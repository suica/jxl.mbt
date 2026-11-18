// Port of jxl-render `vardct/transform_common.rs` and
// `vardct/generic/transform.rs`.

///|
/// `f32::mul_add`: `a * b + c` with a single rounding (fused multiply-add).
fn fma_f32(a : Float, b : Float, c : Float) -> Float {
  // The product of two f32 values is exact in f64.
  let p = a.to_double() * b.to_double()
  let cd = c.to_double()
  let s = p + cd
  // TwoSum: `s + err == p + cd` exactly.
  let bv = s - p
  let err = p - (s - bv) + (cd - bv)
  if err == 0.0 || err != err {
    return Float::from_double(s)
  }
  // `s` is inexact; rounding it to f32 again is only wrong when it lies exactly
  // halfway between two f32 values. Nudge it towards the exact value then.
  let bits = s.reinterpret_as_uint64()
  if (bits & 0x1FFFFFFFUL) == 0x10000000UL {
    let toward_larger_magnitude = (err > 0.0) == (s > 0.0)
    let nb = if toward_larger_magnitude { bits + 1UL } else { bits - 1UL }
    return Float::from_double(nb.reinterpret_as_double())
  }
  Float::from_double(s)
}

///|
fn aux_idct2_in_place(block : @grid.SubGrid[Float], size : Int32) -> Unit {
  let num_2x2 = size / 2
  let scratch = FixedArray::make(size * size, (0.0 : Float))
  for y in 0..<num_2x2 {
    for x in 0..<num_2x2 {
      let c00 = block.get(x, y)
      let c01 = block.get(x + num_2x2, y)
      let c10 = block.get(x, y + num_2x2)
      let c11 = block.get(x + num_2x2, y + num_2x2)
      scratch[2 * y * size + 2 * x] = c00 + c01 + c10 + c11
      scratch[2 * y * size + 2 * x + 1] = c00 + c01 - c10 - c11
      scratch[(2 * y + 1) * size + 2 * x] = c00 - c01 + c10 - c11
      scratch[(2 * y + 1) * size + 2 * x + 1] = c00 - c01 - c10 + c11
    }
  }
  for y in 0..<size {
    FixedArray::blit_to(
      scratch,
      block.buf,
      len=size,
      src_offset=y * size,
      dst_offset=block.row_offset(y),
    )
  }
}

///|
fn transform_dct2(coeff : @grid.SubGrid[Float]) -> Unit {
  aux_idct2_in_place(coeff, 2)
  aux_idct2_in_place(coeff, 4)
  aux_idct2_in_place(coeff, 8)
}

///|
fn transform_dct4(coeff : @grid.SubGrid[Float]) -> Unit {
  aux_idct2_in_place(coeff, 2)
  let scratch = FixedArray::make(64, (0.0 : Float))
  for y in 0..<2 {
    for x in 0..<2 {
      let off = (y * 2 + x) * 16
      let sub = @grid.SubGrid::from_buf(scratch, off, 4, 4, 4)
      for iy in 0..<4 {
        for ix in 0..<4 {
          sub.set(iy, ix, coeff.get(x + ix * 2, y + iy * 2))
        }
      }
      dct_2d(sub, Inverse)
    }
  }
  for y in 0..<2 {
    for x in 0..<2 {
      let off = (y * 2 + x) * 16
      for iy in 0..<4 {
        for ix in 0..<4 {
          coeff.set(x * 4 + ix, y * 4 + iy, scratch[off + iy * 4 + ix])
        }
      }
    }
  }
}

///|
fn transform_hornuss(coeff : @grid.SubGrid[Float]) -> Unit {
  aux_idct2_in_place(coeff, 2)
  let scratch = FixedArray::make(64, (0.0 : Float))
  for y in 0..<2 {
    for x in 0..<2 {
      let off = (y * 2 + x) * 16
      for iy in 0..<4 {
        for ix in 0..<4 {
          scratch[off + iy * 4 + ix] = coeff.get(x + ix * 2, y + iy * 2)
        }
      }
      // `Sum for f32` starts from -0.0, so the first addition is exact.
      let mut residual_sum = scratch[off + 1]
      for i in 2..<16 {
        residual_sum = residual_sum + scratch[off + i]
      }
      let avg = scratch[off] - residual_sum / 16.0
      scratch[off] = scratch[off + 5]
      scratch[off + 5] = 0.0
      for i in 0..<16 {
        scratch[off + i] = scratch[off + i] + avg
      }
    }
  }
  for y in 0..<2 {
    for x in 0..<2 {
      let off = (y * 2 + x) * 16
      for iy in 0..<4 {
        for ix in 0..<4 {
          coeff.set(x * 4 + ix, y * 4 + iy, scratch[off + iy * 4 + ix])
        }
      }
    }
  }
}

