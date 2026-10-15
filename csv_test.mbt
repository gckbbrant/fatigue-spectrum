///|
test "canonical stress CSV round trips signed and constant samples" {
  let samples : Array[@app.StressSample] = [
    { time_s: -1.0e250, stress_mpa: -1.0e250, },
    { time_s: 0.0, stress_mpa: 1.0e-250, },
    { time_s: 1.0e250, stress_mpa: 1.0e-250, },
  ]
  let csv = @app.stress_csv(samples).unwrap()
  let restored = @app.parse_stress_csv(csv).unwrap()
  assert_eq(restored.length(), samples.length())
  for i, sample in samples {
    assert_eq(restored[i].time_s, sample.time_s)
    assert_eq(restored[i].stress_mpa, sample.stress_mpa)
  }
  assert_eq(
    @app.stress_csv([{ time_s: 0.0, stress_mpa: -2.0, }]).unwrap(),
    "time_s,stress_mpa\n0,-2\n",
  )
}

///|
test "canonical stress export validates publicly constructed samples" {
  assert_true(@app.stress_csv([]) is Err(_))
  for value in [@double.infinity, @double.not_a_number] {
    assert_true(
      @app.stress_csv([{ time_s: 0.0, stress_mpa: value, }]) is Err(_),
    )
  }
  assert_true(
    @app.stress_csv([{ time_s: @double.infinity, stress_mpa: 0.0, }]) is Err(_),
  )
  for time in [0.0, -1.0] {
    assert_true(
      @app.stress_csv([
        { time_s: 0.0, stress_mpa: 0.0, },
        { time_s: time, stress_mpa: 1.0, },
      ])
      is Err(_),
    )
  }
}

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

///|
test "measurement columns, quoted notes and explicit unit scales" {
  let samples = @app.parse_stress_csv(
    "\u{FEFF}note;Load;Clock\r\n\"sensor; A\"\"x\"\"\";-2000;0\r\n\"sensor B\";5000;1000\r\n\"sensor C\";0;2000\r\n",
    time_column="Clock",
    stress_column="Load",
    time_scale=0.001,
    stress_scale=0.001,
    delimiter=";",
  ).unwrap()
  assert_eq(samples.length(), 3)
  assert_eq(samples[1].time_s, 1.0)
  assert_eq(samples[1].stress_mpa, 5.0)
  let tabbed = @app.parse_stress_csv(
    "Clock\tLoad\tnote\n0\t1\t\n1\t2\t\n",
    time_column="Clock",
    stress_column="Load",
    delimiter="\t",
  ).unwrap()
  assert_eq(tabbed.length(), 2)
}

///|
test "measurement imports reject ambiguous columns and lossy conversion" {
  for
    text in [
      "time_s,stress_mpa,stress_mpa\n0,1,2", "time_s,other\n0,1", "time_s,stress_mpa,note\n0,1",
      "time_s,stress_mpa\n0,\"1", "time_s,stress_mpa\n0,\"1\"oops",
    ] {
    assert_true(@app.parse_stress_csv(text) is Err(_))
  }
  assert_true(
    @app.parse_stress_csv("time_s,stress_mpa\n0,1e308", stress_scale=1000.0)
    is Err(_),
  )
  assert_true(
    @app.parse_stress_csv("time_s,stress_mpa\n0,1e-300", stress_scale=1.0e-100)
    is Err(_),
  )
  assert_true(
    @app.parse_stress_csv("time_s,stress_mpa\n0,1", time_scale=0.0) is Err(_),
  )
  assert_true(
    @app.parse_stress_csv("time_s,stress_mpa\n0,1", stress_column="time_s")
    is Err(_),
  )
}

///|
test "explicit preamble skipping and decimal comma keep original line numbers" {
  let result = @app.parse_stress_csv(
    "Instrument export\nsep=;\nClock;Value\n0,0;0,0\n1000,5;1,25\n",
    time_column="Clock",
    stress_column="Value",
    delimiter=";",
    time_scale=0.001,
    skip_rows=2,
    decimal_comma=true,
  ).unwrap()
  assert_eq(result.length(), 2)
  assert_true(result[1].time_s.is_close(1.0005))
  assert_eq(result[1].stress_mpa, 1.25)
  assert_true(
    @app.parse_stress_csv("time_s,stress_mpa\n0,1", skip_rows=-1) is Err(_),
  )
  assert_true(
    @app.parse_stress_csv("time_s,stress_mpa\n0,1", skip_rows=9) is Err(_),
  )
}

///|
test "decimal comma never guesses mixed decimal or grouping formats" {
  for value in ["1.25", "1.234,5", "1,234,5"] {
    assert_true(
      @app.parse_stress_csv(
        "time_s;stress_mpa\n0;" + value,
        delimiter=";",
        decimal_comma=true,
      )
      is Err(_),
    )
  }
  let broken = @app.parse_stress_csv(
    "metadata\nmetadata\ntime_s;stress_mpa\n0;bad",
    delimiter=";",
    skip_rows=2,
    decimal_comma=true,
  )
  assert_true(
    broken is Err(@app.InvalidInput(message)) && message.contains("line 4"),
  )
}
