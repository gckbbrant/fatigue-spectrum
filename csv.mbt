///|
/// Read selected measurement columns, converting explicitly to canonical units.
/// Other columns are ignored; every row must match the complete header width.
pub fn parse_stress_csv(
  text : StringView,
  time_column? : String = "time_s",
  stress_column? : String = "stress_mpa",
  time_scale? : Double = 1.0,
  stress_scale? : Double = 1.0,
  delimiter? : String = ",",
) -> Result[Array[StressSample], FatigueError] {
  if time_column.trim().is_empty() ||
    stress_column.trim().is_empty() ||
    time_column == stress_column {
    return Err(
      InvalidInput("time and value columns must be nonempty and distinct"),
    )
  }
  if !finite(time_scale) ||
    time_scale <= 0.0 ||
    !finite(stress_scale) ||
    stress_scale <= 0.0 {
    return Err(InvalidInput("unit scales must be finite and positive"))
  }
  let samples : Array[StressSample] = []
  let mut columns : (Int, Int)? = None
  let mut width = 0
  for index, raw in text.split("\n").collect() {
    let raw = raw.strip_suffix("\r").unwrap_or(raw)
    let line = raw.strip_prefix("\u{FEFF}").unwrap_or(raw)
    if line.trim().is_empty() {
      continue
    }
    let fields = match csv_fields(line, delimiter) {
      Ok(value) => value
      Err(error) =>
        return Err(InvalidInput("CSV line \{index + 1}: \{error.to_repr()}"))
    }
    if columns is None {
      columns = match measurement_columns(fields, time_column, stress_column) {
        Ok(value) => Some(value)
        Err(error) => return Err(error)
      }
      width = fields.length()
      continue
    }
    if fields.length() != width {
      return Err(
        InvalidInput("CSV line \{index + 1}: expected \{width} columns"),
      )
    }
    let (time_index, value_index) = columns.unwrap()
    let time : Double = @string.from_str(fields[time_index]) catch {
      _ =>
        return Err(InvalidInput("CSV line \{index + 1}: invalid time number"))
    }
    let value : Double = @string.from_str(fields[value_index]) catch {
      _ =>
        return Err(InvalidInput("CSV line \{index + 1}: invalid stress number"))
    }
    let sample : StressSample = {
      time_s: time * time_scale,
      stress_mpa: value * stress_scale,
    }
    if !finite(time) || !finite(value) {
      return Err(InvalidInput("CSV line \{index + 1}: values must be finite"))
    }
    if !finite(sample.time_s) ||
      !finite(sample.stress_mpa) ||
      (time != 0.0 && sample.time_s == 0.0) ||
      (value != 0.0 && sample.stress_mpa == 0.0) {
      return Err(
        InvalidInput(
          "CSV line \{index + 1}: unit conversion cannot be represented",
        ),
      )
    }
    if samples.last() is Some(previous) && sample.time_s <= previous.time_s {
      return Err(
        InvalidInput("CSV line \{index + 1}: timestamps must strictly increase"),
      )
    }
    samples.push(sample)
  }
  if samples.is_empty() {
    Err(InvalidInput("CSV has no stress samples"))
  } else {
    Ok(samples)
  }
}

///|
/// Read unbinned cycle records, retaining counts, means and original indices.
/// A header-only file is a valid empty spectrum, as exported for constant stress.
pub fn parse_cycles_csv(
  text : StringView,
) -> Result[Array[Cycle], FatigueError] {
  let cycles : Array[Cycle] = []
  let mut header_seen = false
  for index, raw in text.split("\n").collect() {
    let line = raw.trim().strip_prefix("\u{FEFF}").unwrap_or(raw.trim())
    if line.is_empty() {
      continue
    }
    if !header_seen {
      if line != "range_mpa,mean_mpa,count,start_index,end_index" {
        return Err(
          InvalidInput(
            "CSV header must be range_mpa,mean_mpa,count,start_index,end_index",
          ),
        )
      }
      header_seen = true
      continue
    }
    guard line.split(",").collect() is [range, mean, count, start, end] else {
      return Err(InvalidInput("CSV line \{index + 1}: expected five columns"))
    }
    let cycle : Cycle = {
      range_mpa: @string.from_str(range.trim()),
      mean_mpa: @string.from_str(mean.trim()),
      count: @string.from_str(count.trim()),
      start_index: @string.from_str(start.trim()),
      end_index: @string.from_str(end.trim()),
    } catch {
      _ =>
        return Err(
          InvalidInput("CSV line \{index + 1}: invalid number or integer index"),
        )
    }
    if validate_cycles([cycle]) is Err(_) {
      return Err(
        InvalidInput(
          "CSV line \{index + 1}: invalid range, mean, count or sample indices",
        ),
      )
    }
    cycles.push(cycle)
  }
  if !header_seen {
    Err(InvalidInput("CSV has no cycle header"))
  } else {
    Ok(cycles)
  }
}

///|
pub fn cycles_csv(cycles : ArrayView[Cycle]) -> Result[String, FatigueError] {
  if validate_cycles(cycles) is Err(error) {
    return Err(error)
  }
  let output = StringBuilder()
  output.write_string("range_mpa,mean_mpa,count,start_index,end_index\n")
  for c in cycles {
    output.write_string(
      "\{c.range_mpa},\{c.mean_mpa},\{c.count},\{c.start_index},\{c.end_index}\n",
    )
  }
  Ok(output.to_string())
}
