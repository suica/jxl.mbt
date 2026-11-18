// Port of jxl-render `vardct/x86_64/transform.rs` (the SSE2 kernels for DCT4
// and DCT4x8). A group of four lanes is a `FixedArray[Float]` of 16 values,
// lane `i` at `[4 * i, 4 * i + 4)`.

///|
/// `_MM_TRANSPOSE4_PS`.
fn transpose_lane(lanes : FixedArray[Float]) -> Unit {
  for i in 0..<4 {
    for j in (i + 1)..<4 {
      let t = lanes[i * 4 + j]
      lanes[i * 4 + j] = lanes[j * 4 + i]
      lanes[j * 4 + i] = t
    }
  }
}

///|
/// `dct4_inverse` on four lanes (component-wise).
fn dct4_inverse_lanes(lanes : FixedArray[Float]) -> Unit {
  for j in 0..<4 {
    let (o0, o1, o2, o3) = dct4_inverse_x86(
      lanes[j],
      lanes[4 + j],
      lanes[8 + j],
      lanes[12 + j],
    )
    lanes[j] = o0
    lanes[4 + j] = o1
    lanes[8 + j] = o2
    lanes[12 + j] = o3
  }
}

///|
/// Loads row `y` of `coeff` as even (`s0`) and odd (`s1`) columns into lane
/// `i` (`_mm_shuffle_ps::<0b10001000>` / `<0b11011101>`).
fn load_even_odd(
  coeff : @grid.SubGrid[Float],
  y : Int32,
  s0 : FixedArray[Float],
  s1 : FixedArray[Float],
  i : Int32,
) -> Unit {
  let r = coeff.row_offset(y)
  let buf = coeff.buf
  for k in 0..<4 {
    s0[i * 4 + k] = buf[r + 2 * k]
    s1[i * 4 + k] = buf[r + 2 * k + 1]
  }
}

///|
/// Stores lane `i` of `lanes` to `coeff` at `(x, y)..(x + 4, y)`.
fn store_lane(
  coeff : @grid.SubGrid[Float],
  x : Int32,
  y : Int32,
  lanes : FixedArray[Float],
  i : Int32,
) -> Unit {
  let r = coeff.row_offset(y) + x
  for k in 0..<4 {
    coeff.buf[r + k] = lanes[i * 4 + k]
  }
}

///|
/// Stores `dct4_vec_inverse(lane i)` to `coeff` at `(x, y)..(x + 4, y)`.
fn store_lane_vec_inverse(
  coeff : @grid.SubGrid[Float],
  x : Int32,
  y : Int32,
  lanes : FixedArray[Float],
  i : Int32,
) -> Unit {
  let tmp = FixedArray::make(4, (0.0 : Float))
  for k in 0..<4 {
    tmp[k] = lanes[i * 4 + k]
  }
  dct4_vec_inverse(tmp, 0)
  let r = coeff.row_offset(y) + x
  for k in 0..<4 {
    coeff.buf[r + k] = tmp[k]
  }
}

///|
/// `dct8_vec_inverse` of row `y`, stored into lane `i` of `l` and `r`.
fn load_dct8_vec_inverse(
  coeff : @grid.SubGrid[Float],
  y : Int32,
  l : FixedArray[Float],
  r : FixedArray[Float],
  i : Int32,
) -> Unit {
  let tmp = FixedArray::make(8, (0.0 : Float))
  let off = coeff.row_offset(y)
  for k in 0..<8 {
    tmp[k] = coeff.buf[off + k]
  }
  dct8_vec_inverse(tmp, 0)
  for k in 0..<4 {
    l[i * 4 + k] = tmp[k]
    r[i * 4 + k] = tmp[4 + k]
  }
}

