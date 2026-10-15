///|
struct InputSummary {
  input_samples : Int
  time_start_s : Double
  time_end_s : Double
  minimum_stress_mpa : Double
  maximum_stress_mpa : Double
} derive(ToJson)

///|
async fn read_measurements(
  path : String,
  values : Map[String, Array[String]],
) -> Array[@app.StressSample] {
  match
    @app.parse_stress_csv(
      @fs.read_file(path).text(),
      time_column=optional(values, "time-column").unwrap_or("time_s"),
      stress_column=optional(values, "stress-column").unwrap_or("stress_mpa"),
      time_scale=input_time_scale(values),
      stress_scale=input_stress_scale(values),
      delimiter=input_delimiter(values),
      skip_rows=input_skip_rows(values),
      decimal_comma=input_decimal_comma(values),
      stress_zero=calibration_number(values, "stress-zero", 0.0),
      stress_gain=calibration_number(values, "stress-gain", 1.0),
    ) {
    Ok(value) => value
    Err(error) => fail(@json.to_json(error).stringify())
  }
}

///|
fn normalization_command() -> @argparse.Command {
  let options = measurement_options()
  options.push(OptionArg("csv", about="Write canonical time_s,stress_mpa CSV."))
  options.push(
    OptionArg(
      "json",
      about="Write sample count, time endpoints and stress range JSON.",
    ),
  )
  Command(
    "normalize",
    about="Check measurement input and convert to s and MPa without model calculations.",
    positionals=[PositionArg("input")],
    options~,
  )
}

///|
async fn normalize_input(values : Map[String, Array[String]]) -> Unit {
  let input = required(values, "input")
  let csv_path = optional(values, "csv")
  let json_path = optional(values, "json")
  prepare_outputs([input], [csv_path, json_path].filter_map(fn(x) { x }))
  let samples = read_measurements(input, values)
  let csv = match @app.stress_csv(samples) {
    Ok(value) => value
    Err(error) => fail(@json.to_json(error).stringify())
  }
  let mut minimum = samples[0].stress_mpa
  let mut maximum = minimum
  for sample in samples {
    minimum = minimum.min(sample.stress_mpa)
    maximum = maximum.max(sample.stress_mpa)
  }
  let summary : InputSummary = {
    input_samples: samples.length(),
    time_start_s: samples[0].time_s,
    time_end_s: samples[samples.length() - 1].time_s,
    minimum_stress_mpa: minimum,
    maximum_stress_mpa: maximum,
  }
  if csv_path is Some(path) {
    @fs.write_file(path, csv, create_mode=CreateOrTruncate)
  }
  if json_path is Some(path) {
    @fs.write_file(
      path,
      @json.to_json(summary).stringify(indent=2) + "\n",
      create_mode=CreateOrTruncate,
    )
  }
  @stdio.stdout.write(
    "Samples: \{summary.input_samples}; time: \{summary.time_start_s}..\{summary.time_end_s} s; stress: \{minimum}..\{maximum} MPa\n",
  )
}
