// Port of moxcms 0.9.0 `transform.rs` (`Layout`, `TransformOptions`).

///|
/// Data layout (channel order for RGB).
#derive(Eq, Debug)
pub(all) enum Layout {
  Rgb
  Rgba
  Cmyka
  Gray
  GrayAlpha
  Inks5
  Inks6
  Inks7
  Inks8
  Inks9
  Inks10
  Inks11
  Inks12
  Inks13
  Inks14
  Inks15
}

///|
pub fn Layout::channels(self : Layout) -> Int32 {
  match self {
    Rgb => 3
    Rgba => 4
    Gray => 1
    GrayAlpha => 2
    Cmyka => 5
    Inks5 => 5
    Inks6 => 6
    Inks7 => 7
    Inks8 => 8
    Inks9 => 9
    Inks10 => 10
    Inks11 => 11
    Inks12 => 12
    Inks13 => 13
    Inks14 => 14
    Inks15 => 15
  }
}

///|
pub fn Layout::has_alpha(self : Layout) -> Bool {
  match self {
    Rgba | GrayAlpha => true
    _ => false
  }
}

///|
/// Red channel index (`r_i`); only RGB layouts are valid.
fn Layout::r_i(self : Layout) -> Int32 {
  match self {
    Rgb | Rgba => 0
    _ => abort("not implemented")
  }
}

///|
fn Layout::g_i(self : Layout) -> Int32 {
  match self {
    Rgb | Rgba => 1
    _ => abort("not implemented")
  }
}

///|
fn Layout::b_i(self : Layout) -> Int32 {
  match self {
    Rgb | Rgba => 2
    _ => abort("not implemented")
  }
}

///|
fn Layout::a_i(self : Layout) -> Int32 {
  match self {
    Rgba => 3
    GrayAlpha => 1
    _ => abort("not implemented")
  }
}

///|
/// Interpolation method for 3D LUTs. Only `Linear` exists without the
/// `options` feature (which jxl-oxide does not enable).
#derive(Eq, Debug)
pub(all) enum InterpolationMethod {
  Linear
}

///|
/// Barycentric weight scale. Only `Low` exists without the `options` feature.
#derive(Eq, Debug)
pub(all) enum BarycentricWeightScale {
  Low
}

///|
#derive(Debug)
pub(all) struct TransformOptions {
  rendering_intent : RenderingIntent
  allow_use_cicp_transfer : Bool
  prefer_fixed_point : Bool
  interpolation_method : InterpolationMethod
  barycentric_weight_scale : BarycentricWeightScale
}

///|
pub fn TransformOptions::default() -> TransformOptions {
  {
    rendering_intent: Perceptual,
    allow_use_cicp_transfer: true,
    prefer_fixed_point: true,
    interpolation_method: Linear,
    barycentric_weight_scale: Low,
  }
}
