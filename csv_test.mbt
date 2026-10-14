///|
test "stress CSV units, BOM, finite values and time order" {
  let s = @app.parse_stress_csv("\u{FEFF}time_s,stress_mpa\r\n0,-1\r\n1,4\r\n").unwrap()
  assert_eq(s.length(), 2)
  assert_eq(s[0].stress_mpa, -1.0)
  assert_true(@app.parse_stress_csv("time_s,force_n\n0,1") is Err(_))
  assert_true(@app.parse_stress_csv("time_s,stress_mpa\n1,1\n0,2") is Err(_))
  assert_true(@app.parse_stress_csv("time_s,stress_mpa\n0,nan") is Err(_))
  assert_true(@app.parse_stress_csv("time_s,stress_mpa\n0,1,2") is Err(_))
  assert_true(@app.parse_stress_csv("time_s,stress_mpa") is Err(_))
}

///|
test "cycle CSV keeps unbinned amplitude information and half counts" {
  let csv = @app.cycles_csv(@app.extract_cycles([2.0, 6.0]).unwrap()).unwrap()
  assert_eq(
    csv, "range_mpa,mean_mpa,count,start_index,end_index\n4,4,0.5,0,1\n",
  )
  assert_true(@app.render_spectrum_svg([]) is Ok(_))
}

///|
test "cycle CSV round trip, empty history and counted records" {
  let extracted = @app.extract_cycles([0.0, 30.0, 10.0, 40.0, 0.0]).unwrap()
  let csv = @app.cycles_csv(extracted).unwrap()
  let imported = @app.parse_cycles_csv(csv).unwrap()
  assert_eq(@app.cycles_csv(imported).unwrap(), csv)
  assert_eq(
    @app.parse_cycles_csv("range_mpa,mean_mpa,count,start_index,end_index\n")
    .unwrap()
    .length(),
    0,
  )
  let counted = @app.parse_cycles_csv(
    "\u{FEFF}range_mpa,mean_mpa,count,start_index,end_index\r\n\r\n20,-5,100,0,1\r\n40,2,0.5,1,4\r\n",
  ).unwrap()
  assert_eq(counted[0].count, 100.0)
  assert_eq(counted[0].mean_mpa, -5.0)
  assert_eq(counted[1].end_index, 4)
}

///|
test "invalid cycle CSV cannot bypass public cycle validation" {
  let header = "range_mpa,mean_mpa,count,start_index,end_index\n"
  for
    row in [
      "20,0,0,0,1", "-20,0,1,0,1", "20,nan,1,0,1", "20,0,1,1,1", "20,0,1,-1,2", "20,0,1,0.5,2",
      "20,0,1,0,1,extra", "20,0,1e309,0,1",
    ] {
    assert_true(@app.parse_cycles_csv(header + row) is Err(_))
  }
  assert_true(@app.parse_cycles_csv("") is Err(_))
  assert_true(
    @app.parse_cycles_csv(
      "amplitude_mpa,mean_mpa,count,start_index,end_index\n20,0,1,0,1",
    )
    is Err(_),
  )
}
