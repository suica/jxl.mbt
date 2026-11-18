// 16-bit interpolation routines, ported from Little CMS 2.19 (as vendored by lcms2-sys 4.0.7) `cmsintrp.c`.
// Only the 16-bit (`CMS_LERP_FLAGS_16BITS`) interpolators are needed: every
// CLUT and tabulated curve read from an ICC profile is 16-bit, and lcms2's
// float pipeline evaluates them by quantizing to 16 bits.

///|
/// `cmsInterpParams`
priv struct InterpParams {
  n_inputs : Int32
  n_outputs : Int32
  domain : FixedArray[Int32]
  opta : FixedArray[Int32]
  mut trilinear : Bool
}

///|
/// `_cmsComputeInterpParamsEx` (16-bit tables).
fn InterpParams::new(
  n_samples : FixedArray[Int32],
  n_inputs : Int32,
  n_outputs : Int32,
) -> InterpParams raise @bitstream.JxlError {
  if n_inputs > MAX_INPUT_DIMENSIONS {
    raise cms_error("Too many input channels")
  }
  if n_inputs >= 4 && n_outputs >= MAX_STAGE_CHANNELS {
    raise cms_error("Unsupported interpolation")
  }
  let domain = FixedArray::make(MAX_INPUT_DIMENSIONS, 0)
  let opta = FixedArray::make(MAX_INPUT_DIMENSIONS, 0)
  for i in 0..<n_inputs {
    domain[i] = n_samples[i] - 1
  }
  opta[0] = n_outputs
  for i in 1..<n_inputs {
    opta[i] = opta[i - 1] * n_samples[n_inputs - i]
  }
  { n_inputs, n_outputs, domain, opta, trilinear: false, }
}

///|
/// Scratch buffers for the recursive N-input interpolators.
priv struct InterpScratch {
  tmp : FixedArray[FixedArray[Int32]]
}

///|
fn InterpScratch::new() -> InterpScratch {
  let tmp = FixedArray::make(2 * MAX_INPUT_DIMENSIONS, FixedArray::make(0, 0))
  for i in 0..<(2 * MAX_INPUT_DIMENSIONS) {
    tmp[i] = FixedArray::make(MAX_STAGE_CHANNELS, 0)
  }
  { tmp, }
}

///|
/// Evaluates the interpolation selected by `DefaultInterpolatorsFactory`.
fn InterpParams::eval16(
  self : InterpParams,
  table : FixedArray[Int32],
  input : FixedArray[Int32],
  output : FixedArray[Int32],
  scratch : InterpScratch,
) -> Unit {
  match self.n_inputs {
    1 =>
      if self.n_outputs == 1 {
        lin_lerp_1d(self, table, input[0], output)
      } else {
        eval_1_input(self, table, input, output)
      }
    2 => bilinear_interp16(self, table, input, output)
    3 =>
      if self.trilinear {
        trilinear_interp16(self, table, input, output)
      } else {
        tetrahedral_interp16(self, table, input, output)
      }
    4 => eval_4_inputs(self, table, 0, input, 0, output, scratch, 0)
    n => eval_n_inputs(n, self, table, 0, input, 0, output, scratch, 0)
  }
}

///|
/// `LinLerp1D`
fn lin_lerp_1d(
  p : InterpParams,
  table : FixedArray[Int32],
  value : Int32,
  output : FixedArray[Int32],
) -> Unit {
  if value == 0xffff || p.domain[0] == 0 {
    output[0] = table[p.domain[0]]
  } else {
    let val3 = to_fixed_domain(p.domain[0] * value)
    let cell0 = val3 >> 16
    let rest = val3 & 0xFFFF
    let y0 = table[cell0]
    let y1 = table[cell0 + 1]
    output[0] = linear_interp(rest, y0, y1)
  }
}

///|
/// `Eval1Input`
fn eval_1_input(
  p : InterpParams,
  table : FixedArray[Int32],
  input : FixedArray[Int32],
  output : FixedArray[Int32],
) -> Unit {
  if input[0] == 0xffff || p.domain[0] == 0 {
    let y0 = p.domain[0] * p.opta[0]
    for o in 0..<p.n_outputs {
      output[o] = table[y0 + o]
    }
  } else {
    let v = input[0] * p.domain[0]
    let fk = to_fixed_domain(v)
    let k0 = fk >> 16
    let rk = fk & 0xFFFF
    let k1 = k0 + (if input[0] != 0xFFFF { 1 } else { 0 })
    let kk0 = p.opta[0] * k0
    let kk1 = p.opta[0] * k1
    for o in 0..<p.n_outputs {
      output[o] = linear_interp(rk, table[kk0 + o], table[kk1 + o])
    }
  }
}

