"""Compare the native CLI against rainflow 3.2.0 on reproducible signals.

Install the optional reference dependency: python -m pip install rainflow==3.2.0
The MoonBit library and CLI do not depend on Python.
"""
import argparse
import json
import math
import platform
import random
import subprocess
import tempfile
from pathlib import Path

import rainflow


def reference(values):
    # rainflow 3.2.0 omits the last endpoint for length-two inputs.
    # This tool deliberately counts a distinct endpoint pair as a half cycle.
    if len(values) == 2 and values[0] != values[1]:
        return [(abs(values[1] - values[0]), (values[0] + values[1]) / 2, 0.5, 0, 1)]
    return [c for c in rainflow.extract_cycles(values) if c[0] != 0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=int, default=500)
    parser.add_argument("--seed", type=int, default=20261013)
    parser.add_argument("--output", type=Path, default=Path("samples/reference-check.json"))
    args = parser.parse_args()
    if args.cases < 0:
        parser.error("--cases must be nonnegative")
    if rainflow.__version__ != "3.2.0":
        raise RuntimeError("reference must be rainflow 3.2.0")
    root = Path(__file__).resolve().parents[1]
    subprocess.run(["moon", "build", "--target", "native"], cwd=root, check=True)
    executable = root / "_build/native/debug/build/cmd/main/main"
    if platform.system() == "Windows":
        executable = executable.with_suffix(".exe")
    fixed = [
        [0], [1, 1], [1, 2], [2, 1], [1, 1, 1], [0, 1, 2],
        [0, 3, 1, 4, 0], [0, 3, 3, 1, 4, 0], [0, 0, 3, 0, 0],
        [3, 3, 1, 1, 4, 4, 0], [0, 1, 0, 1, 0], [0, -1, 2, -3, 0],
    ]
    rng = random.Random(args.seed)
    signals = list(fixed)
    for case in range(args.cases):
        size = rng.randint(3, 180)
        values = []
        for _ in range(size):
            if values and rng.random() < 0.25:
                values.append(values[-1])
            elif case % 2:
                values.append(rng.uniform(-500, 500))
            else:
                values.append(rng.randint(-50, 50))
        signals.append(values)
    max_error = 0.0
    compared_cycles = 0
    fields = ("range_mpa", "mean_mpa", "count", "start_index", "end_index")
    with tempfile.TemporaryDirectory(prefix="rainflow-reference-", dir=root / "_build") as directory:
        directory = Path(directory)
        source, result = directory / "stress.csv", directory / "cycles.json"
        for index, values in enumerate(signals):
            source.write_text("time_s,stress_mpa\n" + "".join("{},{}\n".format(i, v) for i, v in enumerate(values)), encoding="utf-8")
            process = subprocess.run([str(executable), "analyze", str(source), "--json", str(result)], cwd=root, capture_output=True, text=True)
            if process.returncode:
                raise AssertionError("case {}: {}".format(index, process.stderr))
            actual = json.loads(result.read_text(encoding="utf-8"))["cycles"]
            expected = reference(values)
            if len(actual) != len(expected):
                raise AssertionError("case {}: cycle lengths {} != {}; signal={!r}".format(index, len(actual), len(expected), values))
            for a, b in zip(actual, expected):
                for key, wanted in zip(fields, b):
                    got = a[key]
                    if key.endswith("index") or key == "count":
                        equal = got == wanted
                    else:
                        max_error = max(max_error, abs(got - wanted))
                        equal = math.isclose(got, wanted, rel_tol=1e-12, abs_tol=1e-10)
                    if not equal:
                        raise AssertionError("case {}: {} {} != {}; signal={!r}".format(index, key, got, wanted, values))
            compared_cycles += len(expected)
    report = {
        "command": "python scripts/compare_rainflow.py --cases {} --seed {}".format(args.cases, args.seed),
        "reference": "rainflow==3.2.0",
        "python": platform.python_version(),
        "moon": subprocess.check_output(["moon", "version"], cwd=root, text=True).splitlines()[0],
        "seed": args.seed,
        "fixed_signals": len(fixed),
        "random_signals": args.cases,
        "compared_cycle_records": compared_cycles,
        "mismatches": 0,
        "max_absolute_numeric_difference": max_error,
        "relative_tolerance": 1e-12,
        "absolute_tolerance": 1e-10,
        "intentional_endpoint_policy": "two distinct samples form a half cycle; zero-range cycles are omitted",
    }
    output = args.output if args.output.is_absolute() else root / args.output
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
