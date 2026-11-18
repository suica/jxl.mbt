// Port of jxl-render features/spot_colors.rs.

///|
/// Renders a spot color channel onto color_channels
/// (`features::render_spot_color`).
pub fn render_spot_color(
  color_channels : FixedArray[@grid.Grid[Float]],
  ec_grid : @grid.Grid[Float],
  ec_ty : @image.ExtraChannelType,
) -> Unit raise @bitstream.JxlError {
  guard ec_ty is SpotColour(red~, green~, blue~, solidity~) else {
    raise @bitstream.NotSupported("EC type is not SpotColour")
  }
  if color_channels.length() != 3 {
    return
  }
  render_spot_color_raw(
    [color_channels[0], color_channels[1], color_channels[2]],
    ec_grid,
    red,
    green,
    blue,
    solidity,
  )
}

///|
/// Renders a spot colour channel onto `color_channels` (`render_spot_color`
/// with the fields of `ExtraChannelType::SpotColour` given as values).
fn render_spot_color_raw(
  color_channels : Array[@grid.Grid[Float]],
  ec_grid : @grid.Grid[Float],
  red : Float,
  green : Float,
  blue : Float,
  solidity : Float,
) -> Unit {
  let spot_colors : FixedArray[Float] = [red, green, blue]
  let s = ec_grid.buf
  let len = ec_grid.width * ec_grid.height
  for c in 0..<3 {
    let g = color_channels[c]
    let channel = g.buf
    let color = spot_colors[c]
    guard g.width * g.height == len else {
      abort("assertion failed: channel.len() == s.len()")
    }
    for i in 0..<len {
      let mix = s[i] * solidity
      channel[i] = mix * color + (1.0 - mix) * channel[i]
    }
  }
}