///|
/// `LERP` macro of the bilinear/trilinear interpolators.
fn lerp16(a : Int32, l : Int32, h : Int32) -> Int32 {
  (l + round_fixed_to_int((h - l) * a)) & 0xFFFF
}

///|
/// `BilinearInterp16`
fn bilinear_interp16(
  p : InterpParams,
  table : FixedArray[Int32],
  input : FixedArray[Int32],
  output : FixedArray[Int32],
) -> Unit {
  let fx = to_fixed_domain(input[0] * p.domain[0])
  let x0 = fx >> 16
  let rx = fx & 0xFFFF
  let fy = to_fixed_domain(input[1] * p.domain[1])
  let y0 = fy >> 16
  let ry = fy & 0xFFFF
  let xx0 = p.opta[1] * x0
  let xx1 = xx0 + (if input[0] == 0xFFFF { 0 } else { p.opta[1] })
  let yy0 = p.opta[0] * y0
  let yy1 = yy0 + (if input[1] == 0xFFFF { 0 } else { p.opta[0] })
  for o in 0..<p.n_outputs {
    let d00 = table[xx0 + yy0 + o]
    let d01 = table[xx0 + yy1 + o]
    let d10 = table[xx1 + yy0 + o]
    let d11 = table[xx1 + yy1 + o]
    let dx0 = lerp16(rx, d00, d10)
    let dx1 = lerp16(rx, d01, d11)
    output[o] = lerp16(ry, dx0, dx1)
  }
}

///|
/// `TrilinearInterp16`
fn trilinear_interp16(
  p : InterpParams,
  table : FixedArray[Int32],
  input : FixedArray[Int32],
  output : FixedArray[Int32],
) -> Unit {
  let fx = to_fixed_domain(input[0] * p.domain[0])
  let x0 = fx >> 16
  let rx = fx & 0xFFFF
  let fy = to_fixed_domain(input[1] * p.domain[1])
  let y0 = fy >> 16
  let ry = fy & 0xFFFF
  let fz = to_fixed_domain(input[2] * p.domain[2])
  let z0 = fz >> 16
  let rz = fz & 0xFFFF
  let xx0 = p.opta[2] * x0
  let xx1 = xx0 + (if input[0] == 0xFFFF { 0 } else { p.opta[2] })
  let yy0 = p.opta[1] * y0
  let yy1 = yy0 + (if input[1] == 0xFFFF { 0 } else { p.opta[1] })
  let zz0 = p.opta[0] * z0
  let zz1 = zz0 + (if input[2] == 0xFFFF { 0 } else { p.opta[0] })
  for o in 0..<p.n_outputs {
    let d000 = table[xx0 + yy0 + zz0 + o]
    let d001 = table[xx0 + yy0 + zz1 + o]
    let d010 = table[xx0 + yy1 + zz0 + o]
    let d011 = table[xx0 + yy1 + zz1 + o]
    let d100 = table[xx1 + yy0 + zz0 + o]
    let d101 = table[xx1 + yy0 + zz1 + o]
    let d110 = table[xx1 + yy1 + zz0 + o]
    let d111 = table[xx1 + yy1 + zz1 + o]
    let dx00 = lerp16(rx, d000, d100)
    let dx01 = lerp16(rx, d001, d101)
    let dx10 = lerp16(rx, d010, d110)
    let dx11 = lerp16(rx, d011, d111)
    let dxy0 = lerp16(ry, dx00, dx10)
    let dxy1 = lerp16(ry, dx01, dx11)
    output[o] = lerp16(rz, dxy0, dxy1)
  }
}

