///|
/// Draw sparse range bins; bar height is full plus half-cycle count, not damage.
pub fn render_spectrum_svg(
  bins : ArrayView[SpectrumBin],
) -> Result[String, FatigueError] {
  let mut max_count = 1.0
  for bin in bins {
    if !finite(bin.count) ||
      bin.count <= 0.0 ||
      !finite(bin.lower_range_mpa) ||
      !finite(bin.upper_range_mpa) ||
      bin.lower_range_mpa < 0.0 ||
      bin.upper_range_mpa < bin.lower_range_mpa {
      return Err(InvalidInput("invalid spectrum bin"))
    }
    max_count = max_count.max(bin.count)
  }
  let output = StringBuilder()
  output.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 780 410\" role=\"img\" aria-labelledby=\"title desc\">\n",
  )
  output.write_string(
    "<title id=\"title\">Rainflow stress range spectrum</title><desc id=\"desc\">Sparse bins, range in MPa, cycle counts including half cycles. Damage uses unbinned cycles.</desc>\n",
  )
  output.write_string(
    "<rect width=\"780\" height=\"410\" fill=\"#f7f8fa\"/><g font-family=\"sans-serif\" fill=\"#263449\"><text x=\"60\" y=\"32\" font-size=\"22\">fatigue-spectrum · rainflow cycles</text><text x=\"60\" y=\"53\" font-size=\"12\">Range bins, not stress amplitudes; counts include half cycles</text>\n",
  )
  output.write_string(
    "<path d=\"M70 85V310H700\" fill=\"none\" stroke=\"#758299\"/><text x=\"70\" y=\"76\" font-size=\"12\">Cycle count; scale maximum \{max_count}</text>\n",
  )
  if bins.is_empty() {
    output.write_string(
      "<text x=\"245\" y=\"200\" font-size=\"18\">No varying stress cycles</text>\n",
    )
  } else {
    let step = 580.0 / bins.length().to_double()
    for i, bin in bins {
      let height = bin.count / max_count * 210.0
      let x = 90.0 + i.to_double() * step
      let y = 310.0 - height
      output.write_string(
        "<rect x=\"\{x}\" y=\"\{y}\" width=\"\{step * 0.78}\" height=\"\{height}\" fill=\"#2563eb\"><title>(\{bin.lower_range_mpa}, \{bin.upper_range_mpa}] MPa: \{bin.count} cycles</title></rect>\n",
      )
      if bins.length() <= 12 {
        output.write_string(
          "<text x=\"\{x}\" y=\"\{y - 8.0}\" font-size=\"12\">\{bin.count}</text><text x=\"\{x}\" y=\"333\" font-size=\"12\">\{bin.upper_range_mpa}</text>\n",
        )
      }
    }
  }
  output.write_string(
    "<text x=\"245\" y=\"367\" font-size=\"13\">Occupied bin upper range (MPa)</text><text x=\"60\" y=\"394\" font-size=\"12\">Mean stress is retained in cycle data. No mean-stress correction is applied.</text></g></svg>\n",
  )
  Ok(output.to_string())
}
