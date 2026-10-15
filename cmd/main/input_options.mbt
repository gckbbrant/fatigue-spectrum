///|
fn input_time_scale(values : Map[String, Array[String]]) -> Double raise {
  match optional(values, "time-unit") {
    None | Some("s") => 1.0
    Some("ms") => 0.001
    _ => fail("time-unit must be s or ms")
  }
}

///|
fn input_delimiter(values : Map[String, Array[String]]) -> String raise {
  match optional(values, "delimiter") {
    None | Some("comma") => ","
    Some("semicolon") => ";"
    Some("tab") => "\t"
    _ => fail("delimiter must be comma, semicolon or tab")
  }
}

///|
fn input_stress_scale(values : Map[String, Array[String]]) -> Double raise {
  match optional(values, "stress-unit") {
    None | Some("MPa") => 1.0
    Some("kPa") => 0.001
    Some("Pa") => 0.000001
    _ => fail("stress-unit must be MPa, kPa or Pa")
  }
}

///|
fn input_skip_rows(values : Map[String, Array[String]]) -> Int raise {
  let rows : Int = match optional(values, "skip-rows") {
    None => 0
    Some(text) => @string.from_str(text)
  }
  if rows < 0 {
    fail("skip-rows must be nonnegative")
  }
  rows
}

///|
fn input_decimal_comma(values : Map[String, Array[String]]) -> Bool raise {
  match optional(values, "decimal-separator") {
    None | Some("dot") => false
    Some("comma") => true
    _ => fail("decimal-separator must be dot or comma")
  }
}

///|
fn measurement_options() -> Array[@argparse.OptionArg] {
  [
    OptionArg("time-column", about="Time column name; default time_s."),
    OptionArg("stress-column", about="Stress column name; default stress_mpa."),
    OptionArg("time-unit", about="Input time unit: s or ms; default s."),
    OptionArg(
      "stress-unit",
      about="Input stress unit: MPa, kPa or Pa; default MPa.",
    ),
    OptionArg(
      "stress-zero",
      about="Raw channel reading at zero stress; default 0.",
      allow_hyphen_values=true,
    ),
    OptionArg(
      "stress-gain",
      about="Declared input stress unit per raw reading, finite and nonzero; default 1.",
      allow_hyphen_values=true,
    ),
    OptionArg("delimiter", about="CSV separator: comma, semicolon or tab."),
    OptionArg(
      "skip-rows",
      about="Physical preamble lines before header; default 0.",
    ),
    OptionArg(
      "decimal-separator",
      about="Input decimal separator: dot or comma; default dot.",
    ),
  ]
}

///|
fn calibration_number(
  values : Map[String, Array[String]],
  key : String,
  fallback : Double,
) -> Double raise {
  match optional(values, key) {
    None => fallback
    Some(text) =>
      @string.from_str(text) catch {
        _ => fail("\{key} must be a number")
      }
  }
}