///|
/// `TetrahedralInterp16` (Sakamoto algorithm).
fn tetrahedral_interp16(
  p : InterpParams,
  table : FixedArray[Int32],
  input : FixedArray[Int32],
  output : FixedArray[Int32],
) -> Unit {
  let fx = to_fixed_domain(input[0] * p.domain[0])
  let fy = to_fixed_domain(input[1] * p.domain[1])
  let fz = to_fixed_domain(input[2] * p.domain[2])
  let x0 = fx >> 16
  let y0 = fy >> 16
  let z0 = fz >> 16
  let rx = fx & 0xFFFF
  let ry = fy & 0xFFFF
  let rz = fz & 0xFFFF
  let xx0 = p.opta[2] * x0
  let mut xx1 = if input[0] == 0xFFFF { 0 } else { p.opta[2] }
  let yy0 = p.opta[1] * y0
  let mut yy1 = if input[1] == 0xFFFF { 0 } else { p.opta[1] }
  let zz0 = p.opta[0] * z0
  let mut zz1 = if input[2] == 0xFFFF { 0 } else { p.opta[0] }
  let base = xx0 + yy0 + zz0
  // Selects the tetrahedron, then the differences c1..c3 per output channel.
  let case_ = if rx >= ry {
    if ry >= rz {
      yy1 += xx1
      zz1 += yy1
      0
    } else if rz >= rx {
      xx1 += zz1
      yy1 += xx1
      1
    } else {
      zz1 += xx1
      yy1 += zz1
      2
    }
  } else if rx >= rz {
    xx1 += yy1
    zz1 += xx1
    3
  } else if ry >= rz {
    zz1 += yy1
    xx1 += zz1
    4
  } else {
    yy1 += zz1
    xx1 += yy1
    5
  }
  for o in 0..<p.n_outputs {
    let t = base + o
    let mut c1 = table[t + xx1]
    let mut c2 = table[t + yy1]
    let mut c3 = table[t + zz1]
    let c0 = table[t]
    match case_ {
      0 => {
        c3 -= c2
        c2 -= c1
        c1 -= c0
      }
      1 => {
        c2 -= c1
        c1 -= c3
        c3 -= c0
      }
      2 => {
        c2 -= c3
        c3 -= c1
        c1 -= c0
      }
      3 => {
        c3 -= c1
        c1 -= c2
        c2 -= c0
      }
      4 => {
        c1 -= c3
        c3 -= c2
        c2 -= c0
      }
      _ => {
        c1 -= c2
        c2 -= c3
        c3 -= c0
      }
    }
    let rest = c1 * rx + c2 * ry + c3 * rz + 0x8001
    output[o] = (c0 + ((rest + (rest >> 16)) >> 16)) & 0xFFFF
  }
}

///|
/// One 3D tetrahedral pass of `Eval4Inputs` over the table at `t0`.
fn eval4_tetra_pass(
  p : InterpParams,
  table : FixedArray[Int32],
  t0 : Int32,
  xx0 : Int32,
  xx1 : Int32,
  yy0 : Int32,
  yy1 : Int32,
  zz0 : Int32,
  zz1 : Int32,
  rx : Int32,
  ry : Int32,
  rz : Int32,
  out : FixedArray[Int32],
) -> Unit {
  for o in 0..<p.n_outputs {
    let t = t0 + o
    let c0 = table[t + xx0 + yy0 + zz0]
    let mut c1 = 0
    let mut c2 = 0
    let mut c3 = 0
    if rx >= ry && ry >= rz {
      c1 = table[t + xx1 + yy0 + zz0] - c0
      c2 = table[t + xx1 + yy1 + zz0] - table[t + xx1 + yy0 + zz0]
      c3 = table[t + xx1 + yy1 + zz1] - table[t + xx1 + yy1 + zz0]
    } else if rx >= rz && rz >= ry {
      c1 = table[t + xx1 + yy0 + zz0] - c0
      c2 = table[t + xx1 + yy1 + zz1] - table[t + xx1 + yy0 + zz1]
      c3 = table[t + xx1 + yy0 + zz1] - table[t + xx1 + yy0 + zz0]
    } else if rz >= rx && rx >= ry {
      c1 = table[t + xx1 + yy0 + zz1] - table[t + xx0 + yy0 + zz1]
      c2 = table[t + xx1 + yy1 + zz1] - table[t + xx1 + yy0 + zz1]
      c3 = table[t + xx0 + yy0 + zz1] - c0
    } else if ry >= rx && rx >= rz {
      c1 = table[t + xx1 + yy1 + zz0] - table[t + xx0 + yy1 + zz0]
      c2 = table[t + xx0 + yy1 + zz0] - c0
      c3 = table[t + xx1 + yy1 + zz1] - table[t + xx1 + yy1 + zz0]
    } else if ry >= rz && rz >= rx {
      c1 = table[t + xx1 + yy1 + zz1] - table[t + xx0 + yy1 + zz1]
      c2 = table[t + xx0 + yy1 + zz0] - c0
      c3 = table[t + xx0 + yy1 + zz1] - table[t + xx0 + yy1 + zz0]
    } else if rz >= ry && ry >= rx {
      c1 = table[t + xx1 + yy1 + zz1] - table[t + xx0 + yy1 + zz1]
      c2 = table[t + xx0 + yy1 + zz1] - table[t + xx0 + yy0 + zz1]
      c3 = table[t + xx0 + yy0 + zz1] - c0
    }
    let rest = c1 * rx + c2 * ry + c3 * rz + 0x8001
    out[o] = (c0 + ((rest + (rest >> 16)) >> 16)) & 0xFFFF
  }
}

