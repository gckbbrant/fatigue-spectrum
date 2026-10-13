///|
fn main {
  let cycles = @fatigue.extract_cycles([0.0, 30.0, 10.0, 40.0, 0.0]).unwrap()
  for c in cycles {
    println(
      "Range \{c.range_mpa} MPa; mean \{c.mean_mpa} MPa; count \{c.count}; indices \{c.start_index}..\{c.end_index}",
    )
  }
  let damage = @fatigue.calculate_damage(cycles, [
    { amplitude_mpa: 1.0, cycles_to_failure: 10000000000.0, },
    { amplitude_mpa: 10.0, cycles_to_failure: 1000000.0, },
    { amplitude_mpa: 100.0, cycles_to_failure: 100.0, },
  ]).unwrap()
  if damage.total_damage is Some(value) {
    println("Miner damage without mean correction: \{value}")
  }
}
