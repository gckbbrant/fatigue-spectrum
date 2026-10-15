"""Native CLI tests for cycles, model coverage, units and file handling."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SpectrumCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["moon", "build", "--target", "native"], cwd=ROOT, check=True)
        base = ROOT / "_build/native/debug/build/cmd/main/main"
        cls.binary = next((p for p in (base.with_suffix(".exe"), base) if p.is_file()), None)
        if cls.binary is None:
            raise FileNotFoundError("moon build produced no native CLI at " + str(base))

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="spectrum-cli-", dir=ROOT / "_build")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)

    def run_cli(self, *args):
        return subprocess.run([str(self.binary)] + [str(a) for a in args], cwd=ROOT, capture_output=True, encoding="utf-8", errors="replace")

    def test_normalize_logger_can_be_reanalyzed_without_import_options(self):
        canonical, summary, report = (self.path / n for n in ("stress.csv", "summary.json", "report.json"))
        p = self.run_cli("normalize", "samples/logger-stress.csv", "--time-column", "Clock", "--stress-column", "Stress", "--time-unit", "ms", "--stress-unit", "kPa", "--delimiter", "semicolon", "--skip-rows", "2", "--decimal-separator", "comma", "--csv", canonical, "--json", summary)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(canonical.read_text(encoding="utf-8"), (ROOT / "samples/stress.csv").read_text(encoding="utf-8"))
        self.assertEqual(json.loads(summary.read_text(encoding="utf-8")), {"input_samples": 5, "time_start_s": 0, "time_end_s": 4, "minimum_stress_mpa": 0, "maximum_stress_mpa": 40})
        p = self.run_cli("analyze", canonical, "--sn", "samples/sn.json", "--json", report)
        self.assertEqual(p.returncode, 0, p.stderr)
        actual = json.loads(report.read_text(encoding="utf-8"))
        expected = json.loads((ROOT / "samples/analysis.json").read_text(encoding="utf-8"))
        for key in ("cycles", "spectrum", "damage"):
            self.assertEqual(actual[key], expected[key])

    def test_normalize_accepts_negative_stress_without_a_curve(self):
        source, csv = self.path / "signed.csv", self.path / "stress.csv"
        source.write_text("time_s,stress_mpa\n-1,-20\n0,10\n", encoding="utf-8")
        p = self.run_cli("normalize", source, "--csv", csv)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("Samples:", p.stdout)
        self.assertEqual(csv.read_text(encoding="utf-8"), source.read_text(encoding="utf-8"))

    def test_normalize_preserves_inputs_and_rejects_shared_outputs(self):
        source = self.path / "stress.csv"
        original = (ROOT / "samples/stress.csv").read_bytes()
        source.write_bytes(original)
        p = self.run_cli("normalize", source, "--csv", str(source.parent) + "/./" + source.name)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(source.read_bytes(), original)
        output = self.path / "result.csv"
        output.write_text("existing", encoding="utf-8")
        p = self.run_cli("normalize", source, "--csv", output, "--json", output)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(output.read_text(encoding="utf-8"), "existing")

    def test_normalize_invalid_source_clears_both_old_exports(self):
        source, csv, summary = (self.path / n for n in ("bad.csv", "stress.csv", "summary.json"))
        source.write_text("metadata\ntime_s,stress_mpa\n0,0\n0,1\n", encoding="utf-8")
        for path in (csv, summary):
            path.write_text("stale", encoding="utf-8")
        p = self.run_cli("normalize", source, "--skip-rows", "1", "--csv", csv, "--json", summary)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("line 4", p.stderr)
        self.assertFalse(csv.exists())
        self.assertFalse(summary.exists())

    def test_damage_from_unbinned_cycles_is_independent_of_plot_width(self):
        values = []
        for width in ("10", "100"):
            result = self.path / "result.json"
            p = self.run_cli("analyze", "samples/stress.csv", "--sn", "samples/sn.json", "--bin-width", width, "--json", result)
            self.assertEqual(p.returncode, 0, p.stderr)
            data = json.loads(result.read_text(encoding="utf-8"))
            self.assertEqual(len(data["cycles"]), 3)
            values.append(data["damage"]["total_damage"])
        self.assertEqual(values[0], values[1])
        self.assertAlmostEqual(values[0], 0.000017)

    def test_unsupported_amplitude_has_no_total_damage(self):
        result = self.path / "outside.json"
        p = self.run_cli("analyze", "samples/outside.csv", "--sn", "samples/sn.json", "--json", result)
        self.assertEqual(p.returncode, 1, p.stderr)
        damage = json.loads(result.read_text(encoding="utf-8"))["damage"]
        self.assertNotIn("total_damage", damage)
        self.assertEqual(len(damage["out_of_range_cycles"]), 2)

    def test_constant_stress_has_zero_cycles_and_damage(self):
        result = self.path / "constant.json"
        p = self.run_cli("analyze", "samples/constant.csv", "--sn", "samples/sn.json", "--json", result)
        self.assertEqual(p.returncode, 0, p.stderr)
        data = json.loads(result.read_text(encoding="utf-8"))
        self.assertEqual(data["cycles"], [])
        self.assertEqual(data["damage"]["total_damage"], 0)

    def test_spectrum_without_a_curve_is_standalone(self):
        result = self.path / "cycles.json"
        p = self.run_cli("analyze", "samples/stress.csv", "--json", result)
        self.assertEqual(p.returncode, 0, p.stderr)
        data = json.loads(result.read_text(encoding="utf-8"))
        self.assertEqual(len(data["cycles"]), 3)
        self.assertNotIn("damage", data)

    def test_invalid_units_clear_old_output(self):
        source, result = self.path / "wrong.csv", self.path / "report.json"
        source.write_text("time_s,force_n\n0,1\n1,2\n", encoding="utf-8")
        result.write_text("old result", encoding="utf-8")
        p = self.run_cli("analyze", source, "--json", result)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertFalse(result.exists())

    def test_measurement_column_mapping_and_units(self):
        source, result = self.path / "instrument.csv", self.path / "analysis.json"
        source.write_text('note;Stress;Clock\n"sensor; A";0;0\n"sensor B";30000;1000\n"sensor C";10000;2000\n"sensor D";40000;3000\n"sensor E";0;4000\n', encoding="utf-8")
        p = self.run_cli("analyze", source, "--time-column", "Clock", "--stress-column", "Stress", "--time-unit", "ms", "--stress-unit", "kPa", "--delimiter", "semicolon", "--sn", "samples/sn.json", "--json", result)
        self.assertEqual(p.returncode, 0, p.stderr)
        actual = json.loads(result.read_text(encoding="utf-8"))
        expected = json.loads((ROOT / "samples/analysis.json").read_text(encoding="utf-8"))
        for key in ("cycles", "spectrum", "damage"):
            self.assertEqual(actual[key], expected[key])

    def test_preamble_and_decimal_comma_match_canonical_stress(self):
        source, result = self.path / "locale.csv", self.path / "analysis.json"
        source.write_text('instrument export\nsep=;\nClock;Stress\n0,0;0,0\n1000,0;30000,0\n2000,0;10000,0\n3000,0;40000,0\n4000,0;0,0\n', encoding="utf-8")
        p = self.run_cli("analyze", source, "--time-column", "Clock", "--stress-column", "Stress", "--time-unit", "ms", "--stress-unit", "kPa", "--delimiter", "semicolon", "--skip-rows", "2", "--decimal-separator", "comma", "--sn", "samples/sn.json", "--json", result)
        self.assertEqual(p.returncode, 0, p.stderr)
        actual = json.loads(result.read_text(encoding="utf-8"))
        expected = json.loads((ROOT / "samples/analysis.json").read_text(encoding="utf-8"))
        for key in ("cycles", "spectrum", "damage"):
            self.assertEqual(actual[key], expected[key])

    def test_bad_decimal_after_preamble_keeps_source_line_number(self):
        source, result = self.path / "invalid.csv", self.path / "result.json"
        source.write_text('instrument export\nsep=;\ntime_s;stress_mpa\n0;1.234,5\n', encoding="utf-8")
        result.write_text("stale", encoding="utf-8")
        p = self.run_cli("analyze", source, "--delimiter", "semicolon", "--skip-rows", "2", "--decimal-separator", "comma", "--json", result)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("line 4", p.stderr)
        self.assertFalse(result.exists())

    def test_cycle_import_rejects_measurement_only_options(self):
        for key, value in (("--stress-unit", "Pa"), ("--skip-rows", "2"), ("--decimal-separator", "comma")):
            p = self.run_cli("from-cycles", "samples/cycles.csv", key, value)
            self.assertNotEqual(p.returncode, 0)

    def test_unknown_stress_unit_clears_old_result(self):
        result = self.path / "result.json"
        result.write_text("old result", encoding="utf-8")
        p = self.run_cli("analyze", "samples/stress.csv", "--stress-unit", "psi", "--json", result)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("stress-unit", p.stderr)
        self.assertFalse(result.exists())

    def test_input_alias_is_preserved(self):
        source = self.path / "stress.csv"
        original = (ROOT / "samples/stress.csv").read_bytes()
        source.write_bytes(original)
        p = self.run_cli("analyze", source, "--json", str(source.parent) + "/./" + source.name)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(source.read_bytes(), original)

    def test_cycle_export_can_be_reanalyzed_with_the_same_damage(self):
        cycles, first, second = self.path / "cycles.csv", self.path / "first.json", self.path / "second.json"
        p = self.run_cli("analyze", "samples/stress.csv", "--sn", "samples/sn.json", "--json", first, "--cycles", cycles)
        self.assertEqual(p.returncode, 0, p.stderr)
        p = self.run_cli("from-cycles", cycles, "--sn", "samples/sn.json", "--json", second)
        self.assertEqual(p.returncode, 0, p.stderr)
        original = json.loads(first.read_text(encoding="utf-8"))
        imported = json.loads(second.read_text(encoding="utf-8"))
        for key in ("cycles", "spectrum", "damage"):
            self.assertEqual(imported[key], original[key])
        self.assertNotIn("input_samples", imported)

    def test_header_only_cycle_export_has_zero_damage(self):
        source, result = self.path / "empty.csv", self.path / "empty.json"
        source.write_text("range_mpa,mean_mpa,count,start_index,end_index\n", encoding="utf-8")
        p = self.run_cli("from-cycles", source, "--sn", "samples/sn.json", "--json", result)
        self.assertEqual(p.returncode, 0, p.stderr)
        data = json.loads(result.read_text(encoding="utf-8"))
        self.assertEqual(data["cycles"], [])
        self.assertEqual(data["damage"]["total_damage"], 0)

    def test_counted_cycles_and_incomplete_coverage(self):
        source, result = self.path / "counted.csv", self.path / "counted.json"
        source.write_text("range_mpa,mean_mpa,count,start_index,end_index\n20,5,100,0,1\n400,0,0.5,1,2\n", encoding="utf-8")
        p = self.run_cli("from-cycles", source, "--sn", "samples/sn.json", "--json", result)
        self.assertEqual(p.returncode, 1, p.stderr)
        damage = json.loads(result.read_text(encoding="utf-8"))["damage"]
        self.assertNotIn("total_damage", damage)
        self.assertAlmostEqual(damage["evaluated_damage"], 0.0001)
        self.assertEqual(damage["out_of_range_cycles"], [1])

    def test_invalid_cycle_row_clears_old_output_and_preserves_input(self):
        source, result = self.path / "invalid.csv", self.path / "result.json"
        original = "range_mpa,mean_mpa,count,start_index,end_index\n20,0,1,2,1\n"
        source.write_text(original, encoding="utf-8")
        result.write_text("old result", encoding="utf-8")
        p = self.run_cli("from-cycles", source, "--json", result)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("CSV line 2", p.stderr)
        self.assertFalse(result.exists())
        p = self.run_cli("from-cycles", source, "--cycles", source)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(source.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