///|
fn transform_dct4x8(coeff : @grid.SubGrid[Float], tr : Bool) -> Unit {
  let coeff0 = coeff.get(0, 0)
  let coeff1 = coeff.get(0, 1)
  coeff.set(0, 0, coeff0 + coeff1)
  coeff.set(0, 1, coeff0 - coeff1)
  let scratch = FixedArray::make(64, (0.0 : Float))
  for idx in 0..<2 {
    let sub = @grid.SubGrid::from_buf(scratch, idx * 32, 8, 4, 8)
    for iy in 0..<4 {
      for ix in 0..<8 {
        sub.set(ix, iy, coeff.get(ix, iy * 2 + idx))
      }
    }
    dct_2d(sub, Inverse)
  }
  if tr {
    for y in 0..<8 {
      for x in 0..<8 {
        coeff.set(y, x, scratch[y * 8 + x])
      }
    }
  } else {
    for y in 0..<8 {
      FixedArray::blit_to(
        scratch,
        coeff.buf,
        len=8,
        src_offset=y * 8,
        dst_offset=coeff.row_offset(y),
      )
    }
  }
}

///|
fn transform_afv(coeff : @grid.SubGrid[Float], n : Int32) -> Unit {
  guard n < 4 else { abort("invalid AFV index") }
  let flip_x = n % 2
  let flip_y = n / 2
  let coeff_afv = FixedArray::make(16, (0.0 : Float))
  coeff_afv[0] = (coeff.get(0, 0) + coeff.get(1, 0) + coeff.get(0, 1)) * 4.0
  for idx in 1..<16 {
    let iy = idx / 4
    let ix = idx % 4
    coeff_afv[idx] = coeff.get(2 * ix, 2 * iy)
  }
  let samples_afv = FixedArray::make(16, (0.0 : Float))
  for k in 0..<16 {
    let c = coeff_afv[k]
    let basis = afv_basis[k]
    for i in 0..<16 {
      samples_afv[i] = fma_f32(c, basis[i], samples_afv[i])
    }
  }
  let scratch_4x4 = FixedArray::make(16, (0.0 : Float))
  let scratch_4x8 = FixedArray::make(32, (0.0 : Float))
  scratch_4x4[0] = coeff.get(0, 0) - coeff.get(1, 0) + coeff.get(0, 1)
  for iy in 0..<4 {
    for ix in 0..<4 {
      if (ix | iy) == 0 {
        continue
      }
      scratch_4x4[ix * 4 + iy] = coeff.get(2 * ix + 1, 2 * iy)
    }
  }
  dct_2d(@grid.SubGrid::from_buf(scratch_4x4, 0, 4, 4, 4), Inverse)
  scratch_4x8[0] = coeff.get(0, 0) - coeff.get(0, 1)
  for iy in 0..<4 {
    for ix in 0..<8 {
      if (ix | iy) == 0 {
        continue
      }
      scratch_4x8[iy * 8 + ix] = coeff.get(ix, 2 * iy + 1)
    }
  }
  dct_2d(@grid.SubGrid::from_buf(scratch_4x8, 0, 8, 4, 8), Inverse)
  for iy in 0..<4 {
    let afv_y = if flip_y == 0 { iy } else { 3 - iy }
    for ix in 0..<4 {
      let afv_x = if flip_x == 0 { ix } else { 3 - ix }
      coeff.set(
        flip_x * 4 + ix,
        flip_y * 4 + iy,
        samples_afv[afv_y * 4 + afv_x],
      )
    }
  }
  for iy in 0..<4 {
    let y = flip_y * 4 + iy
    for ix in 0..<4 {
      let x = (1 - flip_x) * 4 + ix
      coeff.set(x, y, scratch_4x4[iy * 4 + ix])
    }
  }
  for iy in 0..<4 {
    let y = (1 - flip_y) * 4 + iy
    FixedArray::blit_to(
      scratch_4x8,
      coeff.buf,
      len=8,
      src_offset=iy * 8,
      dst_offset=coeff.row_offset(y),
    )
  }
}

///|
fn transform_dct(coeff : @grid.SubGrid[Float]) -> Unit {
  dct_2d(coeff, Inverse)
}

///|
/// Inverse transform of a varblock, given its coefficients with the LLF
/// coefficients already in place (`transform`).
pub fn transform(
  coeff : @grid.SubGrid[Float],
  dct_select : TransformType,
) -> Unit {
  match dct_select {
    Dct2 => transform_dct2(coeff)
    Dct4 => transform_dct4(coeff)
    Hornuss => transform_hornuss(coeff)
    Dct4x8 => transform_dct4x8(coeff, false)
    Dct8x4 => transform_dct4x8(coeff, true)
    Afv0 => transform_afv(coeff, 0)
    Afv1 => transform_afv(coeff, 1)
    Afv2 => transform_afv(coeff, 2)
    Afv3 => transform_afv(coeff, 3)
    _ => transform_dct(coeff)
  }
}

