///|
fn validate_sn(curve : ArrayView[SNPoint]) -> Result[Unit, FatigueError] {
  if curve.length() < 2 {
    return Err(InvalidInput("S-N curve requires at least two points"))
  }
  for i, point in curve {
    if !finite(point.amplitude_mpa) ||
      point.amplitude_mpa <= 0.0 ||
      !finite(point.cycles_to_failure) ||
      point.cycles_to_failure <= 0.0 {
      return Err(
        InvalidInput(
          "S-N point \{i}: amplitude and cycles must be finite and positive",
        ),
      )
    }
    if i > 0 &&
      (
        point.amplitude_mpa <= curve[i - 1].amplitude_mpa ||
        point.cycles_to_failure >= curve[i - 1].cycles_to_failure
      ) {
      return Err(
        InvalidInput(
          "S-N amplitudes must strictly increase and cycles strictly decrease",
        ),
      )
    }
  }
  Ok(())
}

///|
fn log_ratio(value : Double, base : Double) -> Double {
  let relative = (value - base) / base
  // log1p preserves adjacent values. For wide ratios, subtraction from 1
  // loses the smaller value; log(value)-log(base) retains it instead.
  if finite(relative) && relative.abs() < 0.5 {
    @math.ln_1p(relative)
  } else {
    @math.ln(value) - @math.ln(base)
  }
}

///|
fn allowable_cycles(amplitude : Double, curve : ArrayView[SNPoint]) -> Double? {
  if amplitude < curve[0].amplitude_mpa ||
    amplitude > curve[curve.length() - 1].amplitude_mpa {
    return None
  }
  for i, point in curve {
    if amplitude == point.amplitude_mpa {
      return Some(point.cycles_to_failure)
    }
    if amplitude < point.amplitude_mpa {
      let previous = curve[i - 1]
      let t = log_ratio(amplitude, previous.amplitude_mpa) /
        log_ratio(point.amplitude_mpa, previous.amplitude_mpa)
      return Some(
        @math.exp(
          @math.ln(previous.cycles_to_failure) +
          t * log_ratio(point.cycles_to_failure, previous.cycles_to_failure),
        ),
      )
    }
  }
  None
}

///|
/// Miner damage from unbinned cycles, without mean-stress correction.
/// Any out-of-range nonzero amplitude makes total_damage absent.
pub fn calculate_damage(
  cycles : ArrayView[Cycle],
  curve : ArrayView[SNPoint],
) -> Result[DamageResult, FatigueError] {
  if validate_cycles(cycles) is Err(error) {
    return Err(error)
  }
  if validate_sn(curve) is Err(error) {
    return Err(error)
  }
  let contributions : Array[CycleDamage] = []
  let out_of_range : Array[Int] = []
  let mut sum = 0.0
  for i, c in cycles {
    let amplitude = c.range_mpa / 2.0
    let allowed = if amplitude == 0.0 {
      None
    } else {
      allowable_cycles(amplitude, curve)
    }
    let damage = if amplitude == 0.0 {
      Some(0.0)
    } else {
      match allowed {
        Some(n) => {
          if !finite(n) || n <= 0.0 {
            return Err(
              NumericOverflow("S-N interpolation cannot be represented"),
            )
          }
          let value = c.count / n
          if !finite(value) {
            return Err(NumericOverflow("cycle damage cannot be represented"))
          }
          Some(value)
        }
        None => {
          out_of_range.push(i)
          None
        }
      }
    }
    if damage is Some(value) {
      sum += value
    }
    if !finite(sum) {
      return Err(NumericOverflow("cumulative damage cannot be represented"))
    }
    contributions.push({
      cycle_index: i,
      amplitude_mpa: amplitude,
      mean_mpa: c.mean_mpa,
      count: c.count,
      allowable_cycles: allowed,
      damage,
    })
  }
  Ok({
    total_damage: if out_of_range.is_empty() {
      Some(sum)
    } else {
      None
    },
    evaluated_damage: sum,
    out_of_range_cycles: out_of_range,
    mean_stress_model: "none",
    contributions,
  })
}
