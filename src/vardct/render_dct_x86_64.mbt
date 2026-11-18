// Port of jxl-render `vardct/x86_64/dct/mod.rs`: the SSE2 DCT that upstream
// uses on x86_64. Each `__m128` lane operation is an IEEE `f32` operation, so
// it is emulated here with the same operation sequence on scalars. Upstream's
// `muladd` is `mul` followed by `add` (jxl-oxide is not built with
// `target_feature = "fma"`), which is what is done here.
//
// Results differ from `dct_2d_generic` in the last bits (different pass order
// and different 8x8/4x4 vector kernels); this path is what jxl-oxide runs on
// x86_64, so it is the one used by `transform`.

///|
/// `dct_2d_x86_64_sse2`: falls back to `dct_2d_generic` unless the view is a
/// multiple of 4 wide and high and its rows are 16-byte aligned. Buffers are
/// assumed to start aligned (as upstream's `AlignedGrid`), so a row is aligned
/// when `offset` and `stride` are multiples of 4.
pub fn dct_2d(io : @grid.SubGrid[Float], direction : DctDirection) -> Unit {
  if io.width % 4 != 0 || io.height % 4 != 0 {
    return dct_2d_generic(io, direction)
  }
  if io.offset % 4 != 0 || io.stride % 4 != 0 {
    return dct_2d_generic(io, direction)
  }
  if io.width == 8 && io.height == 8 {
    return dct8x8_x86(io, direction)
  }
  dct_2d_lane(io, direction)
}

///|
/// `dct_2d_lane`: column DCTs, then row DCTs (the 4x4 lane transposes of
/// upstream only move data).
fn dct_2d_lane(io : @grid.SubGrid[Float], direction : DctDirection) -> Unit {
  let width = io.width
  let height = io.height
  let buf = io.buf
  let max_dim = if width > height { width } else { height }
  let scratch = FixedArray::make(max_dim, (0.0 : Float))
  let col = FixedArray::make(height, (0.0 : Float))
  for x in 0..<width {
    for y in 0..<height {
      col[y] = buf[io.row_offset(y) + x]
    }
    dct_x86(col, 0, height, scratch, 0, direction)
    for y in 0..<height {
      buf[io.row_offset(y) + x] = col[y]
    }
  }
  for y in 0..<height {
    dct_x86(buf, io.row_offset(y), width, scratch, 0, direction)
  }
}

///|
fn dct4_forward_x86(
  i0 : Float,
  i1 : Float,
  i2 : Float,
  i3 : Float,
) -> (Float, Float, Float, Float) {
  let sec0 : Float = (0.5411961 : Float) / 4.0
  let sec1 : Float = (1.306563 : Float) / 4.0
  let sum03 = i0 + i3
  let sum12 = i1 + i2
  let tmp0 = (i0 - i3) * sec0
  let tmp1 = (i1 - i2) * sec1
  let out0 = tmp0 + tmp1
  let out1 = tmp0 - tmp1
  (
    (sum03 + sum12) * 0.25,
    out0 * sqrt_2_f32 + out1,
    (sum03 - sum12) * 0.25,
    out1,
  )
}

///|
fn dct4_inverse_x86(
  i0 : Float,
  i1 : Float,
  i2 : Float,
  i3 : Float,
) -> (Float, Float, Float, Float) {
  let sec0 : Float = 0.5411961
  let sec1 : Float = 1.306563
  let tmp0 = i1 * sqrt_2_f32
  let tmp1 = i1 + i3
  let out0 = (tmp0 + tmp1) * sec0
  let out1 = (tmp0 - tmp1) * sec1
  let sum02 = i0 + i2
  let sub02 = i0 - i2
  (sum02 + out0, sub02 + out1, sub02 - out1, sum02 - out0)
}

///|
/// `dct8_forward` on `io[off + k * step]`, k < 8.
fn dct8_forward_x86(io : FixedArray[Float], off : Int32, step : Int32) -> Unit {
  let sec = sec_half_small_table[1]
  let g = k => io[off + k * step]
  let (a0, a1, a2, a3) = dct4_forward_x86(
    (g(0) + g(7)) * 0.5,
    (g(1) + g(6)) * 0.5,
    (g(2) + g(5)) * 0.5,
    (g(3) + g(4)) * 0.5,
  )
  let (b0, b1, b2, b3) = dct4_forward_x86(
    (g(0) - g(7)) * (sec[0] / 2.0),
    (g(1) - g(6)) * (sec[1] / 2.0),
    (g(2) - g(5)) * (sec[2] / 2.0),
    (g(3) - g(4)) * (sec[3] / 2.0),
  )
  io[off] = a0
  io[off + 2 * step] = a1
  io[off + 4 * step] = a2
  io[off + 6 * step] = a3
  let b0 = b0 * sqrt_2_f32
  io[off + step] = b0 + b1
  io[off + 3 * step] = b1 + b2
  io[off + 5 * step] = b2 + b3
  io[off + 7 * step] = b3
}

