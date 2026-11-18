// Port of jxl-render features/spot_colors.rs.

///|
/// Renders a spot colour channel onto `color_channels` (`render_spot_color`
/// with the fields of `ExtraChannelType::SpotColour` given as values).
pub fn render_spot_color_raw(
  color_channels : Array[@grid.Grid[Float]],
  ec_grid : @grid.Grid[Float],
  red : Float,
  green : Float,
  blue : Float,
  solidity : Float,
) -> Unit {
  if color_channels.length() != 3 {
    return
  }
  let spot_colors : FixedArray[Float] = [red, green, blue]
  let s = ec_grid.buf
  let len = ec_grid.width * ec_grid.height
  for c in 0..<3 {
    let g = color_channels[c]
    let channel = g.buf
    let color = spot_colors[c]
    guard g.width * g.height == len else {
      abort("render_spot_color: size mismatch")
    }
    for i in 0..<len {
      let mix = s[i] * solidity
      channel[i] = mix * color + (1.0 - mix) * channel[i]
    }
  }
}
