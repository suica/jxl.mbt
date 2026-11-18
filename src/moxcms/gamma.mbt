// Port of moxcms 0.9.0 `gamma.rs` (the f64 transfer functions behind
// `TransferCharacteristics::linearize`/`gamma` and the f32 table builders;
// the `extended_range` f32 variants are behind a feature jxl-oxide does not
// enable).
//
// `fmla(a, b, c)` and `mlaf(c, a, b)` are `c + a * b`, unfused.

///|
fn srgb_to_linear(gamma : Double) -> Double {
  if gamma < 0.0 {
    0.0
  } else if gamma < 12.92 * 0.0030412825601275209 {
    gamma * (1.0 / 12.92)
  } else if gamma < 1.0 {
    @pxfm.f_pow((gamma + 0.0550107189475866) / 1.0550107189475866, 2.4)
  } else {
    1.0
  }
}

///|
fn srgb_from_linear(linear : Double) -> Double {
  if linear < 0.0 {
    0.0
  } else if linear < 0.0030412825601275209 {
    linear * 12.92
  } else if linear < 1.0 {
    -0.0550107189475866 + 1.0550107189475866 * @pxfm.f_pow(linear, 1.0 / 2.4)
  } else {
    1.0
  }
}

///|
fn rec709_to_linear(gamma : Double) -> Double {
  if gamma < 0.0 {
    0.0
  } else if gamma < 4.5 * 0.018053968510807 {
    gamma * (1.0 / 4.5)
  } else if gamma < 1.0 {
    @pxfm.f_pow((gamma + 0.09929682680944) / 1.09929682680944, 1.0 / 0.45)
  } else {
    1.0
  }
}

///|
fn rec709_from_linear(linear : Double) -> Double {
  if linear < 0.0 {
    0.0
  } else if linear < 0.018053968510807 {
    linear * 4.5
  } else if linear < 1.0 {
    -0.09929682680944 + 1.09929682680944 * @pxfm.f_pow(linear, 0.45)
  } else {
    1.0
  }
}

///|
fn smpte428_to_linear(gamma : Double) -> Double {
  let scale = 1.0 / 0.91655527974030934
  @pxfm.f_pow(dmin(dmax(gamma, 0.0), 1.0), 2.6) * scale
}

///|
fn smpte428_from_linear(linear : Double) -> Double {
  let power_value = 1.0 / 2.6
  @pxfm.f_pow(0.91655527974030934 * dmax(linear, 0.0), power_value)
}

///|
fn smpte240_to_linear(gamma : Double) -> Double {
  if gamma < 0.0 {
    0.0
  } else if gamma < 4.0 * 0.022821585529445 {
    gamma / 4.0
  } else if gamma < 1.0 {
    @pxfm.f_pow((gamma + 0.111572195921731) / 1.111572195921731, 1.0 / 0.45)
  } else {
    1.0
  }
}

///|
fn smpte240_from_linear(linear : Double) -> Double {
  if linear < 0.0 {
    0.0
  } else if linear < 0.022821585529445 {
    linear * 4.0
  } else if linear < 1.0 {
    -0.111572195921731 + 1.111572195921731 * @pxfm.f_pow(linear, 0.45)
  } else {
    1.0
  }
}

///|
fn log100_from_linear(linear : Double) -> Double {
  if linear <= 0.01 {
    0.0
  } else {
    1.0 + @pxfm.f_log10(dmin(linear, 1.0)) / 2.0
  }
}

///|
fn log100_to_linear(gamma : Double) -> Double {
  // The function is non-bijective so choose the middle of [0, 0.00316227766f].
  let mid_interval = 0.01 / 2.0
  if gamma <= 0.0 {
    mid_interval
  } else {
    @pxfm.f_exp10(2.0 * (dmin(gamma, 1.0) - 1.0))
  }
}

///|
fn log100_sqrt10_to_linear(gamma : Double) -> Double {
  let mid_interval = 0.00316227766 / 2.0
  if gamma <= 0.0 {
    mid_interval
  } else {
    @pxfm.f_exp10(2.5 * (dmin(gamma, 1.0) - 1.0))
  }
}

