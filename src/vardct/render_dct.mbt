// Port of jxl-render `vardct/dct_common.rs` and `vardct/generic/dct.rs`.

///|
/// Direction of a DCT.
#derive(Eq, Debug)
pub(all) enum DctDirection {
  Forward
  Inverse
}

///|
/// `std::f32::consts::SQRT_2`.
let sqrt_2_f32 : Float = Float::reinterpret_from_uint(0x3FB504F3)

///|
/// `std::f32::consts::FRAC_1_SQRT_2`.
let frac_1_sqrt_2_f32 : Float = Float::reinterpret_from_uint(0x3F3504F3)

///|
let sec_half_small_table : FixedArray[FixedArray[Float]] = [
  // n = 4
  [0.541196100146197, 1.3065629648763764],
  // n = 8
  [
    0.5097955791041592, 0.6013448869350453, 0.8999762231364156, 2.5629154477415055,
  ],
  // n = 16
  [
    0.5024192861881557, 0.5224986149396889, 0.5669440348163577, 0.6468217833599901,
    0.7881546234512502, 1.060677685990347, 1.7224470982383342, 5.101148618689155,
  ],
  // n = 32
  [
    0.5006029982351963, 0.5054709598975436, 0.5154473099226246, 0.5310425910897841,
    0.5531038960344445, 0.5829349682061339, 0.6225041230356648, 0.6748083414550057,
    0.7445362710022984, 0.8393496454155268, 0.9725682378619608, 1.1694399334328847,
    1.4841646163141662, 2.057781009953411, 3.407608418468719, 10.190008123548033,
  ],
]

///|
/// Lazily computed `sec_half` tables for n >= 64 (upstream `SEC_HALF_LARGE`).
let sec_half_large : Map[Int32, FixedArray[Float]] = Map([])

///|
/// Table of `1 / (2 cos((2k + 1) / 2n * pi))`, `k < n / 2`.
///
/// Tables for n >= 64 are computed on first use with `f32` arithmetic and
/// `cosf`, like upstream.
pub fn sec_half(n : Int32) -> FixedArray[Float] {
  let idx = n.ctz() - 2
  if idx >= 4 {
    match sec_half_large.get(idx - 4) {
      Some(table) => table
      None => {
        let table = FixedArray::make(n / 2, (0.0 : Float))
        for k in 0..<(n / 2) {
          let theta = Float::from_int(2 * k + 1) /
            Float::from_int(2 * n) *
            pi_f32
          table[k] = (1.0 : Float) / cosf(theta) / 2.0
        }
        sec_half_large.set(idx - 4, table)
        table
      }
    }
  } else {
    sec_half_small_table[idx]
  }
}

///|
/// `sec_half` for n <= 32 (precomputed).
pub fn sec_half_small(n : Int32) -> FixedArray[Float] {
  sec_half_small_table[n.ctz() - 2]
}

///|
/// `std::f32::consts::PI`.
let pi_f32 : Float = Float::reinterpret_from_uint(0x40490FDB)

///|
let scale_f_table : FixedArray[Float] = [
  1.0000000000000000, 0.9996047255830407, 0.9984194528776054, 0.9964458326264695,
  0.9936866130906366, 0.9901456355893141, 0.9858278282666936, 0.9807391980963174,
  0.9748868211368796, 0.9682788310563117, 0.9609244059440204, 0.9528337534340876,
  0.9440180941651672, 0.9344896436056892, 0.9242615922757944, 0.9133480844001980,
  0.9017641950288744, 0.8895259056651056, 0.8766500784429904, 0.8631544288990163,
  0.8490574973847023, 0.8343786191696513, 0.8191378932865928, 0.8033561501721485,
  0.7870549181591013, 0.7702563888779096, 0.7529833816270532, 0.7352593067735488,
  0.7171081282466044, 0.6985543251889097, 0.6796228528314652, 0.6603391026591464,
]

///|
/// Precomputed for c = 0..32, b = 256.
pub fn scale_f(c : Int32, logb : Int32) -> Float {
  scale_f_table[c << logb]
}