///|
/// Computes the LLF coefficients of a varblock from the LF image and runs the
/// inverse transform (the body of `transform_varblocks_inner` for one block).
///
/// `coeff` is the channel's coefficient grid, `lf` the channel's LF grid
/// (one sample per 8x8 block); `shifted_bx`/`shifted_by` are block coordinates
/// in both.
pub fn transform_varblock(
  lf : @grid.SubGrid[Float],
  coeff : @grid.SubGrid[Float],
  shifted_bx : Int32,
  shifted_by : Int32,
  dct_select : TransformType,
) -> Unit {
  let (bw, bh) = dct_select.dct_select_size()
  let left = shifted_bx * 8
  let top = shifted_by * 8
  let logbw = bw.ctz()
  let logbh = bh.ctz()
  let out = coeff.subgrid(left, top, bw, bh)
  match dct_select {
    Hornuss
    | Dct2
    | Dct4
    | Dct8x4
    | Dct4x8
    | Dct8
    | Afv0
    | Afv1
    | Afv2
    | Afv3 => out.set(0, 0, lf.get(shifted_bx, shifted_by))
    _ => {
      for y in 0..<bh {
        for x in 0..<bw {
          out.set(x, y, lf.get(shifted_bx + x, shifted_by + y))
        }
      }
      dct_2d(out, Forward)
      for y in 0..<bh {
        for x in 0..<bw {
          out.set(
            x,
            y,
            out.get(x, y) / (scale_f(y, 5 - logbh) * scale_f(x, 5 - logbw)),
          )
        }
      }
    }
  }
  let block = coeff.subgrid(left, top, bw * 8, bh * 8)
  transform(block, dct_select)
}

///|
/// `transform_varblocks`: LLF computation and inverse transform of every
/// varblock of a group, for each of the three channels.
///
/// `hshifts`/`vshifts` are the channel shifts (`ChannelShift::hshift`/`vshift`)
/// of the X, Y, B channels.
pub fn transform_varblocks(
  lf : FixedArray[@grid.SubGrid[Float]],
  coeff_out : FixedArray[@grid.SubGrid[Float]],
  hshifts : FixedArray[Int32],
  vshifts : FixedArray[Int32],
  block_info : @grid.SubGrid[BlockInfo],
) -> Unit {
  for channel in 0..<3 {
    let coeff = coeff_out[channel]
    let lf = lf[channel]
    let hshift = hshifts[channel]
    let vshift = vshifts[channel]
    let w8 = block_info.width
    let h8 = block_info.height
    for by in 0..<h8 {
      for bx in 0..<w8 {
        guard varblock_at(block_info, bx, by, hshift, vshift)
          is Some((shifted_bx, shifted_by, dct_select, _)) else {
          continue
        }
        transform_varblock(lf, coeff, shifted_bx, shifted_by, dct_select)
      }
    }
  }
}

///|
/// One step of `for_each_varblocks`: returns
/// `(shifted_bx, shifted_by, dct_select, hf_mul)` if a varblock of the shifted
/// channel starts at block `(bx, by)`.
pub fn varblock_at(
  block_info : @grid.SubGrid[BlockInfo],
  bx : Int32,
  by : Int32,
  hshift : Int32,
  vshift : Int32,
) -> (Int32, Int32, TransformType, Int32)? {
  guard block_info.get(bx, by) is Data(dct_select~, hf_mul~) else { None }
  let shifted_bx = bx >> hshift
  let shifted_by = by >> vshift
  if hshift != 0 || vshift != 0 {
    if shifted_bx << hshift != bx || shifted_by << vshift != by {
      return None
    }
    if !(block_info.get(shifted_bx, shifted_by) is Data(_)) {
      return None
    }
  }
  Some((shifted_bx, shifted_by, dct_select, hf_mul))
}