///|
/// `Eval4Inputs`: two tetrahedral interpolations in CMY, then linear in K.
/// `d` is the offset of this sub-hypercube's first input/domain entry and
/// `t0` the offset of its table, as in lcms2's recursive `EvalNInputs`.
fn eval_4_inputs(
  p : InterpParams,
  table : FixedArray[Int32],
  t0 : Int32,
  input : FixedArray[Int32],
  d : Int32,
  output : FixedArray[Int32],
  scratch : InterpScratch,
  level : Int32,
) -> Unit {
  let fk = to_fixed_domain(input[d] * p.domain[d])
  let fx = to_fixed_domain(input[d + 1] * p.domain[d + 1])
  let fy = to_fixed_domain(input[d + 2] * p.domain[d + 2])
  let fz = to_fixed_domain(input[d + 3] * p.domain[d + 3])
  let k0 = fk >> 16
  let x0 = fx >> 16
  let y0 = fy >> 16
  let z0 = fz >> 16
  let rk = fk & 0xFFFF
  let rx = fx & 0xFFFF
  let ry = fy & 0xFFFF
  let rz = fz & 0xFFFF
  let kk0 = p.opta[3] * k0
  let kk1 = kk0 + (if input[d] == 0xFFFF { 0 } else { p.opta[3] })
  let xx0 = p.opta[2] * x0
  let xx1 = xx0 + (if input[d + 1] == 0xFFFF { 0 } else { p.opta[2] })
  let yy0 = p.opta[1] * y0
  let yy1 = yy0 + (if input[d + 2] == 0xFFFF { 0 } else { p.opta[1] })
  let zz0 = p.opta[0] * z0
  let zz1 = zz0 + (if input[d + 3] == 0xFFFF { 0 } else { p.opta[0] })
  let tmp1 = scratch.tmp[2 * level]
  let tmp2 = scratch.tmp[2 * level + 1]
  eval4_tetra_pass(
    p,
    table,
    t0 + kk0,
    xx0,
    xx1,
    yy0,
    yy1,
    zz0,
    zz1,
    rx,
    ry,
    rz,
    tmp1,
  )
  eval4_tetra_pass(
    p,
    table,
    t0 + kk1,
    xx0,
    xx1,
    yy0,
    yy1,
    zz0,
    zz1,
    rx,
    ry,
    rz,
    tmp2,
  )
  for i in 0..<p.n_outputs {
    output[i] = linear_interp(rk, tmp1[i], tmp2[i])
  }
}

///|
/// `Eval5Inputs` .. `Eval15Inputs` (the `EVAL_FNS` macro).
fn eval_n_inputs(
  n : Int32,
  p : InterpParams,
  table : FixedArray[Int32],
  t0 : Int32,
  input : FixedArray[Int32],
  d : Int32,
  output : FixedArray[Int32],
  scratch : InterpScratch,
  level : Int32,
) -> Unit {
  if n == 4 {
    eval_4_inputs(p, table, t0, input, d, output, scratch, level)
    return
  }
  let fk = to_fixed_domain(input[d] * p.domain[d])
  let k0 = fk >> 16
  let rk = fk & 0xFFFF
  let nm = n - 1
  let kk0 = p.opta[nm] * k0
  let kk1 = p.opta[nm] * (k0 + (if input[d] != 0xFFFF { 1 } else { 0 }))
  let tmp1 = scratch.tmp[2 * level]
  let tmp2 = scratch.tmp[2 * level + 1]
  eval_n_inputs(nm, p, table, t0 + kk0, input, d + 1, tmp1, scratch, level + 1)
  eval_n_inputs(nm, p, table, t0 + kk1, input, d + 1, tmp2, scratch, level + 1)
  for i in 0..<p.n_outputs {
    output[i] = linear_interp(rk, tmp1[i], tmp2[i])
  }
}
