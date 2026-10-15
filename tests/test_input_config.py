"""Native input preset precedence, strictness and canonical reuse."""
import csv
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AXIS = "stress"
KIND = "stress"
UNIT = "MPa"

class InputConfigCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["moon", "build", "--target", "native"], cwd=ROOT, check=True)
        base = ROOT / "_build/native/debug/build/cmd/main/main"
        cls.binary = next(p for p in (base.with_suffix(".exe"), base) if p.is_file())

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="input-config-", dir=ROOT / "_build")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.config = self.path / "input preset.json"
        self.output = self.path / "canonical.csv"
        self.summary = self.path / "summary.json"
        self.source = ROOT / ("samples/sensor-loads.csv" if KIND == "load" else "samples/sensor-stress.csv")
        self.settings = {"schema_version": 1, "kind": KIND, "time_column": "Clock", AXIS + "_column": "Bridge", "time_unit": "ms", AXIS + "_unit": "kN" if KIND == "load" else "MPa", "delimiter": "semicolon", "skip_rows": 1, "decimal_separator": "comma", AXIS + "_zero": 2.5, AXIS + "_gain": -5 if KIND == "load" else -20}
        self.config.write_text(json.dumps(self.settings), encoding="utf-8-sig")

    def run_cli(self, *args):
        return subprocess.run([str(self.binary)] + [str(a) for a in args], cwd=self.path, capture_output=True, text=True, encoding="utf-8", errors="replace")

    def normalize(self, *extra):
        return self.run_cli("normalize", self.source, "--input-config", self.config, "--csv", self.output, "--json", self.summary, *extra)

    def test_preset_metadata_and_canonical_reuse(self):
        p = self.normalize()
        self.assertEqual(p.returncode, 0, p.stderr)
        expected_csv = "time_s,force_n\n0,0\n1,5000\n2,0\n" if KIND == "load" else (ROOT / "samples/stress.csv").read_text(encoding="utf-8")
        self.assertEqual(self.output.read_text(encoding="utf-8"), expected_csv)
        summary = json.loads(self.summary.read_text(encoding="utf-8"))
        expected_format = {k: v for k, v in self.settings.items() if k not in ("schema_version", "kind")}
        self.assertEqual(summary["source_format"], expected_format)
        canonical = {"time_column": "time_s", AXIS + "_column": "force_n" if KIND == "load" else "stress_mpa", "time_unit": "s", AXIS + "_unit": UNIT, "delimiter": "comma", "skip_rows": 0, "decimal_separator": "dot", AXIS + "_zero": 0, AXIS + "_gain": 1}
        self.assertEqual(summary["canonical_format"], canonical)
        first, second = self.path / "direct.json", self.path / "reused.json"
        if KIND == "load":
            p = self.run_cli("history", ROOT / "samples/joint.json", self.source, "--input-config", self.config, "--json", first)
            self.assertEqual(p.returncode, 0, p.stderr)
            p = self.run_cli("history", ROOT / "samples/joint.json", self.output, "--json", second)
            keys = ("samples", "input_samples", "load_fraction")
        else:
            p = self.run_cli("analyze", self.source, "--input-config", self.config, "--sn", ROOT / "samples/sn.json", "--json", first)
            self.assertEqual(p.returncode, 0, p.stderr)
            p = self.run_cli("analyze", self.output, "--sn", ROOT / "samples/sn.json", "--json", second)
            keys = ("cycles", "spectrum", "damage")
        self.assertEqual(p.returncode, 0, p.stderr)
        a, b = json.loads(first.read_text(encoding="utf-8")), json.loads(second.read_text(encoding="utf-8"))
        for key in keys:
            self.assertEqual(a[key], b[key])

    def test_partial_preset_uses_existing_defaults(self):
        self.config.write_text(json.dumps({"schema_version": 1, "kind": KIND}), encoding="utf-8")
        self.source = ROOT / ("samples/loads.csv" if KIND == "load" else "samples/stress.csv")
        p = self.normalize()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.output.read_text(encoding="utf-8"), self.source.read_text(encoding="utf-8"))
        data = json.loads(self.summary.read_text(encoding="utf-8"))
        self.assertEqual(data["source_format"], data["canonical_format"])

    def test_preset_preserves_source_error_line(self):
        text = self.source.read_text(encoding="utf-8").replace("1000,0;", "0,0;")
        self.source = self.path / "bad.csv"
        self.source.write_text(text, encoding="utf-8")
        p = self.normalize()
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("line 4", p.stderr)
        self.assertFalse(self.output.exists())

    def test_cli_override_does_not_reset_other_preset_values(self):
        p = self.normalize("--" + AXIS + "-gain", "-4" if KIND == "load" else "-10")
        self.assertEqual(p.returncode, 0, p.stderr)
        summary = json.loads(self.summary.read_text(encoding="utf-8"))
        self.assertEqual(summary["source_format"][AXIS + "_zero"], 2.5)
        self.assertEqual(summary["source_format"]["time_unit"], "ms")
        self.assertEqual(summary["maximum_" + AXIS + ("_n" if KIND == "load" else "_mpa")], 4000 if KIND == "load" else 20)

    def test_strict_config_rejections_clear_old_outputs(self):
        bad = [[], {}, {"kind": "other"}, {"schema_version": 2}, {"schema_version": True}, {AXIS + "_gain": 0}, {AXIS + "_gain": "2"}, {AXIS + "_gain": 1e309}, {AXIS + "_zero": True}, {"skip_rows": 1.5}, {"time_unit": "minutes"}, {"unknown": 1}, {"input_config": "nested.json"}, {"time_column": []}]
        for value in bad:
            content = dict(self.settings, **value) if isinstance(value, dict) and value else value
            self.config.write_text(json.dumps(content), encoding="utf-8")
            for path in (self.output, self.summary):
                path.write_text("stale")
            p = self.normalize()
            self.assertEqual(p.returncode, 2, p.stderr)
            self.assertFalse(self.output.exists())
            self.assertFalse(self.summary.exists())

    def test_config_numbers_are_not_rounded_into_integers_or_zero(self):
        original = json.dumps(self.settings)
        cases = [
            original.replace('"schema_version": 1', '"schema_version": 1.000000000000000000001'),
            original.replace('"skip_rows": 1', '"skip_rows": 1.000000000000000000001'),
            original.replace('"skip_rows": 1', '"skip_rows": 1e0'),
            original.replace('"skip_rows": 1', '"skip_rows": 2147483648'),
            original.replace('"' + AXIS + '_zero": 2.5', '"' + AXIS + '_zero": 1e-400'),
        ]
        for text in cases:
            self.config.write_text(text, encoding="utf-8")
            p = self.normalize("--" + AXIS + "-zero", "2.5")
            self.assertEqual(p.returncode, 2, p.stderr)
        self.config.write_text(original.replace('"' + AXIS + '_zero": 2.5', '"' + AXIS + '_zero": 0e100'), encoding="utf-8")
        p = self.normalize("--" + AXIS + "-zero", "2.5")
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_duplicate_decoded_keys_are_rejected(self):
        for duplicate in ('"time_unit":"s","time_unit":"ms"', '"time_unit":"s","\\u0074ime_unit":"ms"'):
            self.config.write_text('{"schema_version":1,"kind":"' + KIND + '",' + duplicate + '}', encoding="utf-8")
            p = self.normalize()
            self.assertEqual(p.returncode, 2, p.stderr)
            self.assertIn("duplicate", p.stderr)

    def test_invalid_config_is_not_hidden_by_cli_override(self):
        self.settings[AXIS + "_gain"] = 0
        self.config.write_text(json.dumps(self.settings))
        p = self.normalize("--" + AXIS + "-gain", "-5")
        self.assertEqual(p.returncode, 2, p.stderr)

    def test_output_cannot_overwrite_input_config(self):
        original = self.config.read_bytes()
        p = self.run_cli("normalize", self.source, "--input-config", self.config, "--json", self.config)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(self.config.read_bytes(), original)
        if KIND == "load":
            p = self.run_cli("history", ROOT / "samples/joint.json", self.source, "--input-config", self.config, "--json", self.config)
        else:
            p = self.run_cli("analyze", self.source, "--input-config", self.config, "--json", self.config)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertEqual(self.config.read_bytes(), original)

    def test_quotes_and_colons_in_column_values_are_not_keys(self):
        self.settings[AXIS + "_column"] = 'Bridge: "A"'
        self.settings["decimal_separator"] = "dot"
        self.settings["skip_rows"] = 0
        self.config.write_text(json.dumps(self.settings))
        self.source = self.path / "quoted.csv"
        with self.source.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, delimiter=";")
            writer.writerows([["Clock", 'Bridge: "A"'], [0, 2.5], [1000, 1.5]])
        p = self.normalize()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(self.summary.read_text(encoding="utf-8"))["source_format"][AXIS + "_column"], 'Bridge: "A"')

    def test_non_measurement_command_rejects_input_config(self):
        arguments = ("analyze", ROOT / "samples/joint.json", "--force", "5000") if KIND == "load" else ("from-cycles", ROOT / "samples/cycles.csv")
        p = self.run_cli(*arguments, "--input-config", self.config)
        self.assertNotEqual(p.returncode, 0)

if __name__ == "__main__":
    unittest.main()
