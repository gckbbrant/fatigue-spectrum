"""Reanalyze unbinned cycle CSV, optionally selected from a portable result bundle.

Uses the native MoonBit from-cycles command. No third-party Python dependencies.
"""
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]


def strict_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result
    def invalid(value):
        raise ValueError("nonfinite JSON number: " + value)
    return json.loads(raw.decode("utf-8-sig"), object_pairs_hook=unique, parse_constant=invalid)


def positive(value):
    if isinstance(value, bool):
        raise ValueError("bin width must be finite and positive")
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise ValueError("bin width must be finite and positive")
    return number


def read_bundle(bundle, case):
    root = bundle.resolve(strict=True)
    manifest_path = root / "manifest.json"
    if manifest_path.is_symlink():
        raise ValueError("manifest must be a regular file inside the bundle")
    raw_manifest = manifest_path.read_bytes()
    manifest = strict_json(raw_manifest)
    if not isinstance(manifest, dict) or type(manifest.get("schema_version")) is not int or manifest["schema_version"] != 1:
        raise ValueError("unsupported bundle schema_version")
    if manifest.get("kind") != "joint-comparison" or manifest.get("status") != "complete" or manifest.get("mean_stress_model") != "none":
        raise ValueError("expected a complete joint-comparison bundle without mean-stress correction")
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries:
        raise ValueError("bundle files must be a nonempty list")
    files, paths, identities = {}, set(), set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("invalid bundle file entry")
        name, role, owner = entry.get("path"), entry.get("role"), entry.get("case")
        if not isinstance(name, str) or not name or "\\" in name or ":" in name:
            raise ValueError("bundle path must be a normalized relative file path")
        path = PurePosixPath(name)
        if path.is_absolute() or any(part in ("", ".", "..") for part in name.split("/")) or name == "manifest.json":
            raise ValueError("bundle path must stay inside the bundle")
        if not isinstance(role, str) or not role or (owner is not None and (not isinstance(owner, str) or not owner)):
            raise ValueError("invalid bundle file role or case")
        key = (role, owner)
        if key in files or name.casefold() in paths:
            raise ValueError("duplicate bundle role or path")
        candidate = root.joinpath(*path.parts)
        resolved = candidate.resolve(strict=True)
        if root not in resolved.parents or not resolved.is_file():
            raise ValueError("bundle file resolves outside the bundle or is not a file")
        identity = (resolved.stat().st_dev, resolved.stat().st_ino)
        if identity in identities:
            raise ValueError("bundle files must be distinct")
        digest = entry.get("sha256")
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            raise ValueError("invalid bundle SHA-256")
        # Only the two analysis inputs need byte snapshots. Large histories and
        # reports are verified in chunks without retaining another full copy.
        raw = None
        calculated = hashlib.sha256()
        if key in (("cycles", case), ("sn_curve", None)):
            raw = candidate.read_bytes()
            calculated.update(raw)
        else:
            with candidate.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    calculated.update(chunk)
        if calculated.hexdigest() != digest:
            raise ValueError("bundle SHA-256 mismatch: " + name)
        files[key] = (name, raw, entry)
        paths.add(name.casefold())
        identities.add(identity)
    try:
        cycles = files[("cycles", case)]
        curve = files[("sn_curve", None)]
    except KeyError:
        raise ValueError("bundle has no cycles for the selected case or no S-N curve") from None
    if cycles[2].get("units") != {"range_mpa": "MPa", "mean_mpa": "MPa", "count": "cycles", "start_index": "sample_index", "end_index": "sample_index"}:
        raise ValueError("unsupported cycle units")
    if curve[2].get("units") != {"amplitude_mpa": "MPa", "cycles_to_failure": "cycles"}:
        raise ValueError("unsupported S-N units")
    width = manifest.get("bin_width_mpa")
    if type(width) not in (int, float):
        raise ValueError("bundle bin_width_mpa must be a number")
    return root, raw_manifest, cycles, curve, positive(width)


