///|
/// Gabor-like filter parameters.
#derive(Debug)
pub(all) enum Gabor {
  Disabled
  /// Weights `[[w1, w2]; 3]` (per channel X, Y, B).
  Enabled(FixedArray[FixedArray[Float]])
}

///|
pub fn Gabor::default() -> Gabor {
  Enabled(FixedArray::makei(3, _ => [0.115169525, 0.061248592]))
}

///|
pub fn Gabor::parse(
  bs : @bitstream.Bitstream,
) -> Gabor raise @bitstream.JxlError {
  let gab_enabled = bs.read_bool()
  if !gab_enabled {
    return Disabled
  }
  let custom = bs.read_bool()
  if !custom {
    return Gabor::default()
  }
  let weights : FixedArray[FixedArray[Float]] = FixedArray::makei(3, _ => {
    FixedArray::make(2, (0.0 : Float))
  })
  for chan_weight in weights {
    for i in 0..<2 {
      chan_weight[i] = bs.read_f16_as_f32()
    }
    let w0 : Float = chan_weight[0]
    let w1 : Float = chan_weight[1]
    if ((1.0 : Float) + (w0 + w1) * 4.0).abs() < f32_epsilon {
      raise ValidationFailed(
        "Gaborish weights lead to near 0 unnormalized kernel",
      )
    }
  }
  Enabled(weights)
}

///|
pub fn Gabor::enabled(self : Gabor) -> Bool {
  self is Enabled(_)
}

///|
let f32_epsilon : Float = 1.1920929e-7

///|
#derive(Debug)
pub(all) enum EdgePreservingFilter {
  Disabled
  Enabled(EpfParams)
}

///|
#derive(Debug)
pub(all) struct EpfParams {
  iters : Int32
  sharp_lut : FixedArray[Float]
  channel_scale : FixedArray[Float]
  sigma : EpfSigma
  sigma_for_modular : Float
}

///|
pub fn EdgePreservingFilter::enabled(self : EdgePreservingFilter) -> Bool {
  self is Enabled(_)
}

///|
pub fn EdgePreservingFilter::default() -> EdgePreservingFilter {
  Enabled(EpfParams::default())
}

///|
fn epf_sharp_lut_default() -> FixedArray[Float] {
  [
    0.0,
    (1.0 : Float) / 7.0,
    (2.0 : Float) / 7.0,
    (3.0 : Float) / 7.0,
    (4.0 : Float) / 7.0,
    (5.0 : Float) / 7.0,
    (6.0 : Float) / 7.0,
    1.0,
  ]
}

///|
fn epf_channel_scale_default() -> FixedArray[Float] {
  [40.0, 5.0, 3.5]
}

///|
pub fn EpfParams::default() -> EpfParams {
  {
    iters: 2,
    sharp_lut: epf_sharp_lut_default(),
    channel_scale: epf_channel_scale_default(),
    sigma: EpfSigma::default(),
    sigma_for_modular: 1.0,
  }
}

///|
pub fn EdgePreservingFilter::parse(
  bs : @bitstream.Bitstream,
  encoding : Encoding,
) -> EdgePreservingFilter raise @bitstream.JxlError {
  let iters = bs.read_bits(2).reinterpret_as_int()
  if iters == 0 {
    return Disabled
  }
  let sharp_custom = if encoding == VarDct { bs.read_bool() } else { false }
  let sharp_lut = if sharp_custom {
    let ret = FixedArray::make(8, (0.0 : Float))
    for i in 0..<8 {
      ret[i] = bs.read_f16_as_f32()
    }
    ret
  } else {
    epf_sharp_lut_default()
  }
  let weight_custom = bs.read_bool()
  let channel_scale = if weight_custom {
    let ret = FixedArray::make(3, (0.0 : Float))
    for i in 0..<3 {
      ret[i] = bs.read_f16_as_f32()
    }
    bs.read_bits(32) |> ignore // ignored
    ret
  } else {
    epf_channel_scale_default()
  }
  let sigma_custom = bs.read_bool()
  let sigma = if sigma_custom {
    EpfSigma::parse(bs, encoding)
  } else {
    EpfSigma::default()
  }
  let sigma_for_modular : Float = if encoding == Modular {
    bs.read_f16_as_f32()
  } else {
    1.0
  }
  Enabled({ iters, sharp_lut, channel_scale, sigma, sigma_for_modular, })
}

///|
#derive(Debug)
pub(all) struct EpfSigma {
  quant_mul : Float
  pass0_sigma_scale : Float
  pass2_sigma_scale : Float
  border_sad_mul : Float
}

///|
pub fn EpfSigma::default() -> EpfSigma {
  {
    quant_mul: 0.46,
    pass0_sigma_scale: 0.9,
    pass2_sigma_scale: 6.5,
    border_sad_mul: (2.0 : Float) / 3.0,
  }
}

///|
pub fn EpfSigma::parse(
  bs : @bitstream.Bitstream,
  encoding : Encoding,
) -> EpfSigma raise @bitstream.JxlError {
  let quant_mul : Float = if encoding == VarDct {
    bs.read_f16_as_f32()
  } else {
    0.46
  }
  let pass0_sigma_scale = bs.read_f16_as_f32()
  let pass2_sigma_scale = bs.read_f16_as_f32()
  let border_sad_mul = bs.read_f16_as_f32()
  { quant_mul, pass0_sigma_scale, pass2_sigma_scale, border_sad_mul, }
}
