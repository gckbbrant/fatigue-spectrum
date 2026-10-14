///|
/// Split one physical CSV row. Quoted fields support delimiters and doubled quotes.
/// Embedded newlines are rejected rather than silently skipping data.
fn csv_fields(
  line : StringView,
  delimiter : String,
) -> Result[Array[String], FatigueError] {
  let separator = match delimiter {
    "," => ','
    ";" => ';'
    "\t" => '\t'
    _ => return Err(InvalidInput("delimiter must be comma, semicolon or tab"))
  }
  let fields : Array[String] = []
  let field = StringBuilder()
  // 0: plain; 1: quoted; 2: just closed; 3: padding after close.
  let mut state = 0
  for ch in line.to_owned().iter() {
    if state == 1 {
      if ch == '"' {
        state = 2
      } else {
        field.write_char(ch)
      }
    } else if ch == separator {
      fields.push(field.to_string().trim().to_owned())
      field.reset()
      state = 0
    } else if state == 2 && ch == '"' {
      field.write_char('"')
      state = 1
    } else if state == 2 || state == 3 {
      if ch == ' ' || ch == '\t' {
        state = 3
      } else {
        return Err(InvalidInput("unexpected text after quoted CSV field"))
      }
    } else if ch == '"' {
      if !field.to_string().trim().is_empty() {
        return Err(InvalidInput("quote inside unquoted CSV field"))
      }
      field.reset()
      state = 1
    } else {
      field.write_char(ch)
    }
  }
  if state == 1 {
    return Err(
      InvalidInput(
        "unterminated quoted CSV field; multiline fields are unsupported",
      ),
    )
  }
  fields.push(field.to_string().trim().to_owned())
  Ok(fields)
}

///|
fn measurement_columns(
  header : ArrayView[String],
  time_column : String,
  value_column : String,
) -> Result[(Int, Int), FatigueError] {
  let mut time_index = -1
  let mut value_index = -1
  for index, name in header {
    if name == time_column {
      if time_index >= 0 {
        return Err(InvalidInput("duplicate time column: \{time_column}"))
      }
      time_index = index
    }
    if name == value_column {
      if value_index >= 0 {
        return Err(InvalidInput("duplicate value column: \{value_column}"))
      }
      value_index = index
    }
  }
  if time_index < 0 || value_index < 0 {
    Err(InvalidInput("CSV requires columns \{time_column} and \{value_column}"))
  } else {
    Ok((time_index, value_index))
  }
}