def executable():
    subprocess.run(["moon", "build", "--target", "native"], cwd=ROOT, check=True)
    base = ROOT / "_build/native/debug/build/cmd/main/main"
    return next(p for p in (base.with_suffix(".exe"), base) if p.is_file())


def write_json(path, value):
    temporary = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, prefix="reanalysis-", suffix=".json", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(value, stream, indent=2, allow_nan=False)
            stream.write("\n")
        os.replace(str(temporary), str(path))
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def reanalyze(args):
    bundle = None
    if args.bundle is not None:
        if args.case is None:
            raise ValueError("--case is required with --bundle")
        bundle, raw_manifest, cycles, curve, width = read_bundle(args.bundle, args.case)
        source = {"kind": "bundle", "case": args.case, "cycles_file": cycles[0], "manifest_sha256": hashlib.sha256(raw_manifest).hexdigest()}
        cycle_bytes, curve_bytes = cycles[1], curve[1]
        source["sn_file"] = curve[0]
    else:
        if args.case is not None:
            raise ValueError("--case is only valid with --bundle")
        if args.sn is None:
            raise ValueError("--sn is required with --cycles")
        cycle_bytes = args.cycles.read_bytes()
        curve_bytes = None
        width = 10.0
        source = {"kind": "cycles", "cycles_file": str(args.cycles.resolve())}
    if args.sn is not None:
        curve_bytes = args.sn.read_bytes()
        source["sn_file"] = str(args.sn.resolve())
    if args.bin_width is not None:
        width = positive(args.bin_width)
    output = args.output.resolve()
    if bundle is not None and (output == bundle or bundle in output.parents):
        raise ValueError("output must be outside the source bundle")
    inputs = [p for p in (args.cycles, args.sn) if p is not None]
    if bundle is not None:
        inputs += [p for p in bundle.rglob("*") if p.is_file()]
    for path in inputs:
        if output == path.resolve() or (output.exists() and path.exists() and output.samefile(path)):
            raise ValueError("output must not overwrite an input")
    source["cycles_sha256"] = hashlib.sha256(cycle_bytes).hexdigest()
    source["sn_sha256"] = hashlib.sha256(curve_bytes).hexdigest()
    binary = executable()
    # These exact checked bytes drive analysis, even if the source is changed
    # during compilation. No commands from a manifest are ever executed.
    with tempfile.TemporaryDirectory(prefix="cycle-reanalysis-", dir=ROOT / "_build") as directory:
        work = Path(directory)
        (work / "cycles.csv").write_bytes(cycle_bytes)
        (work / "sn.json").write_bytes(curve_bytes)
        p = subprocess.run([str(binary), "from-cycles", str(work / "cycles.csv"), "--sn", str(work / "sn.json"), "--bin-width", str(width), "--json", str(work / "report.json")], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if p.returncode not in (0, 1):
            raise ValueError(p.stderr.strip() or "native cycle analysis failed")
        report = strict_json((work / "report.json").read_bytes())
    report["input_file"] = source["cycles_file"]
    report["reanalysis_source"] = source
    write_json(output, report)
    print(p.stdout, end="")
    if p.stderr:
        print(p.stderr, end="", file=sys.stderr)
    return p.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--bundle", type=Path, help="portable comparison directory; validate every listed file before analysis")
    source.add_argument("--cycles", type=Path, help="standalone unbinned cycles CSV; requires --sn")
    parser.add_argument("--case", help="case name from the bundle, e.g. stiff_joint")
    parser.add_argument("--sn", type=Path, help="new curve; otherwise use the curve captured in the bundle")
    parser.add_argument("--bin-width", help="new range-bin width in MPa; otherwise keep the bundle width or 10 for standalone cycles")
    parser.add_argument("--output", type=Path, required=True, help="JSON result outside the source bundle; replaced only after a valid result")
    args = parser.parse_args()
    try:
        return reanalyze(args)
    except (OSError, ValueError, TypeError, OverflowError, StopIteration, subprocess.CalledProcessError) as error:
        parser.exit(2, "reanalyze_cycles: {}\n".format(error))


if __name__ == "__main__":
    raise SystemExit(main())
