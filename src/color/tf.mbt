// Port of jxl-color `tf.rs`: transfer functions.
//
// Sample buffers are `FixedArray[Float]` processed in place; the optional
// `start`/`len` arguments select a sub-range (the whole buffer by default).

///|
/// Applies gamma to samples.
pub fn apply_gamma(
  samples : FixedArray[Float],
  gamma : Float,
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  // x86_64 AVX2 + FMA path: 8-wide chunks, then one 4-wide FMA chunk, then
  // the generic code for the last (< 4) samples.
  let end = start + len
  let simd_end = start + len / 8 * 8 + (if len % 8 >= 4 { 4 } else { 0 })
  for i in start..<simd_end {
    let a = samples[i]
    samples[i] = if a <= 1.0e-7 { 0.0 } else { fast_powf_fma(a, gamma) }
  }
  for i in simd_end..<end {
    let a = samples[i]
    samples[i] = if a <= 1.0e-7 { 0.0 } else { fast_powf_generic(a, gamma) }
  }
}

///|
/// Converts scene luminance values to display luminance values using the hybrid log-gamma
/// transfer function (HLG OOTF).
pub fn hlg_oo(
  samples_r : FixedArray[Float],
  samples_g : FixedArray[Float],
  samples_b : FixedArray[Float],
  luminances : FixedArray[Float],
  intensity_target : Float,
  start~ : Int32 = 0,
  len~ : Int32 = samples_r.length() - start,
) -> Unit {
  let lr = luminances[0]
  let lg = luminances[1]
  let lb = luminances[2]
  let gamma : Float = 1.2 *
    powf_glibc(1.111, log2_f32(intensity_target / 1.0e3))
  // 1/g - 1
  let exp = gamma - 1.0
  for i in start..<(start + len) {
    let r = samples_r[i]
    let g = samples_g[i]
    let b = samples_b[i]
    let mixed = mul_add_f32(r, lr, mul_add_f32(g, lg, b * lb))
    let mult = powf_glibc(mixed, exp)
    samples_r[i] = r * mult
    samples_g[i] = g * mult
    samples_b[i] = b * mult
  }
}

///|
/// Converts the display-referred samples to scene-referred signals using the hybrid log-gamma
/// transfer function (HLG inverse OOTF).
pub fn hlg_inverse_oo(
  samples_r : FixedArray[Float],
  samples_g : FixedArray[Float],
  samples_b : FixedArray[Float],
  luminances : FixedArray[Float],
  intensity_target : Float,
  start~ : Int32 = 0,
  len~ : Int32 = samples_r.length() - start,
) -> Unit {
  // System gamma results to ~1 in this range.
  if intensity_target >= 295.0 && intensity_target <= 305.0 {
    return
  }
  let lr = luminances[0]
  let lg = luminances[1]
  let lb = luminances[2]
  let gamma : Float = 1.2 *
    powf_glibc(1.111, log2_f32(intensity_target / 1.0e3))
  // 1/g - 1
  let exp = ((1.0 : Float) - gamma) / gamma
  for i in start..<(start + len) {
    let r = samples_r[i]
    let g = samples_g[i]
    let b = samples_b[i]
    let mixed = mul_add_f32(r, lr, mul_add_f32(g, lg, b * lb))
    let mult = powf_glibc(mixed, exp)
    samples_r[i] = r * mult
    samples_g[i] = g * mult
    samples_b[i] = b * mult
  }
}

///|
const HLG_A : Float = 0.17883277

///|
const HLG_B : Float = 0.28466892

///|
const HLG_C : Float = 0.5599107

///|
/// Converts the scene-referred linear samples with the hybrid log-gamma transfer function.
pub fn linear_to_hlg(
  samples : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  for i in start..<(start + len) {
    let s = samples[i]
    let a = s.abs()
    let v = if a <= 1.0 / 12.0 {
      ((3.0 : Float) * a).sqrt()
    } else {
      HLG_A * @math.lnf(mul_add_f32(a, 12.0, -HLG_B)) + HLG_C
    }
    samples[i] = copysign_f32(v, s)
  }
}

///|
/// HLG inverse OETF, maps non-linear HLG signal to scene-referred linear sample.
pub fn hlg_to_linear(
  samples : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  for i in start..<(start + len) {
    let s = samples[i]
    let a = s.abs()
    let v = if a <= 0.5 {
      a * a / 3.0
    } else {
      (@math.expf((a - HLG_C) / HLG_A) + HLG_B) / 12.0
    }
    samples[i] = copysign_f32(v, s)
  }
}

///|
/// `(d * 65535.0) as u16`: saturating cast, NaN maps to 0.
fn f64_to_u16_saturating(d : Double) -> Int32 {
  if d.is_nan() || d <= 0.0 {
    0
  } else if d >= 65535.0 {
    65535
  } else {
    d.to_int()
  }
}

///|
/// Lookup table of the HLG inverse OETF with `n` entries, scaled to `0..=65535`
/// (used for ICC profile synthesis).
pub fn hlg_table(n : Int32) -> Array[Int32] {
  let a = 0.17883277
  let b = 0.28466892
  let c = 0.5599107
  let out = Array::make(n, 0)
  let half = (n - 1) / 2
  for idx in 0..<=half {
    // usize arithmetic in upstream: compute in 64 bits
    let d = (idx.to_int64() * idx.to_int64()).to_double() /
      (3L * (n - 1).to_int64() * (n - 1).to_int64()).to_double()
    out[idx] = f64_to_u16_saturating(d * 65535.0) // clamped
  }
  for idx in (half + 1)..<n {
    let e = idx.to_double() / (n - 1).to_double()
    let d = (@math.exp((e - c) / a) + b) / 12.0
    out[idx] = f64_to_u16_saturating(d * 65535.0) // clamped
  }
  out
}
