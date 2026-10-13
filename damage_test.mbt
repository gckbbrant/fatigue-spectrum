///|
fn curve() -> Array[@app.SNPoint] {
  [
    { amplitude_mpa: 1.0, cycles_to_failure: 10000.0, },
    { amplitude_mpa: 10.0, cycles_to_failure: 100.0, },
  ]
}

///|
test "log-log interpolation and raw-cycle Miner sum" {
  let c = @app.extract_cycles([0.0, 2.0, 0.0]).unwrap()
  let report = @app.calculate_damage(c, curve()).unwrap()
  assert_true(report.total_damage is Some(d) && d.is_close(0.0001))
  let middle = @app.extract_cycles([0.0, 2.0 * 10.0.sqrt(), 0.0]).unwrap()
  let d = @app.calculate_damage(middle, curve()).unwrap()
  assert_true(d.total_damage is Some(value) && value.is_close(0.001))
  assert_eq(d.mean_stress_model, "none")
}

///|
test "curve endpoints accepted; outside coverage is explicitly incomplete" {
  let endpoint = @app.calculate_damage(
    @app.extract_cycles([0.0, 20.0, 0.0]).unwrap(),
    curve(),
  ).unwrap()
  assert_true(endpoint.total_damage is Some(d) && d.is_close(0.01))
  let outside = @app.calculate_damage(
    @app.extract_cycles([0.0, 22.0, 0.0]).unwrap(),
    curve(),
  ).unwrap()
  assert_true(outside.total_damage is None)
  assert_eq(outside.out_of_range_cycles.length(), 2)
  assert_eq(outside.evaluated_damage, 0.0)
  assert_true(@app.calculate_damage([], []) is Err(_))
  assert_true(
    @app.calculate_damage([], [
      { amplitude_mpa: 2.0, cycles_to_failure: 10.0, },
      { amplitude_mpa: 1.0, cycles_to_failure: 20.0, },
    ])
    is Err(_),
  )
}

///|
test "close S-N amplitudes retain a usable log interval" {
  let a = 10000000000.0
  let b = a + 0.000004
  let midpoint = a + 0.000002
  let c : @app.Cycle = {
    range_mpa: 2.0 * midpoint,
    mean_mpa: 0.0,
    count: 1.0,
    start_index: 0,
    end_index: 1,
  }
  let report = @app.calculate_damage([c], [
    { amplitude_mpa: a, cycles_to_failure: 10000.0, },
    { amplitude_mpa: b, cycles_to_failure: 100.0, },
  ]).unwrap()
  assert_true(
    report.total_damage is Some(d) &&
    d.is_close(0.001, relative_tolerance=1.0e-10),
  )
}

///|
test "wide cycle-count ratios use the original positive values" {
  let c : @app.Cycle = {
    range_mpa: 20.0,
    mean_mpa: 0.0,
    count: 1.0,
    start_index: 0,
    end_index: 1,
  }
  let report = @app.calculate_damage([c], [
    { amplitude_mpa: 1.0, cycles_to_failure: 1.0e15, },
    { amplitude_mpa: 100.0, cycles_to_failure: 1.0, },
  ]).unwrap()
  let expected = 1.0 / 1.0e15.sqrt()
  assert_true(
    report.total_damage is Some(d) &&
    d.is_close(expected, relative_tolerance=1.0e-10, absolute_tolerance=1.0e-20),
  )
}
