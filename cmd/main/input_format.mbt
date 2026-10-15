///|
struct InputFormat {
  time_column : String
  stress_column : String
  time_unit : String
  stress_unit : String
  delimiter : String
  skip_rows : Int
  decimal_separator : String
  stress_zero : Double
  stress_gain : Double
} derive(ToJson)

///|
fn InputFormat::options(self : InputFormat) -> Map[String, Array[String]] {
  {
    "time-column": [self.time_column],
    "stress-column": [self.stress_column],
    "time-unit": [self.time_unit],
    "stress-unit": [self.stress_unit],
    "delimiter": [self.delimiter],
    "skip-rows": [self.skip_rows.to_string()],
    "decimal-separator": [self.decimal_separator],
    "stress-zero": [self.stress_zero.to_string()],
    "stress-gain": [self.stress_gain.to_string()],
  }
}

///|
fn format_from_values(values : Map[String, Array[String]]) -> InputFormat raise {
  let time_column = optional(values, "time-column").unwrap_or("time_s")
  let value_column = optional(values, "stress-column").unwrap_or("stress_mpa")
  if time_column.trim().is_empty() ||
    value_column.trim().is_empty() ||
    time_column == value_column {
    fail("time and value columns must be nonempty and distinct")
  }
  ignore(input_time_scale(values))
  ignore(input_stress_scale(values))
  ignore(input_delimiter(values))
  let skip_rows = input_skip_rows(values)
  ignore(input_decimal_comma(values))
  let zero = calibration_number(values, "stress-zero", 0.0)
  let gain = calibration_number(values, "stress-gain", 1.0)
  if zero.is_nan() ||
    zero.is_inf() ||
    gain.is_nan() ||
    gain.is_inf() ||
    gain == 0.0 {
    fail("calibration zero must be finite; gain must be finite and nonzero")
  }
  {
    time_column,
    stress_column: value_column,
    time_unit: optional(values, "time-unit").unwrap_or("s"),
    stress_unit: optional(values, "stress-unit").unwrap_or("MPa"),
    delimiter: optional(values, "delimiter").unwrap_or("comma"),
    skip_rows,
    decimal_separator: optional(values, "decimal-separator").unwrap_or("dot"),
    stress_zero: zero,
    stress_gain: gain,
  }
}
