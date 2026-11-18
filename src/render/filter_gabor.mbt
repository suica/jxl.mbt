// Port of jxl-render filter/gabor.rs and filter/impls/generic/gabor.rs
// (Gaborish, a 3x3 symmetric convolution). Only the generic (scalar) path is
// ported; it is what upstream runs on targets without SIMD.

///|
/// Runs Gaborish on the three colour channels `fb` (views of the padded colour
/// region), writing the results into `fb_scratch`, which must have the same
/// sizes as the views (`filter/impls/generic.rs` `apply_gabor_like`).
///
/// `weights[c]` is `[w0, w1]` of channel `c`.
pub fn apply_gabor_like_grids(
  fb : Array[@grid.SubGrid[Float]],
  fb_scratch : Array[@grid.Grid[Float]],
  weights : FixedArray[FixedArray[Float]],
) -> Unit {
  for c in 0..<3 {
    run_gabor_rows(fb[c], fb_scratch[c], weights[c][0], weights[c][1])
  }
}

///|
/// `run_gabor_rows` with the generic row handler.
fn run_gabor_rows(
  input : @grid.SubGrid[Float],
  output : @grid.Grid[Float],
  w0 : Float,
  w1 : Float,
) -> Unit {
  let width = input.width
  let height = input.height
  let out = output.buf
  guard out.length() >= width * height else {
    abort("gabor: output size mismatch")
  }
  let inb = input.buf
  let stride = input.stride
  let base = input.offset
  if height == 1 {
    gabor_row_edge(inb, base, None, out, 0, width, w0, w1)
    return
  }
  gabor_row_edge(inb, base, Some(base + stride), out, 0, width, w0, w1)
  for y in 1..<(height - 1) {
    run_gabor_row_generic(
      inb,
      base + (y - 1) * stride,
      base + y * stride,
      base + (y + 1) * stride,
      out,
      y * width,
      width,
      w0,
      w1,
    )
  }
  gabor_row_edge(
    inb,
    base + (height - 1) * stride,
    Some(base + (height - 2) * stride),
    out,
    (height - 1) * width,
    width,
    w0,
    w1,
  )
}

///|
/// Top/bottom edge rows (`row_a` is the adjacent row) and the single-row case
/// (`row_a` is `None`). Rows are given as offsets into `inb`.
fn gabor_row_edge(
  inb : FixedArray[Float],
  row_c : Int,
  row_a : Int?,
  out : FixedArray[Float],
  out_off : Int,
  width : Int,
  w0 : Float,
  w1 : Float,
) -> Unit {
  guard width > 0 else { abort("gabor: empty row") }
  let global_weight : Float = 1.0 / (1.0 + w0 * 4.0 + w1 * 4.0)
  match row_a {
    Some(row_a) => {
      // Bottom/top edge case
      if width == 1 {
        let u = inb[row_a]
        let c = inb[row_c]
        out[out_off] = (c * (1.0 + 3.0 * w0 + 2.0 * w1) + u * (w0 + 2.0 * w1)) *
          global_weight
        return
      }
      {
        // 1 | 1 0
        let a1 = inb[row_a]
        let a0 = inb[row_a + 1]
        let c1 = inb[row_c]
        let c0 = inb[row_c + 1]
        out[out_off] = (c1 * (1.0 + 2.0 * w0 + w1) +
          (a1 + c0) * (w0 + w1) +
          a0 * w1) *
          global_weight
      }
      // 0 1 2
      for x in 1..<(width - 1) {
        let a0 = inb[row_a + x - 1]
        let a1 = inb[row_a + x]
        let a2 = inb[row_a + x + 1]
        let c0 = inb[row_c + x - 1]
        let c1 = inb[row_c + x]
        let c2 = inb[row_c + x + 1]
        out[out_off + x] = (c1 +
          (a1 + c0 + c1 + c2) * w0 +
          (a0 + a2 + c0 + c2) * w1) *
          global_weight
      }
      {
        // 0 1 | 1
        let a0 = inb[row_a + width - 2]
        let a1 = inb[row_a + width - 1]
        let c0 = inb[row_c + width - 2]
        let c1 = inb[row_c + width - 1]
        out[out_off + width - 1] = (c1 * (1.0 + 2.0 * w0 + w1) +
          (a1 + c0) * (w0 + w1) +
          a0 * w1) *
          global_weight
      }
    }
    None => {
      // Single row case
      if width == 1 {
        out[out_off] = inb[row_c]
        return
      }
      let merged_w0 : Float = 1.0 + 2.0 + w0
      let merged_w1 : Float = w0 + 2.0 * w1
      {
        let c1 = inb[row_c]
        let c0 = inb[row_c + 1]
        out[out_off] = (c1 * (merged_w0 + merged_w1) + c0 * merged_w1) *
          global_weight
      }
      for x in 1..<(width - 1) {
        let c0 = inb[row_c + x - 1]
        let c1 = inb[row_c + x]
        let c2 = inb[row_c + x + 1]
        out[out_off + x] = (c1 * merged_w0 + (c0 + c2) * merged_w1) *
          global_weight
      }
      {
        let c0 = inb[row_c + width - 2]
        let c1 = inb[row_c + width - 1]
        out[out_off + width - 1] = (c1 * (merged_w0 + merged_w1) +
          c0 * merged_w1) *
          global_weight
      }
    }
  }
}

