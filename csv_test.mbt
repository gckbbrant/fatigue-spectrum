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
