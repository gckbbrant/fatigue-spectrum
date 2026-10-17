"""Exercise cycle reuse through the real native executable."""
import hashlib
import argparse
import importlib.util
import json
import os
import subprocess
import sys
import shutil
import tempfile
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class CycleReuse(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["moon", "build", "--target", "native"], cwd=ROOT, check=True)
        base = ROOT / "_build/native/debug/build/cmd/main/main"
        cls.binary = next(p for p in (base.with_suffix(".exe"), base) if p.is_file())

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="cycle-reuse-", dir=ROOT / "_build")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.output = self.path / "new results/report.json"

    def native(self, *args):
        p = subprocess.run([str(self.binary)] + [str(x) for x in args], capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_native_roundtrip_keeps_negative_means_half_cycles_and_empty_cycles(self):
        for values in ([-30, -10, -30, -5, -30], [7, 7, 7]):
            stress, cycles, direct, reused = [self.path / n for n in ("stress.csv", "cycles.csv", "direct.json", "reused.json")]
            stress.write_text("time_s,stress_mpa\n" + "".join(f"{i},{v}\n" for i, v in enumerate(values)), encoding="utf-8")
            self.native("analyze", stress, "--sn", ROOT / "samples/sn.json", "--cycles", cycles, "--json", direct)
            self.native("from-cycles", cycles, "--sn", ROOT / "samples/sn.json", "--json", reused)
            a, b = [json.loads(p.read_text(encoding="utf-8")) for p in (direct, reused)]
            for key in ("cycles", "spectrum", "damage"):
                self.assertEqual(a[key], b[key])
            self.assertNotIn("input_samples", b)
            if len(set(values)) > 1:
                self.assertTrue(any(c["count"] == 0.5 for c in a["cycles"]))
                self.assertTrue(all(c["mean_mpa"] < 0 for c in a["cycles"]))
            else:
                self.assertEqual(b["cycles"], [])

    def test_standalone_cycle_file_matches_native_analysis(self):
        p = self.helper("--cycles", ROOT / "samples/cycles.csv", "--sn", ROOT / "samples/sn.json")
        self.assertEqual(p.returncode, 0, p.stderr)
        result = json.loads(self.output.read_text(encoding="utf-8"))
        expected = json.loads((ROOT / "samples/analysis.json").read_text(encoding="utf-8"))
        for key in ("cycles", "spectrum", "damage"):
            self.assertEqual(result[key], expected[key])
        self.assertNotIn("input_samples", result)
        self.assertEqual(result["reanalysis_source"]["cycles_sha256"], hashlib.sha256((ROOT / "samples/cycles.csv").read_bytes()).hexdigest())

    def helper(self, *args):
        return subprocess.run([sys.executable, str(ROOT / "scripts/reanalyze_cycles.py"), "--output", str(self.output)] + [str(x) for x in args], cwd=self.path, capture_output=True, text=True, encoding="utf-8", errors="replace")

    def bundle(self):
        bundle = self.path / "original bundle"
        bundle.mkdir()
        stress = bundle / "case-stress.csv"
        stress.write_text("time_s,stress_mpa\n0,-30\n1,-10\n2,-30\n3,-5\n4,-30\n", encoding="utf-8")
        (bundle / "sn.json").write_bytes((ROOT / "samples/sn.json").read_bytes())
        self.native("analyze", stress, "--sn", bundle / "sn.json", "--cycles", bundle / "case-cycles.csv", "--json", bundle / "case-fatigue.json", "--bin-width", "7")
        cycle_units = {"range_mpa": "MPa", "mean_mpa": "MPa", "count": "cycles", "start_index": "sample_index", "end_index": "sample_index"}
        entries = []
        for name, role, units in (("case-cycles.csv", "cycles", cycle_units), ("sn.json", "sn_curve", {"amplitude_mpa": "MPa", "cycles_to_failure": "cycles"}), ("case-stress.csv", "stress", None), ("case-fatigue.json", "fatigue", None)):
            entry = {"path": name, "role": role, "sha256": hashlib.sha256((bundle / name).read_bytes()).hexdigest()}
            if role != "sn_curve":
                entry["case"] = "example"
            if units:
                entry["units"] = units
            entries.append(entry)
        manifest = {"schema_version": 1, "kind": "joint-comparison", "status": "complete", "mean_stress_model": "none", "bin_width_mpa": 7, "files": entries}
        self.save_manifest(bundle, manifest)
        return bundle, manifest

    def save_manifest(self, bundle, manifest):
        (bundle / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def test_moved_bundle_reuses_width_and_can_change_bins_without_changing_damage(self):
        bundle, _ = self.bundle()
        original = json.loads((bundle / "case-fatigue.json").read_text(encoding="utf-8"))
        moved = self.path / "moved bundle"
        shutil.move(str(bundle), moved)
        for extra in ((), ("--bin-width", "20")):
            p = self.helper("--bundle", moved, "--case", "example", *extra)
            self.assertEqual(p.returncode, 0, p.stderr)
            result = json.loads(self.output.read_text(encoding="utf-8"))
            for key in (("cycles", "spectrum", "damage") if not extra else ("cycles", "damage")):
                self.assertEqual(result[key], original[key])
            self.assertEqual(result["bin_width_mpa"], 7 if not extra else 20)
            self.assertNotIn("input_samples", result)
            self.assertEqual(result["input_file"], "case-cycles.csv")

    def test_new_curve_keeps_incomplete_coverage_status_and_no_total(self):
        bundle, _ = self.bundle()
        narrow = self.path / "narrow.json"
        narrow.write_text('[{"amplitude_mpa":1,"cycles_to_failure":100},{"amplitude_mpa":2,"cycles_to_failure":10}]', encoding="utf-8")
        p = self.helper("--bundle", bundle, "--case", "example", "--sn", narrow)
        self.assertEqual(p.returncode, 1, p.stderr)
        result = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertNotIn("total_damage", result["damage"])
        self.assertTrue(result["damage"]["out_of_range_cycles"])
        self.assertEqual(result["reanalysis_source"]["sn_sha256"], hashlib.sha256(narrow.read_bytes()).hexdigest())

    def test_empty_standalone_cycles_have_zero_damage(self):
        empty = self.path / "empty.csv"
        empty.write_text("range_mpa,mean_mpa,count,start_index,end_index\n", encoding="utf-8")
        p = self.helper("--cycles", empty, "--sn", ROOT / "samples/sn.json")
        self.assertEqual(p.returncode, 0, p.stderr)
        result = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertEqual(result["cycles"], [])
        self.assertEqual(result["damage"]["total_damage"], 0)
        self.assertNotIn("input_samples", result)

    def test_manifest_errors_preserve_old_output(self):
        bundle, original = self.bundle()
        self.output.parent.mkdir()
        self.output.write_text("keep", encoding="utf-8")
        mutations = [lambda m: m.update(schema_version=2), lambda m: m.update(schema_version=True), lambda m: m.update(kind="other"), lambda m: m.update(status="partial"), lambda m: m.update(mean_stress_model="goodman"), lambda m: m.update(bin_width_mpa=0), lambda m: m["files"].append(dict(m["files"][0])), lambda m: m["files"][0].update(units={"range_mpa": "Pa"}), lambda m: m["files"][0].update(path="../outside.csv"), lambda m: m["files"][0].update(path="/tmp/cycles.csv"), lambda m: m["files"][0].update(path="C:/cycles.csv"), lambda m: m["files"][0].update(path="./case-cycles.csv"), lambda m: m["files"][0].update(path="bad\\name.csv"), lambda m: m["files"][0].update(sha256="a" * 64), lambda m: m["files"][0].update(path="missing.csv")]
        for change in mutations:
            manifest = json.loads(json.dumps(original))
            change(manifest)
            self.save_manifest(bundle, manifest)
            p = self.helper("--bundle", bundle, "--case", "example")
            self.assertEqual(p.returncode, 2, p.stderr)
            self.assertNotIn("Traceback", p.stderr)
            self.assertEqual(self.output.read_text(encoding="utf-8"), "keep")
        self.save_manifest(bundle, original)
        (bundle / "case-stress.csv").write_text("changed unselected artifact", encoding="utf-8")
        p = self.helper("--bundle", bundle, "--case", "example")
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("mismatch", p.stderr)

    def test_duplicate_manifest_keys_are_rejected(self):
        bundle, _ = self.bundle()
        raw = (bundle / "manifest.json").read_text(encoding="utf-8")
        (bundle / "manifest.json").write_text(raw.replace('"schema_version": 1', '"schema_version":1,"\\u0073chema_version":1'), encoding="utf-8")
        p = self.helper("--bundle", bundle, "--case", "example")
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("duplicate", p.stderr)

    def test_outputs_cannot_overwrite_bundle_or_standalone_inputs(self):
        bundle, _ = self.bundle()
        original = (bundle / "case-cycles.csv").read_bytes()
        for output in (bundle / "case-cycles.csv", bundle / "manifest.json", bundle / "new.json"):
            p = self.helper("--bundle", bundle, "--case", "example", "--output", output)
            self.assertEqual(p.returncode, 2, p.stderr)
        p = self.helper("--cycles", bundle / "case-cycles.csv", "--sn", bundle / "sn.json", "--output", bundle / "case-cycles.csv")
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual((bundle / "case-cycles.csv").read_bytes(), original)
        alias = self.path / "alias.csv"
        os.link(bundle / "case-cycles.csv", alias)
        p = self.helper("--bundle", bundle, "--case", "example", "--output", alias)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(alias.read_bytes(), original)

    def test_symlink_leaving_bundle_is_rejected(self):
        bundle, manifest = self.bundle()
        outside = self.path / "outside.csv"
        outside.write_bytes((bundle / "case-cycles.csv").read_bytes())
        link = bundle / "linked.csv"
        try:
            link.symlink_to(outside)
        except OSError:
            self.skipTest("symlink creation is unavailable on this host")
        manifest["files"][0]["path"] = link.name
        self.save_manifest(bundle, manifest)
        p = self.helper("--bundle", bundle, "--case", "example")
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("outside", p.stderr)

    def test_missing_case_and_invalid_cli_options(self):
        bundle, _ = self.bundle()
        for args in (("--bundle", bundle), ("--bundle", bundle, "--case", "absent"), ("--cycles", ROOT / "samples/cycles.csv"), ("--cycles", ROOT / "samples/cycles.csv", "--sn", ROOT / "samples/sn.json", "--case", "example"), ("--bundle", bundle, "--case", "example", "--bin-width", "nan")):
            p = self.helper(*args)
            self.assertEqual(p.returncode, 2, p.stderr)
            self.assertFalse(self.output.exists())

    def script(self):
        spec = importlib.util.spec_from_file_location("cycle_reanalysis", ROOT / "scripts/reanalyze_cycles.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_checked_bytes_survive_sources_changing_during_build(self):
        bundle, _ = self.bundle()
        expected = json.loads((bundle / "case-fatigue.json").read_text(encoding="utf-8"))
        before = (bundle / "case-cycles.csv").read_bytes()
        module = self.script()
        args = argparse.Namespace(bundle=bundle, case="example", cycles=None, sn=None, bin_width=None, output=self.output)
        build = module.executable
        def changing_build():
            binary = build()
            (bundle / "case-cycles.csv").write_text("changed", encoding="utf-8")
            (bundle / "sn.json").write_text("changed", encoding="utf-8")
            return binary
        with mock.patch.object(module, "executable", side_effect=changing_build):
            self.assertEqual(module.reanalyze(args), 0)
        result = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertEqual(result["damage"], expected["damage"])
        self.assertEqual(result["reanalysis_source"]["cycles_sha256"], hashlib.sha256(before).hexdigest())

    def test_invalid_cycles_and_write_failure_do_not_replace_existing_output(self):
        self.output.parent.mkdir()
        self.output.write_text("keep", encoding="utf-8")
        invalid = self.path / "invalid.csv"
        invalid.write_text("range_mpa,mean_mpa,count,start_index,end_index\n20,0,1,2,1\n", encoding="utf-8")
        p = self.helper("--cycles", invalid, "--sn", ROOT / "samples/sn.json")
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "keep")
        module = self.script()
        with mock.patch.object(module.os, "replace", side_effect=OSError("simulated write failure")):
            with self.assertRaises(OSError):
                module.write_json(self.output, {"complete": True})
        self.assertEqual(self.output.read_text(encoding="utf-8"), "keep")
        self.assertEqual(list(self.output.parent.glob("reanalysis-*.json")), [])


if __name__ == "__main__":
    unittest.main()