///|
/// Inner rows: `t`, `c`, `b` are offsets of the top, centre and bottom rows.
fn run_gabor_row_generic(
  inb : FixedArray[Float],
  t : Int,
  c : Int,
  b : Int,
  out : FixedArray[Float],
  out_off : Int,
  width : Int,
  w0 : Float,
  w1 : Float,
) -> Unit {
  if width == 0 {
    return
  }
  let global_weight : Float = 1.0 / (1.0 + w0 * 4.0 + w1 * 4.0)
  if width == 1 {
    let tv = inb[t]
    let cv = inb[c]
    let bv = inb[b]
    let sum_side = tv + 2.0 * cv + bv
    let sum_diag : Float = 2.0 * (tv + bv)
    let unweighted_sum = cv + sum_side * w0 + sum_diag * w1
    out[out_off] = unweighted_sum * global_weight
    return
  }
  {
    // t1 t1 t0
    // c1 c1 c0
    // b1 b1 b0
    let t1 = inb[t]
    let c1 = inb[c]
    let b1 = inb[b]
    let t0 = inb[t + 1]
    let c0 = inb[c + 1]
    let b0 = inb[b + 1]
    let sum_side = t1 + c0 + c1 + b1
    let sum_diag = t0 + t1 + b0 + b1
    let unweighted_sum = c1 + sum_side * w0 + sum_diag * w1
    out[out_off] = unweighted_sum * global_weight
  }
  for x in 1..<(width - 1) {
    let t0 = inb[t + x - 1]
    let t1 = inb[t + x]
    let t2 = inb[t + x + 1]
    let c0 = inb[c + x - 1]
    let c1 = inb[c + x]
    let c2 = inb[c + x + 1]
    let b0 = inb[b + x - 1]
    let b1 = inb[b + x]
    let b2 = inb[b + x + 1]
    let sum_side = t1 + c0 + c2 + b1
    let sum_diag = t0 + t2 + b0 + b2
    let unweighted_sum = c1 + sum_side * w0 + sum_diag * w1
    out[out_off + x] = unweighted_sum * global_weight
  }
  {
    // t0 t1 t1
    // c0 c1 c1
    // b0 b1 b1
    let t1 = inb[t + width - 1]
    let c1 = inb[c + width - 1]
    let b1 = inb[b + width - 1]
    let t0 = inb[t + width - 2]
    let c0 = inb[c + width - 2]
    let b0 = inb[b + width - 2]
    let sum_side = t1 + c0 + c1 + b1
    let sum_diag = t0 + t1 + b0 + b1
    let unweighted_sum = c1 + sum_side * w0 + sum_diag * w1
    out[out_off + width - 1] = unweighted_sum * global_weight
  }
}
