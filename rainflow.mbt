// The three-point counting algorithm follows ASTM E1049's rainflow method.
// Adapted with reference to Piotr Janiszewski's rainflow 3.2.0 (MIT); see NOTICE.

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
fn cycle(a : (Int, Double), b : (Int, Double), count : Double) -> Cycle {
  {
    range_mpa: (b.1 - a.1).abs(),
    mean_mpa: a.1 / 2.0 + b.1 / 2.0,
    count,
    start_index: a.0,
    end_index: b.0,
  }
}

///|
/// Extract offline rainflow cycles, including half-cycle residue.
/// Two distinct samples produce a half cycle. Constant signals produce none.
/// Plateau reversals use the last sample before a direction change.
pub fn extract_cycles(
  stress_mpa : ArrayView[Double],
) -> Result[Array[Cycle], FatigueError] {
  let mut low = 0.0
  let mut high = 0.0
  for i, value in stress_mpa {
    if !finite(value) {
      return Err(InvalidInput("sample \{i}: stress must be finite"))
    }
    if i == 0 {
      low = value
      high = value
    } else {
      low = low.min(value)
      high = high.max(value)
    }
  }
  if !finite(high - low) {
    return Err(NumericOverflow("stress range cannot be represented"))
  }
  if stress_mpa.length() < 2 {
    return Ok([])
  }
  let reversals : Array[(Int, Double)] = [(0, stress_mpa[0])]
  let mut previous_direction = 0
  for i in 1..<stress_mpa.length() {
    let direction = if stress_mpa[i] > stress_mpa[i - 1] {
      1
    } else if stress_mpa[i] < stress_mpa[i - 1] {
      -1
    } else {
      0
    }
    if direction == 0 {
      continue
    }
    if previous_direction != 0 && direction != previous_direction {
      reversals.push((i - 1, stress_mpa[i - 1]))
    }
    previous_direction = direction
  }
  let last_index = stress_mpa.length() - 1
  if stress_mpa[last_index] != reversals[reversals.length() - 1].1 {
    reversals.push((last_index, stress_mpa[last_index]))
  }
  let stack : Array[(Int, Double)] = []
  let cycles : Array[Cycle] = []
  let mut head = 0
  for point in reversals {
    stack.push(point)
    while stack.length() - head >= 3 {
      let n = stack.length()
      let older = (stack[n - 2].1 - stack[n - 3].1).abs()
      let newer = (stack[n - 1].1 - stack[n - 2].1).abs()
      if newer < older {
        break
      }
      if n - head == 3 {
        cycles.push(cycle(stack[head], stack[head + 1], 0.5))
        head += 1
      } else {
        cycles.push(cycle(stack[n - 3], stack[n - 2], 1.0))
        let last = stack.pop().unwrap()
        ignore(stack.pop())
        ignore(stack.pop())
        stack.push(last)
      }
    }
  }
  for i in head..<(stack.length() - 1) {
    cycles.push(cycle(stack[i], stack[i + 1], 0.5))
  }
  Ok(cycles)
}

///|
fn validate_cycles(cycles : ArrayView[Cycle]) -> Result[Unit, FatigueError] {
  for i, c in cycles {
    if !finite(c.range_mpa) ||
      c.range_mpa < 0.0 ||
      !finite(c.mean_mpa) ||
      !finite(c.count) ||
      c.count <= 0.0 ||
      c.start_index < 0 ||
      c.end_index <= c.start_index {
      return Err(
        InvalidInput("cycle \{i}: invalid range, mean, count or sample indices"),
      )
    }
  }
  Ok(())
}

///|
/// Sparse bins (lower, upper], except that the first bin includes zero.
/// Uses right-edge rounding only for display; damage uses original cycles.
pub fn build_spectrum(
  cycles : ArrayView[Cycle],
  bin_width_mpa : Double,
) -> Result[Array[SpectrumBin], FatigueError] {
  if !finite(bin_width_mpa) || bin_width_mpa <= 0.0 {
    return Err(InvalidInput("bin width must be finite and positive"))
  }
  if validate_cycles(cycles) is Err(error) {
    return Err(error)
  }
  let counts : Map[Double, Double] = Map([])
  for c in cycles {
    let quotient = c.range_mpa / bin_width_mpa
    let upper = quotient.ceil() * bin_width_mpa
    let count = counts.get(upper).unwrap_or(0.0) + c.count
    if !finite(upper) || !finite(count) {
      return Err(NumericOverflow("spectrum bin cannot be represented"))
    }
    counts[upper] = count
  }
  let bins : Array[SpectrumBin] = []
  for upper, count in counts {
    bins.push({
      lower_range_mpa: (upper - bin_width_mpa).max(0.0),
      upper_range_mpa: upper,
      count,
    })
  }
  bins.sort_by(fn(a, b) { a.upper_range_mpa.compare(b.upper_range_mpa) })
  Ok(bins)
}
