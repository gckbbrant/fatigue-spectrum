///|
extern "C" fn exit_process(code : Int) -> Unit = "exit"

///|
struct Report {
  input_file : String
  input_samples : Int?
  cycles : Array[@app.Cycle]
  spectrum : Array[@app.SpectrumBin]
  bin_width_mpa : Double
  sn_curve : Array[@app.SNPoint]?
  damage : @app.DamageResult?
  mean_stress_model : String
} derive(ToJson)

///|
fn required(values : Map[String, Array[String]], key : String) -> String raise {
  match values.get(key) {
    Some([value]) => value
    _ => fail("expected one value for \{key}")
  }
}

///|
fn optional(values : Map[String, Array[String]], key : String) -> String? raise {
  match values.get(key) {
    Some([value]) => Some(value)
    None => None
    _ => fail("expected one value for \{key}")
  }
}

///|
async fn run() -> Unit {
  let options = [
    @argparse.OptionArg(
      "bin-width",
      about="Range bin width in MPa; default 10.",
    ),
    @argparse.OptionArg(
      "sn",
      about="JSON array of amplitude_mpa,cycles_to_failure points.",
    ),
    @argparse.OptionArg(
      "json",
      about="Write cycles, spectrum and optional damage JSON.",
    ),
    @argparse.OptionArg("cycles", about="Write unbinned cycles CSV."),
    @argparse.OptionArg("svg", about="Write stress range spectrum SVG."),
  ]
  let analyze_options = measurement_options()
  analyze_options.append(options)
  let analyze = @argparse.Command(
    "analyze",
    about="Extract cycles from time_s,stress_mpa CSV.",
    positionals=[@argparse.PositionArg("stress")],
    options=analyze_options,
  )
  let from_cycles = @argparse.Command(
    "from-cycles",
    about="Analyze previously counted, unbinned cycle CSV records.",
    positionals=[@argparse.PositionArg("cycle-input")],
    options~,
  )
  let matches = @argparse.Command(
    "fatigue-spectrum",
    about="Rainflow stress spectrum and bounded Miner estimates.",
    subcommands=[analyze, from_cycles, normalization_command()],
    subcommand_required=true,
  ).parse()
  guard matches.subcommand is Some((name, args)) else {
    fail("expected analyze, from-cycles or normalize")
  }
  if name == "normalize" {
    normalize_input(args.values)
    return
  }
  let input_path = required(
    args.values,
    if name == "analyze" {
      "stress"
    } else {
      "cycle-input"
    },
  )
  let sn_path = optional(args.values, "sn")
  let json_path = optional(args.values, "json")
  let cycles_path = optional(args.values, "cycles")
  let svg_path = optional(args.values, "svg")
  let inputs = [input_path]
  if sn_path is Some(path) {
    inputs.push(path)
  }
  let outputs = [json_path, cycles_path, svg_path].filter_map(fn(x) { x })
  prepare_outputs(inputs, outputs)
  let width : Double = match optional(args.values, "bin-width") {
    Some(text) => @string.from_str(text)
    None => 10.0
  }
  let mut input_samples : Int? = None
  let cycles = if name == "analyze" {
    let samples = read_measurements(input_path, args.values)
    input_samples = Some(samples.length())
    match @app.extract_cycles(samples.map(fn(s) { s.stress_mpa })) {
      Ok(value) => value
      Err(error) => fail(@json.to_json(error).stringify())
    }
  } else {
    match @app.parse_cycles_csv(@fs.read_file(input_path).text()) {
      Ok(value) => value
      Err(error) => fail(@json.to_json(error).stringify())
    }
  }
  let spectrum = match @app.build_spectrum(cycles, width) {
    Ok(value) => value
    Err(error) => fail(@json.to_json(error).stringify())
  }
  let curve : Array[@app.SNPoint]? = match sn_path {
    Some(path) => Some(@json.from_json(@json.parse(@fs.read_file(path).text())))
    None => None
  }
  let damage = match curve {
    Some(points) =>
      match @app.calculate_damage(cycles, points) {
        Ok(value) => Some(value)
        Err(error) => fail(@json.to_json(error).stringify())
      }
    None => None
  }
  let report : Report = {
    input_file: input_path,
    input_samples,
    cycles,
    spectrum,
    bin_width_mpa: width,
    sn_curve: curve,
    damage,
    mean_stress_model: "none",
  }
  if json_path is Some(path) {
    @fs.write_file(
      path,
      @json.to_json(report).stringify(indent=2) + "\n",
      create_mode=@fs.CreateOrTruncate,
    )
  }
  if cycles_path is Some(path) {
    let csv = match @app.cycles_csv(cycles) {
      Ok(value) => value
      Err(error) => fail(@json.to_json(error).stringify())
    }
    @fs.write_file(path, csv, create_mode=@fs.CreateOrTruncate)
  }
  if svg_path is Some(path) {
    let svg = match @app.render_spectrum_svg(spectrum) {
      Ok(value) => value
      Err(error) => fail(@json.to_json(error).stringify())
    }
    @fs.write_file(path, svg, create_mode=@fs.CreateOrTruncate)
  }
  if input_samples is Some(count) {
    @stdio.stdout.write("Samples: \{count}; ")
  }
  @stdio.stdout.write(
    "Cycle records: \{cycles.length()}; occupied range bins: \{spectrum.length()}\n",
  )
  if damage is Some(result) {
    match result.total_damage {
      Some(value) =>
        @stdio.stdout.write(
          "Miner damage: \{value}; mean-stress correction: none\n",
        )
      None => {
        @stdio.stderr.write(
          "S-N coverage incomplete: \{result.out_of_range_cycles.length()} cycle records outside curve. No total damage is reported.\n",
        )
        exit_process(1)
      }
    }
  }
}

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("fatigue-spectrum: \{error}\n")
      exit_process(2)
    }
  }
}