///|
/// In-place 2D DCT of `io`, generic (scalar) implementation
/// (`generic::dct_2d`).
pub fn dct_2d_generic(
  io : @grid.SubGrid[Float],
  direction : DctDirection,
) -> Unit {
  let width = io.width
  let height = io.height
  if width * height <= 1 {
    return
  }
  let mul : Float = if direction == Forward { 0.5 } else { 1.0 }
  let buf = io.buf
  if width == 2 && height == 1 {
    let v0 = io.get(0, 0)
    let v1 = io.get(1, 0)
    io.set(0, 0, (v0 + v1) * mul)
    io.set(1, 0, (v0 - v1) * mul)
    return
  }
  if width == 1 && height == 2 {
    let v0 = io.get(0, 0)
    let v1 = io.get(0, 1)
    io.set(0, 0, (v0 + v1) * mul)
    io.set(0, 1, (v0 - v1) * mul)
    return
  }
  if width == 2 && height == 2 {
    let v00 = io.get(0, 0)
    let v01 = io.get(1, 0)
    let v10 = io.get(0, 1)
    let v11 = io.get(1, 1)
    io.set(0, 0, (v00 + v01 + v10 + v11) * mul * mul)
    io.set(1, 0, (v00 - v01 + v10 - v11) * mul * mul)
    io.set(0, 1, (v00 + v01 - v10 - v11) * mul * mul)
    io.set(1, 1, (v00 - v01 - v10 + v11) * mul * mul)
    return
  }
  let max_dim = if width > height { width } else { height }
  let scratch = FixedArray::make(max_dim, (0.0 : Float))
  if height == 1 {
    dct(buf, io.row_offset(0), width, scratch, 0, direction)
    return
  }
  if width == 1 {
    let row = FixedArray::make(height, (0.0 : Float))
    for y in 0..<height {
      row[y] = io.get(0, y)
    }
    dct(row, 0, height, scratch, 0, direction)
    for y in 0..<height {
      io.set(0, y, row[y])
    }
    return
  }
  if height == 2 {
    let off0 = io.row_offset(0)
    let off1 = io.row_offset(1)
    for x in 0..<width {
      let tv0 = buf[off0 + x]
      let tv1 = buf[off1 + x]
      buf[off0 + x] = (tv0 + tv1) * mul
      buf[off1 + x] = (tv0 - tv1) * mul
    }
    dct(buf, off0, width, scratch, 0, direction)
    dct(buf, off1, width, scratch, 0, direction)
    return
  }
  if width == 2 {
    let row = FixedArray::make(height * 2, (0.0 : Float))
    for y in 0..<height {
      let v0 = io.get(0, y)
      let v1 = io.get(1, y)
      row[y] = (v0 + v1) * mul
      row[height + y] = (v0 - v1) * mul
    }
    dct(row, 0, height, scratch, 0, direction)
    dct(row, height, height, scratch, 0, direction)
    for y in 0..<height {
      io.set(0, y, row[y])
      io.set(1, y, row[height + y])
    }
    return
  }
  for y in 0..<height {
    dct(buf, io.row_offset(y), width, scratch, 0, direction)
  }
  let block_size = if width < height { width } else { height }
  transpose_blocks(io, block_size)
  if block_size == height {
    for y in 0..<height {
      let off = io.row_offset(y)
      let mut x = 0
      while x + height <= width {
        dct(buf, off + x, height, scratch, 0, direction)
        x += height
      }
    }
  } else {
    let row = FixedArray::make(height, (0.0 : Float))
    let num_chunks = height / width
    for y in 0..<width {
      for idx in 0..<num_chunks {
        let src = io.row_offset(y + idx * block_size)
        FixedArray::blit_to(
          buf,
          row,
          len=width,
          src_offset=src,
          dst_offset=idx * width,
        )
      }
      dct(row, 0, height, scratch, 0, direction)
      for idx in 0..<num_chunks {
        let dst = io.row_offset(y + idx * block_size)
        FixedArray::blit_to(
          row,
          buf,
          len=width,
          src_offset=idx * width,
          dst_offset=dst,
        )
      }
    }
  }
  transpose_blocks(io, block_size)
}

///|
fn transpose_blocks(io : @grid.SubGrid[Float], block_size : Int32) -> Unit {
  let mut by = 0
  while by < io.height {
    let mut bx = 0
    while bx < io.width {
      for dy in 0..<block_size {
        for dx in (dy + 1)..<block_size {
          io.swap(bx + dx, by + dy, bx + dy, by + dx)
        }
      }
      bx += block_size
    }
    by += block_size
  }
}

///|
fn dct4(
  i0 : Float,
  i1 : Float,
  i2 : Float,
  i3 : Float,
  direction : DctDirection,
) -> (Float, Float, Float, Float) {
  let sec0 : Float = 0.5411961
  let sec1 : Float = 1.306563
  if direction == Forward {
    let sum03 = i0 + i3
    let sum12 = i1 + i2
    let tmp0 = (i0 - i3) * sec0
    let tmp1 = (i1 - i2) * sec1
    let out0 = (tmp0 + tmp1) / 4.0
    let out1 = (tmp0 - tmp1) / 4.0
    (
      (sum03 + sum12) / 4.0,
      out0 * sqrt_2_f32 + out1,
      (sum03 - sum12) / 4.0,
      out1,
    )
  } else {
    let tmp0 = i1 * sqrt_2_f32
    let tmp1 = i1 + i3
    let out0 = (tmp0 + tmp1) * sec0
    let out1 = (tmp0 - tmp1) * sec1
    let sum02 = i0 + i2
    let sub02 = i0 - i2
    (sum02 + out0, sub02 + out1, sub02 - out1, sum02 - out0)
  }
}

