// Port of jxl-render vardct/generic/mod.rs: adaptive LF smoothing.

///|
const SCALE_SELF : Float = 0.052262735

///|
const SCALE_SIDE : Float = 0.2034514

///|
const SCALE_DIAG : Float = 0.03348292

///|
fn absf(x : Float) -> Float {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// `f32::max` (returns the non-NaN operand if one is NaN).
fn maxf(a : Float, b : Float) -> Float {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if a > b {
    a
  } else {
    b
  }
}

///|
fn adaptive_lf_smoothing_impl(
  width : Int,
  height : Int,
  shifts : FixedArray[@modular.ChannelShift],
  in_xyb : FixedArray[FixedArray[Float]],
  lf_xyb : FixedArray[Float],
  tracker : @grid.AllocTracker?,
) -> Unit raise @bitstream.JxlError {
  if width <= 2 || height <= 2 {
    // Nothing to do
    return
  }
  let mut subsampled = false
  for s in shifts {
    if s.hshift() + s.vshift() != 0 {
      subsampled = true
    }
  }
  if subsampled {
    return adaptive_lf_smoothing_subsampled_impl(
      width, height, shifts, in_xyb, lf_xyb, tracker,
    )
  }
  let in_x = in_xyb[0]
  let in_y = in_xyb[1]
  let in_b = in_xyb[2]
  let lf_x = lf_xyb[0]
  let lf_y = lf_xyb[1]
  let lf_b = lf_xyb[2]
  let udsum = FixedArray::makei(3, _ => {
    @grid.Grid::with_alloc_tracker(width, height - 2, (0.0 : Float), tracker)
  })
  for c in 0..<3 {
    let g = in_xyb[c]
    let out = udsum[c].buf()
    for y in 0..<(height - 2) {
      for x in 0..<width {
        out[y * width + x] = g[y * width + x] + g[(y + 2) * width + x]
      }
    }
  }
  let udsum_x = udsum[0].buf()
  let udsum_y = udsum[1].buf()
  let udsum_b = udsum[2].buf()
  for row in 0..<(height - 2) {
    let u = row * width
    let r = (row + 1) * width
    let mut in_x_prev = in_x[r]
    let mut in_y_prev = in_y[r]
    let mut in_b_prev = in_b[r]
    for x in 1..<(width - 1) {
      let x_self = in_x[r + x]
      let x_side = in_x_prev + in_x[r + x + 1] + udsum_x[u + x]
      let x_diag = udsum_x[u + x - 1] + udsum_x[u + x + 1]
      let x_wa = x_self * SCALE_SELF + x_side * SCALE_SIDE + x_diag * SCALE_DIAG
      let x_gap_t = absf(x_wa - x_self) / lf_x
      let y_self = in_y[r + x]
      let y_side = in_y_prev + in_y[r + x + 1] + udsum_y[u + x]
      let y_diag = udsum_y[u + x - 1] + udsum_y[u + x + 1]
      let y_wa = y_self * SCALE_SELF + y_side * SCALE_SIDE + y_diag * SCALE_DIAG
      let y_gap_t = absf(y_wa - y_self) / lf_y
      let b_self = in_b[r + x]
      let b_side = in_b_prev + in_b[r + x + 1] + udsum_b[u + x]
      let b_diag = udsum_b[u + x - 1] + udsum_b[u + x + 1]
      let b_wa = b_self * SCALE_SELF + b_side * SCALE_SIDE + b_diag * SCALE_DIAG
      let b_gap_t = absf(b_wa - b_self) / lf_b
      let gap = maxf(maxf(maxf(0.5, x_gap_t), y_gap_t), b_gap_t)
      let gap_scale = maxf(3.0 - 4.0 * gap, 0.0)
      in_x[r + x] = (x_wa - x_self) * gap_scale + x_self
      in_y[r + x] = (y_wa - y_self) * gap_scale + y_self
      in_b[r + x] = (b_wa - b_self) * gap_scale + b_self
      in_x_prev = x_self
      in_y_prev = y_self
      in_b_prev = b_self
    }
  }
}

///|
fn adaptive_lf_smoothing_subsampled_impl(
  width : Int,
  height : Int,
  shifts : FixedArray[@modular.ChannelShift],
  in_xyb : FixedArray[FixedArray[Float]],
  lf_xyb : FixedArray[Float],
  tracker : @grid.AllocTracker?,
) -> Unit raise @bitstream.JxlError {
  let dims = FixedArray::makei(3, c => shifts[c].shift_size((width, height)))
  for d in dims {
    let (w, h) = d
    if w <= 2 || h <= 2 {
      return
    }
  }
  let wa = FixedArray::makei(3, c => {
    let (w, h) = dims[c]
    @grid.Grid::with_alloc_tracker(w - 2, h - 2, (0.0 : Float), tracker)
  })
  for c in 0..<3 {
    let (w, h) = dims[c]
    let g = in_xyb[c]
    let out = wa[c].buf()
    for y in 0..<(h - 2) {
      let up = y * w
      let center = (y + 1) * w
      let down = (y + 2) * w
      for x in 0..<(w - 2) {
        let me = g[center + x + 1]
        let side = g[up + x + 1] + g[center + x] + g[center + x + 2] + g[down + x + 1]
        let diag = g[up + x] + g[up + x + 2] + g[down + x] + g[down + x + 2]
        out[y * (w - 2) + x] = me * SCALE_SELF +
          side * SCALE_SIDE +
          diag * SCALE_DIAG
      }
    }
  }
  let last_coords_y = FixedArray::make(3, 0)
  let current_row = FixedArray::makei(3, c => {
    FixedArray::make(dims[c].0, (0.0 : Float))
  })
  let coords_y = FixedArray::make(3, 0)
  let coords_x = FixedArray::make(3, 0)
  for row in 0..<height {
    let mut skip_row = false
    for c in 0..<3 {
      coords_y[c] = row >> shifts[c].vshift()
      if coords_y[c] == 0 || coords_y[c] == dims[c].1 - 1 {
        skip_row = true
      }
    }
    if skip_row {
      continue
    }
    for c in 0..<3 {
      if last_coords_y[c] != coords_y[c] {
        let w = dims[c].0
        FixedArray::blit_to(
          in_xyb[c],
          current_row[c],
          len=w,
          src_offset=coords_y[c] * w,
        )
      }
      last_coords_y[c] = coords_y[c]
    }
    for col in 0..<width {
      let mut skip_col = false
      for c in 0..<3 {
        coords_x[c] = col >> shifts[c].hshift()
        if coords_x[c] == 0 || coords_x[c] == dims[c].0 - 1 {
          skip_col = true
        }
      }
      if skip_col {
        continue
      }
      let selfs = FixedArray::make(3, (0.0 : Float))
      let was = FixedArray::make(3, (0.0 : Float))
      let mut gap : Float = 0.5
      for c in 0..<3 {
        let s = current_row[c][coords_x[c]]
        let w = wa[c].get(coords_x[c] - 1, coords_y[c] - 1)
        selfs[c] = s
        was[c] = w
        gap = maxf(gap, absf(w - s) / lf_xyb[c])
      }
      let gap_scale = maxf(3.0 - 4.0 * gap, 0.0)
      for c in 0..<3 {
        let shift = shifts[c]
        let skip_update = coords_y[c] << shift.vshift() != row ||
          coords_x[c] << shift.hshift() != col
        if !skip_update {
          in_xyb[c][coords_y[c] * dims[c].0 + coords_x[c]] = (was[c] - selfs[c]) *
            gap_scale +
            selfs[c]
        }
      }
    }
  }
}