///|
fn log100_sqrt10_from_linear(linear : Double) -> Double {
  if linear <= 0.00316227766 {
    0.0
  } else {
    1.0 + @pxfm.f_log10(dmin(linear, 1.0)) / 2.5
  }
}

///|
fn bt1361_from_linear(linear : Double) -> Double {
  if linear < -0.25 {
    -0.25
  } else if linear < 0.0 {
    0.02482420670236 + -0.27482420670236 * @pxfm.f_pow(-4.0 * linear, 0.45)
  } else if linear < 0.018053968510807 {
    linear * 4.5
  } else if linear < 1.0 {
    -0.09929682680944 + 1.09929682680944 * @pxfm.f_pow(linear, 0.45)
  } else {
    1.0
  }
}

///|
fn bt1361_to_linear(gamma : Double) -> Double {
  if gamma < -0.25 {
    -0.25
  } else if gamma < 0.0 {
    @pxfm.f_pow((gamma - 0.02482420670236) / -0.27482420670236, 1.0 / 0.45) /
    -4.0
  } else if gamma < 4.5 * 0.018053968510807 {
    gamma / 4.5
  } else if gamma < 1.0 {
    @pxfm.f_pow((gamma + 0.09929682680944) / 1.09929682680944, 1.0 / 0.45)
  } else {
    1.0
  }
}

///|
fn pure_gamma_function(x : Double, gamma : Double) -> Double {
  if x <= 0.0 {
    0.0
  } else if x >= 1.0 {
    1.0
  } else {
    @pxfm.f_pow(x, gamma)
  }
}

///|
fn iec61966_to_linear(gamma : Double) -> Double {
  if gamma < -4.5 * 0.018053968510807 {
    @pxfm.f_pow((-gamma + 0.09929682680944) / -1.09929682680944, 1.0 / 0.45)
  } else if gamma < 4.5 * 0.018053968510807 {
    gamma / 4.5
  } else {
    @pxfm.f_pow((gamma + 0.09929682680944) / 1.09929682680944, 1.0 / 0.45)
  }
}

///|
fn iec61966_from_linear(v : Double) -> Double {
  if v < -0.018053968510807 {
    0.09929682680944 + -1.09929682680944 * @pxfm.f_pow(-v, 0.45)
  } else if v < 0.018053968510807 {
    v * 4.5
  } else {
    -0.09929682680944 + 1.09929682680944 * @pxfm.f_pow(v, 0.45)
  }
}

///|
fn gamma2p2_from_linear(linear : Double) -> Double {
  pure_gamma_function(linear, 1.0 / 2.2)
}

///|
fn gamma2p2_to_linear(gamma : Double) -> Double {
  pure_gamma_function(gamma, 2.2)
}

///|
fn gamma2p8_from_linear(linear : Double) -> Double {
  pure_gamma_function(linear, 1.0 / 2.8)
}

///|
fn gamma2p8_to_linear(gamma : Double) -> Double {
  pure_gamma_function(gamma, 2.8)
}

///|
fn pq_to_linear(gamma : Double) -> Double {
  if gamma > 0.0 {
    let pow_gamma = @pxfm.f_pow(gamma, 1.0 / 78.84375)
    let num = dmax(pow_gamma - 0.8359375, 0.0)
    let den = dmax(18.8515625 + -18.6875 * pow_gamma, -1.7976931348623157e308)
    @pxfm.f_pow(num / den, 1.0 / 0.1593017578125)
  } else {
    0.0
  }
}

///|
fn pq_from_linear(linear : Double) -> Double {
  if linear > 0.0 {
    let linear = dclamp(linear, 0.0, 1.0)
    let pow_linear = @pxfm.f_pow(linear, 0.1593017578125)
    let num = -0.1640625 + 0.1640625 * pow_linear
    let den = 1.0 + 18.6875 * pow_linear
    @pxfm.f_pow(1.0 + num / den, 78.84375)
  } else {
    0.0
  }
}

