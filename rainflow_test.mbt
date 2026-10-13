///|
test "two endpoints form a half cycle; constant and empty signals have none" {
  assert_eq(@app.extract_cycles([]).unwrap().length(), 0)
  assert_eq(@app.extract_cycles([3.0]).unwrap().length(), 0)
  assert_eq(@app.extract_cycles([3.0, 3.0, 3.0]).unwrap().length(), 0)
  let c = @app.extract_cycles([2.0, 6.0]).unwrap()
  assert_eq(c.length(), 1)
  assert_eq(c[0].range_mpa, 4.0)
  assert_eq(c[0].mean_mpa, 4.0)
  assert_eq(c[0].count, 0.5)
  assert_eq(c[0].start_index, 0)
  assert_eq(c[0].end_index, 1)
}

///|
test "nested cycle and open residue hand calculation" {
  let c = @app.extract_cycles([0.0, 3.0, 1.0, 4.0, 0.0]).unwrap()
  assert_eq(c.length(), 3)
  assert_eq(c[0].range_mpa, 2.0)
  assert_eq(c[0].mean_mpa, 2.0)
  assert_eq(c[0].count, 1.0)
  assert_eq(c[0].start_index, 1)
  assert_eq(c[0].end_index, 2)
  assert_eq(c[1].range_mpa, 4.0)
  assert_eq(c[1].count, 0.5)
  assert_eq(c[2].count, 0.5)
}

///|
test "plateau endpoints retain original indices" {
  let c = @app.extract_cycles([0.0, 3.0, 3.0, 1.0, 4.0, 0.0]).unwrap()
  assert_eq(c[0].start_index, 2)
  assert_eq(c[0].end_index, 3)
  assert_true(@app.extract_cycles([0.0, 0.0 / 0.0, 1.0]) is Err(_))
  assert_true(@app.extract_cycles([-1.0e308, 1.0e308]) is Err(_))
}

///|
test "spectrum keeps half cycles and rejects invalid widths" {
  let c = @app.extract_cycles([0.0, 3.0, 1.0, 4.0, 0.0]).unwrap()
  let bins = @app.build_spectrum(c, 3.0).unwrap()
  assert_eq(bins.length(), 2)
  assert_eq(bins[0].upper_range_mpa, 3.0)
  assert_eq(bins[0].count, 1.0)
  assert_eq(bins[1].upper_range_mpa, 6.0)
  assert_eq(bins[1].count, 1.0)
  assert_true(@app.build_spectrum(c, 0.0) is Err(_))
}