///|
let afv_basis : FixedArray[FixedArray[Float]] = [
  [
    0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
    0.25, 0.25, 0.25,
  ],
  [
    0.876902929799142, 0.2206518106944235, -0.10140050393753763, -0.1014005039375375,
    0.2206518106944236, -0.10140050393753777, -0.10140050393753772, -0.10140050393753763,
    -0.10140050393753758, -0.10140050393753769, -0.1014005039375375, -0.10140050393753768,
    -0.10140050393753768, -0.10140050393753759, -0.10140050393753763, -0.10140050393753741,
  ],
  [
    0.0, 0.0, 0.40670075830260755, 0.44444816619734445, 0.0, 0.0, 0.19574399372042936,
    0.2929100136981264, -0.40670075830260716, -0.19574399372042872, 0.0, 0.11379074460448091,
    -0.44444816619734384, -0.29291001369812636, -0.1137907446044814, 0.0,
  ],
  [
    0.0, 0.0, -0.21255748058288748, 0.3085497062849767, 0.0, 0.4706702258572536,
    -0.1621205195722993, 0.0, -0.21255748058287047, -0.16212051957228327, -0.47067022585725277,
    -0.1464291867126764, 0.3085497062849487, 0.0, -0.14642918671266536, 0.4251149611657548,
  ],
  [
    0.0, -0.7071067811865474, 0.0, 0.0, frac_1_sqrt_2_f32, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
  ],
  [
    -0.4105377591765233, 0.6235485373547691, -0.06435071657946274, -0.06435071657946266,
    0.6235485373547694, -0.06435071657946284, -0.0643507165794628, -0.06435071657946274,
    -0.06435071657946272, -0.06435071657946279, -0.06435071657946266, -0.06435071657946277,
    -0.06435071657946277, -0.06435071657946273, -0.06435071657946274, -0.0643507165794626,
  ],
  [
    0.0, 0.0, -0.4517556589999482, 0.15854503551840063, 0.0, -0.04038515160822202,
    0.0074182263792423875, 0.39351034269210167, -0.45175565899994635, 0.007418226379244351,
    0.1107416575309343, 0.08298163094882051, 0.15854503551839705, 0.3935103426921022,
    0.0829816309488214, -0.45175565899994796,
  ],
  [
    0.0, 0.0, -0.304684750724869, 0.5112616136591823, 0.0, 0.0, -0.290480129728998,
    -0.06578701549142804, 0.304684750724884, 0.2904801297290076, 0.0, -0.23889773523344604,
    -0.5112616136592012, 0.06578701549142545, 0.23889773523345467, 0.0,
  ],
  [
    0.0, 0.0, 0.3017929516615495, 0.25792362796341184, 0.0, 0.16272340142866204,
    0.09520022653475037, 0.0, 0.3017929516615503, 0.09520022653475055, -0.16272340142866173,
    -0.35312385449816297, 0.25792362796341295, 0.0, -0.3531238544981624, -0.6035859033230976,
  ],
  [
    0.0, 0.0, 0.40824829046386274, 0.0, 0.0, 0.0, 0.0, -0.4082482904638628, -0.4082482904638635,
    0.0, 0.0, -0.40824829046386296, 0.0, 0.4082482904638634, 0.408248290463863, 0.0,
  ],
  [
    0.0, 0.0, 0.1747866975480809, 0.0812611176717539, 0.0, 0.0, -0.3675398009862027,
    -0.307882213957909, -0.17478669754808135, 0.3675398009862011, 0.0, 0.4826689115059883,
    -0.08126111767175039, 0.30788221395790305, -0.48266891150598584, 0.0,
  ],
  [
    0.0, 0.0, -0.21105601049335784, 0.18567180916109802, 0.0, 0.0, 0.49215859013738733,
    -0.38525013709251915, 0.21105601049335806, -0.49215859013738905, 0.0, 0.17419412659916217,
    -0.18567180916109904, 0.3852501370925211, -0.1741941265991621, 0.0,
  ],
  [
    0.0, 0.0, -0.14266084808807264, -0.3416446842253372, 0.0, 0.7367497537172237,
    0.24627107722075148, -0.08574019035519306, -0.14266084808807344, 0.24627107722075137,
    0.14883399227113567, -0.04768680350229251, -0.3416446842253373, -0.08574019035519267,
    -0.047686803502292804, -0.14266084808807242,
  ],
  [
    0.0, 0.0, -0.13813540350758585, 0.3302282550303788, 0.0, 0.08755115000587084,
    -0.07946706605909573, -0.4613374887461511, -0.13813540350758294, -0.07946706605910261,
    0.49724647109535086, 0.12538059448563663, 0.3302282550303805, -0.4613374887461554,
    0.12538059448564315, -0.13813540350758452,
  ],
  [
    0.0, 0.0, -0.17437602599651067, 0.0702790691196284, 0.0, -0.2921026642334881,
    0.3623817333531167, 0.0, -0.1743760259965108, 0.36238173335311646, 0.29210266423348785,
    -0.4326608024727445, 0.07027906911962818, 0.0, -0.4326608024727457, 0.34875205199302267,
  ],
  [
    0.0, 0.0, 0.11354987314994337, -0.07417504595810355, 0.0, 0.19402893032594343,
    -0.435190496523228, 0.21918684838857466, 0.11354987314994257, -0.4351904965232251,
    0.5550443808910661, -0.25468277124066463, -0.07417504595810233, 0.2191868483885728,
    -0.25468277124066413, 0.1135498731499429,
  ],
]