///|
/// `dct8_inverse` on `io[off + k * step]`, k < 8.
fn dct8_inverse_x86(io : FixedArray[Float], off : Int32, step : Int32) -> Unit {
  let sec = sec_half_small_table[1]
  let g = k => io[off + k * step]
  let (a0, a1, a2, a3) = dct4_inverse_x86(g(0), g(2), g(4), g(6))
  let (b0, b1, b2, b3) = dct4_inverse_x86(
    g(1) * sqrt_2_f32,
    g(3) + g(1),
    g(5) + g(3),
    g(7) + g(5),
  )
  let r0 = b0 * sec[0]
  let r1 = b1 * sec[1]
  let r2 = b2 * sec[2]
  let r3 = b3 * sec[3]
  io[off] = a0 + r0
  io[off + 7 * step] = a0 - r0
  io[off + step] = a1 + r1
  io[off + 6 * step] = a1 - r1
  io[off + 2 * step] = a2 + r2
  io[off + 5 * step] = a2 - r2
  io[off + 3 * step] = a3 + r3
  io[off + 4 * step] = a3 - r3
}

///|
/// The lane `dct` of upstream, on one lane.
fn dct_x86(
  io : FixedArray[Float],
  off : Int32,
  n : Int32,
  scratch : FixedArray[Float],
  soff : Int32,
  direction : DctDirection,
) -> Unit {
  if n <= 1 {
    return
  }
  if n == 2 {
    let tmp0 = io[off] + io[off + 1]
    let tmp1 = io[off] - io[off + 1]
    if direction == Forward {
      io[off] = tmp0 * 0.5
      io[off + 1] = tmp1 * 0.5
    } else {
      io[off] = tmp0
      io[off + 1] = tmp1
    }
    return
  }
  if n == 4 {
    let (o0, o1, o2, o3) = if direction == Forward {
      dct4_forward_x86(io[off], io[off + 1], io[off + 2], io[off + 3])
    } else {
      dct4_inverse_x86(io[off], io[off + 1], io[off + 2], io[off + 3])
    }
    io[off] = o0
    io[off + 1] = o1
    io[off + 2] = o2
    io[off + 3] = o3
    return
  }
  if n == 8 {
    if direction == Forward {
      dct8_forward_x86(io, off, 1)
    } else {
      dct8_inverse_x86(io, off, 1)
    }
    return
  }
  guard n.popcnt() == 1 else { abort("DCT size is not a power of two") }
  let half = n / 2
  let in0 = soff
  let in1 = soff + half
  let sec = sec_half(n)
  if direction == Forward {
    for idx in 0..<half {
      scratch[in0 + idx] = (io[off + idx] + io[off + n - idx - 1]) * 0.5
      scratch[in1 + idx] = (io[off + idx] - io[off + n - idx - 1]) *
        (sec[idx] / 2.0)
    }
    dct_x86(scratch, in0, half, io, off, Forward)
    dct_x86(scratch, in1, half, io, off + half, Forward)
    for idx in 0..<half {
      io[off + idx * 2] = scratch[in0 + idx]
    }
    scratch[in1] = scratch[in1] * sqrt_2_f32
    for idx in 0..<(half - 1) {
      io[off + idx * 2 + 1] = scratch[in1 + idx] + scratch[in1 + idx + 1]
    }
    io[off + n - 1] = scratch[in1 + half - 1]
  } else {
    for i in 1..<half {
      let idx = half - i
      scratch[in0 + idx] = io[off + idx * 2]
      scratch[in1 + idx] = io[off + idx * 2 + 1] + io[off + idx * 2 - 1]
    }
    scratch[in0] = io[off]
    scratch[in1] = io[off + 1] * sqrt_2_f32
    dct_x86(scratch, in0, half, io, off, Inverse)
    dct_x86(scratch, in1, half, io, off + half, Inverse)
    for idx in 0..<half {
      let r = scratch[in1 + idx] * sec[idx]
      io[off + idx] = scratch[in0 + idx] + r
      io[off + n - idx - 1] = scratch[in0 + idx] - r
    }
  }
}

///|
/// `dct4_vec_forward`: a 4-point DCT inside one lane.
fn dct4_vec_forward(v : FixedArray[Float], o : Int32) -> Unit {
  let sec0 : Float = 0.5411961
  let sec1 : Float = 1.306563
  let v0 = v[o]
  let v1 = v[o + 1]
  let v2 = v[o + 2]
  let v3 = v[o + 3]
  // addsub = v * [1, 1, -1, -1] + reverse(v)
  let s03 = v0 * 1.0 + v3
  let s12 = v1 * 1.0 + v2
  let d12 = v2 * -1.0 + v1
  let d03 = v3 * -1.0 + v0
  // a = [s03, d03, s12, d12], b = [s12, d12, s03, d03]
  let ma1 = (frac_1_sqrt_2_f32 / 2.0 + 0.25) * sec0
  let ma3 = (-0.25 : Float) * sec1
  let mb1 = (frac_1_sqrt_2_f32 / 2.0 - 0.25) * sec1
  let mb3 = (0.25 : Float) * sec0
  v[o] = s03 * 0.25 + s12 * 0.25
  v[o + 1] = d03 * ma1 + d12 * mb1
  v[o + 2] = s12 * -0.25 + s03 * 0.25
  v[o + 3] = d12 * ma3 + d03 * mb3
}

