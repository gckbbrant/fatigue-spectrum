///|
/// Parse an unquoted two-column MPa CSV with strictly increasing timestamps.
pub fn parse_stress_csv(
  text : StringView,
) -> Result[Array[StressSample], FatigueError] {
  let samples : Array[StressSample] = []
  let mut header_seen = false
  for index, raw in text.split("\n").collect() {
    let line = raw.trim().strip_prefix("\u{FEFF}").unwrap_or(raw.trim())
    if line.is_empty() {
      continue
    }
    if !header_seen {
      if line != "time_s,stress_mpa" {
        return Err(InvalidInput("CSV header must be time_s,stress_mpa"))
      }
      header_seen = true
      continue
    }
    guard line.split(",").collect() is [time, stress] else {
      return Err(InvalidInput("CSV line \{index + 1}: expected two columns"))
    }
    let sample : StressSample = {
      time_s: @string.from_str(time.trim()),
      stress_mpa: @string.from_str(stress.trim()),
    } catch {
      _ => return Err(InvalidInput("CSV line \{index + 1}: invalid number"))
    }
    if !finite(sample.time_s) || !finite(sample.stress_mpa) {
      return Err(InvalidInput("CSV line \{index + 1}: values must be finite"))
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
