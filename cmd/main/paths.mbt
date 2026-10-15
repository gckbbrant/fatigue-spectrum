///|
async fn output_identity(path : String) -> String {
  if @fs.exists(path) {
    return @fs.realpath(path).replace(old="\\", new="/").to_lower()
  }
  let parts = path.replace(old="\\", new="/").split("/").collect()
  let name = parts[parts.length() - 1]
  if name.is_empty() {
    fail("output must name a file")
  }
  let parent = if parts.length() == 1 {
    "."
  } else {
    parts[:parts.length() - 1].join("/")
  }
  (@fs.realpath(parent).replace(old="\\", new="/") + "/" + name.to_owned()).to_lower()
}

///|
async fn prepare_outputs(
  inputs : Array[String],
  outputs : Array[String],
) -> Unit {
  let input_ids : Array[String] = []
  for path in inputs {
    input_ids.push(@fs.realpath(path).replace(old="\\", new="/").to_lower())
  }
  let output_ids : Array[String] = []
  for path in outputs {
    let id = output_identity(path)
    if input_ids.contains(id) {
      fail("output must not overwrite an input: \{path}")
    }
    if output_ids.contains(id) {
      fail("output paths must be distinct")
    }
    output_ids.push(id)
  }
  for path in outputs {
    if @fs.exists(path) {
      @fs.remove(path)
    }
  }
}