///|
fn hlg_to_linear(gamma : Double) -> Double {
  if gamma < 0.0 {
    return 0.0
  }
  if gamma <= 0.5 {
    @pxfm.f_pow(gamma * gamma * (1.0 / 3.0), 1.2)
  } else {
    @pxfm.f_pow(
      (@pxfm.f_exp((gamma - 0.55991073) / 0.17883277) + 0.28466892) / 12.0,
      1.2,
    )
  }
}

///|
fn hlg_from_linear(linear : Double) -> Double {
  let mut linear = dclamp(linear, 0.0, 1.0)
  linear = @pxfm.f_pow(linear, 1.0 / 1.2)
  if linear < 0.0 {
    0.0
  } else if linear <= 1.0 / 12.0 {
    (3.0 * linear).sqrt()
  } else {
    0.55991073 + 0.17883277 * @pxfm.f_log(-0.28466892 + 12.0 * linear)
  }
}

///|
fn trc_linear(v : Double) -> Double {
  dmax(dmin(v, 1.0), 0.0)
}

///|
pub fn TransferCharacteristics::linearize(
  self : TransferCharacteristics,
  v : Double,
) -> Double {
  match self {
    Reserved => 0.0
    Bt709 | Bt601 | Bt202010bit | Bt202012bit => rec709_to_linear(v)
    Unspecified => 0.0
    Bt470M => gamma2p2_to_linear(v)
    Bt470Bg => gamma2p8_to_linear(v)
    Smpte240 => smpte240_to_linear(v)
    Linear => trc_linear(v)
    Log100 => log100_to_linear(v)
    Log100sqrt10 => log100_sqrt10_to_linear(v)
    Iec61966 => iec61966_to_linear(v)
    Bt1361 => bt1361_to_linear(v)
    Srgb => srgb_to_linear(v)
    Smpte2084 => pq_to_linear(v)
    Smpte428 => smpte428_to_linear(v)
    Hlg => hlg_to_linear(v)
  }
}

///|
pub fn TransferCharacteristics::gamma(
  self : TransferCharacteristics,
  v : Double,
) -> Double {
  match self {
    Reserved => 0.0
    Bt709 | Bt601 | Bt202010bit | Bt202012bit => rec709_from_linear(v)
    Unspecified => 0.0
    Bt470M => gamma2p2_from_linear(v)
    Bt470Bg => gamma2p8_from_linear(v)
    Smpte240 => smpte240_from_linear(v)
    Linear => trc_linear(v)
    Log100 => log100_from_linear(v)
    Log100sqrt10 => log100_sqrt10_from_linear(v)
    Iec61966 => iec61966_from_linear(v)
    Bt1361 => bt1361_from_linear(v)
    Srgb => srgb_from_linear(v)
    Smpte2084 => pq_from_linear(v)
    Smpte428 => smpte428_from_linear(v)
    Hlg => hlg_from_linear(v)
  }
}

///|
/// `TransferCharacteristics::make_linear_table::<f32, N, BIT_DEPTH>`.
fn TransferCharacteristics::make_linear_table(
  self : TransferCharacteristics,
  n : Int32,
) -> FixedArray[Float] {
  let max_value = NOT_FINITE_LINEAR_TABLE_SIZE - 1
  let cap_values = NOT_FINITE_LINEAR_TABLE_SIZE
  guard cap_values <= n else { abort("Invalid lut table construction") }
  let output = FixedArray::make(n, (0.0 : Float))
  let scale_value = 1.0 / max_value.to_double()
  for i in 0..<cap_values {
    output[i] = Float::from_double(self.linearize(i.to_double() * scale_value))
  }
  output
}

///|
/// `TransferCharacteristics::make_gamma_table::<f32, BUCKET, N>`.
fn TransferCharacteristics::make_gamma_table(
  self : TransferCharacteristics,
  bucket : Int32,
  n : Int32,
) -> FixedArray[Float] {
  let max_range = 1.0 / (n - 1).to_double()
  let table = FixedArray::make(bucket, (0.0 : Float))
  for v in 0..<n.min(bucket) {
    table[v] = Float::from_double(self.gamma(v.to_double() * max_range))
  }
  table
}