///|
/// `transform_dct4_x86_64_sse2`.
fn transform_dct4_x86_64(coeff : @grid.SubGrid[Float]) -> Unit {
  aux_idct2_in_place(coeff, 2)
  let s0 = FixedArray::make(16, (0.0 : Float))
  let s1 = FixedArray::make(16, (0.0 : Float))
  for y2 in 0..<4 {
    load_even_odd(coeff, y2 * 2, s0, s1, y2)
  }
  transpose_lane(s0)
  transpose_lane(s1)
  dct4_inverse_lanes(s0)
  dct4_inverse_lanes(s1)
  for y2 in 0..<4 {
    store_lane_vec_inverse(coeff, 0, y2, s0, y2)
    store_lane_vec_inverse(coeff, 4, y2, s1, y2)
    load_even_odd(coeff, y2 * 2 + 1, s0, s1, y2)
  }
  transpose_lane(s0)
  transpose_lane(s1)
  dct4_inverse_lanes(s0)
  dct4_inverse_lanes(s1)
  for y in 0..<4 {
    store_lane_vec_inverse(coeff, 0, y + 4, s0, y)
    store_lane_vec_inverse(coeff, 4, y + 4, s1, y)
  }
}

///|
/// `transform_dct4x8_x86_64_sse2::<TR>`.
fn transform_dct4x8_x86_64(coeff : @grid.SubGrid[Float], tr : Bool) -> Unit {
  let coeff0 = coeff.get(0, 0)
  let coeff1 = coeff.get(0, 1)
  coeff.set(0, 0, coeff0 + coeff1)
  coeff.set(0, 1, coeff0 - coeff1)
  let s0 = FixedArray::make(16, (0.0 : Float))
  let s1 = FixedArray::make(16, (0.0 : Float))
  if tr {
    for y2 in 0..<4 {
      load_dct8_vec_inverse(coeff, y2 * 2, s0, s1, y2)
    }
    dct4_inverse_lanes(s0)
    dct4_inverse_lanes(s1)
    transpose_lane(s0)
    transpose_lane(s1)
    let rows : FixedArray[Int32] = [1, 5, 3, 7]
    let l = FixedArray::make(16, (0.0 : Float))
    let r = FixedArray::make(16, (0.0 : Float))
    for y2 in 0..<4 {
      load_dct8_vec_inverse(coeff, rows[y2], l, r, y2)
      store_lane(coeff, 0, y2, s0, y2)
      store_lane(coeff, 0, y2 + 4, s1, y2)
      for k in 0..<4 {
        s0[y2 * 4 + k] = l[y2 * 4 + k]
        s1[y2 * 4 + k] = r[y2 * 4 + k]
      }
    }
    // scratch.swap(1, 2)
    for k in 0..<4 {
      let t0 = s0[4 + k]
      s0[4 + k] = s0[8 + k]
      s0[8 + k] = t0
      let t1 = s1[4 + k]
      s1[4 + k] = s1[8 + k]
      s1[8 + k] = t1
    }
    dct4_inverse_lanes(s0)
    dct4_inverse_lanes(s1)
    transpose_lane(s0)
    transpose_lane(s1)
    for y in 0..<4 {
      store_lane(coeff, 4, y, s0, y)
      store_lane(coeff, 4, y + 4, s1, y)
    }
  } else {
    for y2 in 0..<4 {
      load_dct8_vec_inverse(coeff, y2 * 2, s0, s1, y2)
    }
    dct4_inverse_lanes(s0)
    dct4_inverse_lanes(s1)
    for y2 in 0..<4 {
      store_lane(coeff, 0, y2, s0, y2)
      store_lane(coeff, 4, y2, s1, y2)
      load_dct8_vec_inverse(coeff, y2 * 2 + 1, s0, s1, y2)
    }
    dct4_inverse_lanes(s0)
    dct4_inverse_lanes(s1)
    for y in 0..<4 {
      store_lane(coeff, 0, y + 4, s0, y)
      store_lane(coeff, 4, y + 4, s1, y)
    }
  }
}