///|
/// 1D DCT of `io[off..off + n]`, using `scratch[soff..soff + n]` as scratch space.
fn dct(
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
      io[off] = tmp0 / 2.0
      io[off + 1] = tmp1 / 2.0
    } else {
      io[off] = tmp0
      io[off + 1] = tmp1
    }
    return
  }
  if n == 4 {
    let (o0, o1, o2, o3) = dct4(
      io[off],
      io[off + 1],
      io[off + 2],
      io[off + 3],
      direction,
    )
    io[off] = o0
    io[off + 1] = o1
    io[off + 2] = o2
    io[off + 3] = o3
    return
  }
  if n == 8 {
    let sec = sec_half_small_table[1]
    if direction == Forward {
      let (a0, a1, a2, a3) = dct4(
        (io[off] + io[off + 7]) / 2.0,
        (io[off + 1] + io[off + 6]) / 2.0,
        (io[off + 2] + io[off + 5]) / 2.0,
        (io[off + 3] + io[off + 4]) / 2.0,
        Forward,
      )
      let (b0, b1, b2, b3) = dct4(
        (io[off] - io[off + 7]) * sec[0] / 2.0,
        (io[off + 1] - io[off + 6]) * sec[1] / 2.0,
        (io[off + 2] - io[off + 5]) * sec[2] / 2.0,
        (io[off + 3] - io[off + 4]) * sec[3] / 2.0,
        Forward,
      )
      io[off] = a0
      io[off + 2] = a1
      io[off + 4] = a2
      io[off + 6] = a3
      let b0 = b0 * sqrt_2_f32
      io[off + 1] = b0 + b1
      io[off + 3] = b1 + b2
      io[off + 5] = b2 + b3
      io[off + 7] = b3
    } else {
      let (a0, a1, a2, a3) = dct4(
        io[off],
        io[off + 2],
        io[off + 4],
        io[off + 6],
        Inverse,
      )
      let (b0, b1, b2, b3) = dct4(
        io[off + 1] * sqrt_2_f32,
        io[off + 3] + io[off + 1],
        io[off + 5] + io[off + 3],
        io[off + 7] + io[off + 5],
        Inverse,
      )
      let r0 = b0 * sec[0]
      let r1 = b1 * sec[1]
      let r2 = b2 * sec[2]
      let r3 = b3 * sec[3]
      io[off] = a0 + r0
      io[off + 7] = a0 - r0
      io[off + 1] = a1 + r1
      io[off + 6] = a1 - r1
      io[off + 2] = a2 + r2
      io[off + 5] = a2 - r2
      io[off + 3] = a3 + r3
      io[off + 4] = a3 - r3
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
      scratch[in0 + idx] = (io[off + idx] + io[off + n - idx - 1]) / 2.0
      scratch[in1 + idx] = (io[off + idx] - io[off + n - idx - 1]) / 2.0
    }
    for idx in 0..<half {
      scratch[in1 + idx] = scratch[in1 + idx] * sec[idx]
    }
    dct(scratch, in0, half, io, off, Forward)
    dct(scratch, in1, half, io, off + half, Forward)
    scratch[in1] = scratch[in1] * sqrt_2_f32
    for idx in 0..<(half - 1) {
      scratch[in1 + idx] = scratch[in1 + idx] + scratch[in1 + idx + 1]
    }
    for idx in 0..<half {
      io[off + idx * 2] = scratch[in0 + idx]
      io[off + idx * 2 + 1] = scratch[in1 + idx]
    }
  } else {
    for idx in 0..<half {
      scratch[in0 + idx] = io[off + idx * 2]
      scratch[in1 + idx] = io[off + idx * 2 + 1]
    }
    for idx in 1..<half {
      scratch[in1 + half - idx] = scratch[in1 + half - idx] +
        scratch[in1 + half - idx - 1]
    }
    scratch[in1] = scratch[in1] * sqrt_2_f32
    dct(scratch, in0, half, io, off, Inverse)
    dct(scratch, in1, half, io, off + half, Inverse)
    for idx in 0..<half {
      scratch[in1 + idx] = scratch[in1 + idx] * sec[idx]
    }
    for idx in 0..<half {
      io[off + idx] = scratch[in0 + idx] + scratch[in1 + idx]
      io[off + n - idx - 1] = scratch[in0 + idx] - scratch[in1 + idx]
    }
  }
}