///|
/// `dct4_vec_inverse`: a 4-point IDCT inside one lane.
fn dct4_vec_inverse(v : FixedArray[Float], o : Int32) -> Unit {
  let sec0 : Float = 0.5411961
  let sec1 : Float = 1.306563
  let v0 = v[o]
  let v1 = v[o + 1]
  let v2 = v[o + 2]
  let v3 = v[o + 3]
  let ma1 = (sqrt_2_f32 + 1.0) * sec0
  let mb3 = (sqrt_2_f32 - 1.0) * sec1
  // tmp = v * mul_a + flip(v) * mul_b, flip(v) = [v2, v3, v0, v1]
  let t0 = v0 * 1.0 + v2 * 1.0
  let t1 = v1 * ma1 + v3 * sec0
  let t2 = v2 * -1.0 + v0 * 1.0
  let t3 = v3 * -sec1 + v1 * mb3
  // tmp_b * [1, 1, -1, -1] + tmp_a, tmp_a = [t0, t2, t2, t0], tmp_b = [t1, t3, t3, t1]
  v[o] = t1 * 1.0 + t0
  v[o + 1] = t3 * 1.0 + t2
  v[o + 2] = t3 * -1.0 + t2
  v[o + 3] = t1 * -1.0 + t0
}

///|
let dct8_vec_forward_sec : FixedArray[Float] = [
  0.2548977895520796, 0.30067244346752264, 0.4499881115682078, 1.2814577238707527,
]

///|
/// `dct8_vec_forward` on the 8 values `row[o..o + 8]` (two lanes).
fn dct8_vec_forward(row : FixedArray[Float], o : Int32) -> Unit {
  let in0 = FixedArray::make(4, (0.0 : Float))
  let in1 = FixedArray::make(4, (0.0 : Float))
  for i in 0..<4 {
    let l = row[o + i]
    let r = row[o + 7 - i]
    in0[i] = (l + r) * 0.5
    in1[i] = (l - r) * dct8_vec_forward_sec[i]
  }
  dct4_vec_forward(in0, 0)
  dct4_vec_forward(in1, 0)
  // output1 * [sqrt2, 1, 1, 1] + (output1 >> 1 lane)
  let b0 = in1[0] * sqrt_2_f32 + in1[1]
  let b1 = in1[1] * 1.0 + in1[2]
  let b2 = in1[2] * 1.0 + in1[3]
  let b3 = in1[3] * 1.0 + 0.0
  // unpacklo/unpackhi(output0, output1)
  row[o] = in0[0]
  row[o + 1] = b0
  row[o + 2] = in0[1]
  row[o + 3] = b1
  row[o + 4] = in0[2]
  row[o + 5] = b2
  row[o + 6] = in0[3]
  row[o + 7] = b3
}

///|
/// `dct8_vec_inverse` on the 8 values `row[o..o + 8]` (two lanes).
fn dct8_vec_inverse(row : FixedArray[Float], o : Int32) -> Unit {
  let sec = sec_half_small_table[1]
  // input0 = even elements, input1 = odd elements
  let in0 : FixedArray[Float] = [row[o], row[o + 2], row[o + 4], row[o + 6]]
  let i0 = row[o + 1]
  let i1 = row[o + 3]
  let i2 = row[o + 5]
  let i3 = row[o + 7]
  // input1 * [sqrt2, 1, 1, 1] + (input1 << 1 lane)
  let in1 : FixedArray[Float] = [
    i0 * sqrt_2_f32 + 0.0,
    i1 * 1.0 + i0,
    i2 * 1.0 + i1,
    i3 * 1.0 + i2,
  ]
  dct4_vec_inverse(in0, 0)
  dct4_vec_inverse(in1, 0)
  for i in 0..<4 {
    let r = in1[i] * sec[i]
    row[o + i] = in0[i] + r
    // reverse(output0 - output1)
    row[o + 7 - i] = in0[i] - r
  }
}

///|
/// `dct8x8`: column 8-point DCTs, then in-lane row DCTs.
fn dct8x8_x86(io : @grid.SubGrid[Float], direction : DctDirection) -> Unit {
  let buf = io.buf
  let base = io.offset
  let stride = io.stride
  if direction == Forward {
    for x in 0..<8 {
      dct8_forward_x86(buf, base + x, stride)
    }
    for y in 0..<8 {
      dct8_vec_forward(buf, io.row_offset(y))
    }
  } else {
    for x in 0..<8 {
      dct8_inverse_x86(buf, base + x, stride)
    }
    for y in 0..<8 {
      dct8_vec_inverse(buf, io.row_offset(y))
    }
  }
}
