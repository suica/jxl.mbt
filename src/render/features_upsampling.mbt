// Port of jxl-render features/upsampling.rs (non-separable 2x/4x/8x
// upsampling with the weights from the image metadata).

///|
/// `upsample` on plain values: `up2_weight` (15), `up4_weight` (55) and
/// `up8_weight` (210) are `ImageMetadata`'s custom weights; `factor` is the
/// log2 upsampling factor. Returns `None` when `factor == 0`. The caller
/// upsamples its region by `factor` (`out_region.upsample(factor)`).
pub fn upsample_raw(
  grid : @grid.SubGrid[Float],
  up2_weight : FixedArray[Float],
  up4_weight : FixedArray[Float],
  up8_weight : FixedArray[Float],
  factor : Int,
  tracker : @grid.AllocTracker?,
) -> @grid.Grid[Float]? raise @bitstream.JxlError {
  let mut out : @grid.Grid[Float]? = None
  let mut grid = grid
  let up8 = factor / 3
  let last_up = factor % 3
  for _ in 0..<up8 {
    let g = upsample_inner(grid, 8, up8_weight, tracker)
    out = Some(g)
    grid = g.as_subgrid()
  }
  match last_up {
    1 => Some(upsample_inner(grid, 2, up2_weight, tracker))
    2 => Some(upsample_inner(grid, 4, up4_weight, tracker))
    _ => out
  }
}

///|
/// `upsample_inner::<K, NW>`.
fn upsample_inner(
  grid : @grid.SubGrid[Float],
  k : Int,
  weights : FixedArray[Float],
  tracker : @grid.AllocTracker?,
) -> @grid.Grid[Float] raise @bitstream.JxlError {
  let nw = weights.length()
  guard (k == 2 && nw == 15) || (k == 4 && nw == 55) || (k == 8 && nw == 210) else {
    abort("upsample: invalid weights")
  }
  let grid_width = grid.width
  let grid_height = grid.height
  let shift = k.ctz()
  let frame_width = grid_width << shift
  let frame_height = grid_height << shift

  // 5x5 kernel
  let padding = 2
  let padded_width = grid_width + padding * 2
  let padded = @grid.Grid::with_alloc_tracker(
    padded_width,
    grid_height + padding * 2,
    (0.0 : Float),
    tracker,
  )
  let padded_buf = padded.buf
  for y in 0..<grid_height {
    let row = grid.offset + y * grid.stride
    let base = (y + padding) * padded_width + padding
    for x in 0..<grid_width {
      padded_buf[base + x] = grid.buf[row + x]
    }
  }
  upsampling_mirror_edges_padding(padded_buf, padded_width, grid_height, padding)

  // For K = 8:
  // 0  1  2  3  3h 2h 1h 0h
  // 4  5  6  7  7h 6h 5h 4h
  // 8  9  a  b  bh ah 9h 8h
  // c  d  e  f  fh eh dh ch
  // cv dv ev fv f' e' d' c'
  // 8v 9v av bv b' a' 9' 8'
  // 4v 5v 6v 7v 7' 6' 5' 4'
  // 0v 1v 2v 3v 3' 2' 1' 0'
  let mat_n = k / 2
  let num_mats = k * k / 4
  let weights_quarter = FixedArray::make(num_mats * 25, (0.0 : Float))
  let mut weight_idx = 0
  for y in 0..<(5 * mat_n) {
    let mat_y = y / 5
    let ky = y % 5
    for x in y..<(5 * mat_n) {
      let mat_x = x / 5
      let kx = x % 5
      let w = weights[weight_idx]
      weight_idx += 1
      weights_quarter[(mat_y * mat_n + mat_x) * 25 + ky * 5 + kx] = w
      weights_quarter[(mat_x * mat_n + mat_y) * 25 + kx * 5 + ky] = w
    }
  }
  let out = @grid.Grid::with_alloc_tracker(
    frame_width,
    frame_height,
    (0.0 : Float),
    tracker,
  )
  let grid_buf = out.buf
  for y in 0..<frame_height {
    let ref_y = y / k
    let my = y % k
    let mat_y = if my < k - my - 1 { my } else { k - my - 1 }
    let flip_v = my >= mat_n
    for x in 0..<frame_width {
      let ref_x = x / k
      let mx = x % k
      let mat_x = if mx < k - mx - 1 { mx } else { k - mx - 1 }
      let flip_h = mx >= mat_n
      let kernel = (mat_y * mat_n + mat_x) * 25
      let mut sum : Float = 0.0
      let mut min : Float = @float.infinity
      let mut max : Float = @float.neg_infinity
      for iy in 0..<5 {
        let ky = if flip_v { 4 - iy } else { iy }
        for ix in 0..<5 {
          let kx = if flip_h { 4 - ix } else { ix }
          let sample = padded_buf[(ref_y + iy) * padded_width + (ref_x + ix)]
          sum = sum + weights_quarter[kernel + ky * 5 + kx] * sample
          min = min.min(sample)
          max = max.max(sample)
        }
      }
      grid_buf[y * frame_width + x] = if !min.is_finite() {
        // This happens if all samples are NaN.
        @float.not_a_number
      } else if sum < min {
        min
      } else if sum > max {
        max
      } else {
        sum
      }
    }
  }
  if tracker is Some(t) {
    t.free(padded.width * padded.height, 4)
  }
  out
}

///|
/// `PaddedGrid::mirror_edges_padding` (util.rs) on a padded buffer of width
/// `stride` holding `height` rows of samples between `padding` rows of padding.
fn upsampling_mirror_edges_padding(
  buf : FixedArray[Float],
  stride : Int,
  height : Int,
  padding : Int,
) -> Unit {
  // Mirror horizontally.
  for y in padding..<(height + padding) {
    for x in 0..<padding {
      buf[y * stride + x] = buf[y * stride + padding * 2 - x - 1]
      buf[(y + 1) * stride - x - 1] = buf[(y + 1) * stride - padding * 2 + x]
    }
  }
  // Mirror vertically.
  for i in 0..<padding {
    // out row i <- in row (2 * padding - 1 - i)
    let src = (2 * padding - 1 - i) * stride
    let dst = i * stride
    for x in 0..<stride {
      buf[dst + x] = buf[src + x]
    }
  }
  let in_rows = height + padding
  let out_rows = padding
  let n = if in_rows < out_rows { in_rows } else { out_rows }
  for i in 0..<n {
    let src = (in_rows - 1 - i) * stride
    let dst = (in_rows + i) * stride
    for x in 0..<stride {
      buf[dst + x] = buf[src + x]
    }
  }
}
