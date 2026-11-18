// Port of jxl-color `convert/gamut_map.rs` (generic implementation).

///|
fn gamut_map(
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  luminances : FixedArray[Float],
  saturation_factor : Float,
  start : Int32,
  len : Int32,
) -> Unit {
  let rgb : FixedArray[Float] = FixedArray::make(3, 0.0)
  for i in start..<(start + len) {
    rgb[0] = r[i]
    rgb[1] = g[i]
    rgb[2] = b[i]
    let mapped = map_gamut_generic(rgb, luminances, saturation_factor)
    r[i] = mapped[0]
    g[i] = mapped[1]
    b[i] = mapped[2]
  }
}
