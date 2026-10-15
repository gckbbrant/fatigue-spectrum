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
