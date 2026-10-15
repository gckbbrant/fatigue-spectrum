///|
// JSON grammar and Unicode escapes remain the standard parser's responsibility.
// Its object map overwrites duplicate keys, so inspect decoded key tokens too.
// Only a flat scalar object is accepted by the schema below.
fn strict_config_object(
  raw : StringView,
) -> (Map[String, Json], Map[String, String]) raise {
  let text = raw.strip_prefix("\u{FEFF}").unwrap_or(raw)
  guard @json.parse(text) is Object(fields) else {
    fail("input config must be a JSON object")
  }
  let seen : Map[String, Bool] = Map([])
  let lexemes : Map[String, String] = Map([])
  let value_token = StringBuilder()
  let mut capturing = false
  let mut value_key = ""
  let token = StringBuilder()
  let mut quoted = false
  let mut escaped = false
  let mut depth = 0
  let mut candidate : String? = None
  for ch in text.to_owned().iter() {
    if capturing && !quoted && depth == 1 && (ch == ',' || ch == '}') {
      lexemes[value_key] = value_token.to_string().trim().to_owned()
      capturing = false
    } else if capturing {
      value_token.write_char(ch)
    }
    if quoted {
      token.write_char(ch)
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        quoted = false
        candidate = Some(@json.from_json(@json.parse(token.to_string())))
      }
    } else {
      match ch {
        '"' => {
          quoted = true
          token.reset()
          token.write_char(ch)
        }
        '{' | '[' => {
          depth += 1
          candidate = None
        }
        '}' | ']' => {
          depth -= 1
          candidate = None
        }
        ':' => {
          if depth == 1 && candidate is Some(key) {
            if seen.contains(key) {
              fail("duplicate input configuration key: \{key}")
            }
            seen[key] = true
            value_key = key
            value_token.reset()
            capturing = true
          }
          candidate = None
        }
        ' ' | '\t' | '\r' | '\n' => ()
        _ => candidate = None
      }
    }
  }
  (fields, lexemes)
}

///|
// Ignore exponent digits: 0e100 is still an exact zero, while 1e-400 is not.
fn nonzero_mantissa(text : String) -> Bool {
  for ch in text.iter() {
    if ch == 'e' || ch == 'E' {
      break
    }
    if ch >= '1' && ch <= '9' {
      return true
    }
  }
  false
}

///|
fn config_options(text : StringView) -> Map[String, Array[String]] raise {
  let (fields, lexemes) = strict_config_object(text)
  guard fields.get("schema_version") is Some(Number(version, ..)) &&
    version == 1.0 &&
    lexemes.get("schema_version") == Some("1") else {
    fail("input config schema_version must be 1")
  }
  guard fields.get("kind") is Some(String(kind)) && kind == "stress" else {
    fail("input config kind must be stress")
  }
  let strings = [
    "time_column", "stress_column", "time_unit", "stress_unit", "delimiter", "decimal_separator",
  ]
  let result : Map[String, Array[String]] = Map([])
  for key, value in fields {
    if key == "schema_version" || key == "kind" {
      continue
    }
    let option = key.replace(old="_", new="-")
    if strings.contains(key) {
      guard value is String(text) else {
        fail("input config \{key} must be a string")
      }
      result[option] = [text]
    } else if key == "skip_rows" {
      guard value is Number(_, ..) else {
        fail(
          "input config skip_rows must be a nonnegative 32-bit integer literal",
        )
      }
      let rows : Int = @string.from_str(lexemes.get(key).unwrap()) catch {
        _ =>
          fail(
            "input config skip_rows must be a nonnegative 32-bit integer literal",
          )
      }
      if rows < 0 {
        fail("input config skip_rows must be nonnegative")
      }
      result[option] = [rows.to_string()]
    } else if key == "stress_zero" || key == "stress_gain" {
      guard value is Number(number, ..) && !number.is_inf() && !number.is_nan() else {
        fail("input config \{key} must be a finite number")
      }
      if number == 0.0 && nonzero_mantissa(lexemes.get(key).unwrap()) {
        fail("input config \{key}: number cannot be represented")
      }
      result[option] = [number.to_string()]
    } else {
      fail("unknown input configuration key: \{key}")
    }
  }
  // Validate the preset itself before any CLI override can hide a bad value.
  ignore(format_from_values(result))
  result
}

///|
async fn measurement_format(values : Map[String, Array[String]]) -> InputFormat {
  let merged : Map[String, Array[String]] = match
    optional(values, "input-config") {
    Some(path) => config_options(@fs.read_file(path).text())
    None => Map([])
  }
  for key, value in values {
    merged[key] = value
  }
  format_from_values(merged)
}
