// Port of jxl-render filter/ycbcr.rs (JPEG-style chroma upsampling).

///|
/// `filter::apply_jpeg_upsampling_single`.
fn apply_jpeg_upsampling_single(
  grid : @grid.SubGrid[Float],
  shift : @modular.ChannelShift,
  target_region : Region,
  tracker : @grid.AllocTracker?,
) -> @grid.Grid[Float] raise @bitstream.JxlError {
  apply_jpeg_upsampling_single_raw(
    grid,
    shift.hshift(),
    shift.vshift(),
    target_region.width,
    target_region.height,
    tracker,
  )
}

///|
/// `apply_jpeg_upsampling_single` on plain values: `hshift`/`vshift` are the
/// channel's `ChannelShift::hshift()`/`vshift()`, and `target_width` /
/// `target_height` the size of `target_region`.
fn apply_jpeg_upsampling_single_raw(
  grid : @grid.SubGrid[Float],
  hshift : Int32,
  vshift : Int32,
  target_width : Int32,
  target_height : Int32,
  tracker : @grid.AllocTracker?,
) -> @grid.Grid[Float] raise @bitstream.JxlError {
  let height = grid.height
  let gw = grid.width
  let out = @grid.Grid::with_alloc_tracker(
    target_width,
    target_height,
    (0.0 : Float),
    tracker,
  )
  let buf = out.buf
  let h_upsampled = hshift == 0
  let v_upsampled = vshift == 0
  guard target_width > 0 else { abort("chunk size must be non-zero") }
  let rows = if height < target_height { height } else { target_height }
  for y in 0..<rows {
    let row = grid.offset + y * grid.stride
    let out_row = y * target_width
    if h_upsampled {
      guard gw >= target_width else { abort("range end index out of range") }
      for x in 0..<target_width {
        buf[out_row + x] = grid.buf[row + x]
      }
      continue
    }
    guard gw > 0 else { abort("called `Option::unwrap()` on a `None` value") }
    let mut prev_sample = grid.buf[row]
    // One output pair per input sample, as far as the output row reaches.
    let num_chunks = (target_width + 1) / 2
    let n = if gw < num_chunks { gw } else { num_chunks }
    for i in 0..<n {
      let curr = grid.buf[row + i]
      let next = if i + 1 < gw { grid.buf[row + i + 1] } else { curr }
      let left : Float = 0.25 * prev_sample + 0.75 * curr
      let right : Float = 0.75 * curr + 0.25 * next
      buf[out_row + 2 * i] = left
      if 2 * i + 1 < target_width {
        buf[out_row + 2 * i + 1] = right
      }
      prev_sample = curr
    }
  }

  // image is horizontally upsampled here
  if !v_upsampled {
    let prev_row = FixedArray::make(target_width, (0.0 : Float))
    for x in 0..<target_width {
      prev_row[x] = buf[(height - 1) * target_width + x]
    }
    for y = height - 1; y >= 0; y = y - 1 {
      let idx_base = y * target_width
      let top_base = if idx_base >= target_width {
        idx_base - target_width
      } else {
        0
      }
      for x in 0..<target_width {
        let curr_sample = buf[idx_base + x]
        // We're interpolating bottom-to-top.
        let bottom : Float = 0.25 * prev_row[x] + 0.75 * curr_sample
        let top : Float = 0.75 * curr_sample + 0.25 * buf[top_base + x]
        buf[idx_base * 2 + x] = top
        if y * 2 + 1 < target_height {
          buf[idx_base * 2 + target_width + x] = bottom
        }
        prev_row[x] = curr_sample
      }
    }
  }
  out
}
