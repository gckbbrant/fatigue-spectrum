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
