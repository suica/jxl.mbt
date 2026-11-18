// Profile linking with ICC intents, ported from Little CMS 2.19 (as vendored by lcms2-sys 4.0.7)
// `cmscnvrt.c` (`DefaultICCintents`, `ComputeConversion`, `AddConversion`,
// `_cmsLinkProfiles`) and the built-in Lab profiles of `cmsvirt.c` used by
// black point detection.

///|
/// A profile taking part in a link: a parsed ICC profile or one of the
/// built-in Lab identity profiles (`cmsCreateLab2Profile`,
/// `cmsCreateLab4Profile`).
priv enum LinkProfile {
  Icc(Profile)
  Lab2
  Lab4
}

///|
fn LinkProfile::device_class(self : LinkProfile) -> UInt32 {
  match self {
    Icc(p) => p.device_class
    Lab2 | Lab4 => SIG_ABSTRACT_CLASS
  }
}

///|
fn LinkProfile::color_space(self : LinkProfile) -> UInt32 {
  match self {
    Icc(p) => p.color_space
    Lab2 | Lab4 => SIG_LAB_DATA
  }
}

///|
fn LinkProfile::pcs(self : LinkProfile) -> UInt32 {
  match self {
    Icc(p) => p.pcs
    Lab2 | Lab4 => SIG_LAB_DATA
  }
}

///|
fn LinkProfile::version(self : LinkProfile) -> UInt32 {
  match self {
    Icc(p) => p.version
    Lab2 => 0x02100000
    Lab4 => 0x04400000
  }
}

///|
fn LinkProfile::read_media_white_point(
  self : LinkProfile,
) -> (Double, Double, Double) raise @bitstream.JxlError {
  match self {
    Icc(p) => p.read_media_white_point()
    // Built from cmsCreateRGBProfile with a D50 white point.
    Lab2 | Lab4 => (D50_X, D50_Y, D50_Z)
  }
}

///|
/// `_cmsReadDevicelinkLUT`
fn LinkProfile::read_devicelink_lut(
  self : LinkProfile,
  intent : Int32,
) -> Pipeline raise @bitstream.JxlError {
  match self {
    Lab2 => {
      // In-memory A2B0 = identity CLUT, written as lut16 (v2): PCS Lab makes
      // it trilinear and adds the V2/V4 Lab conversions on both sides.
      let lut = Pipeline::new(3, 3)
      lut.push(stage_identity_clut(3))
      change_interpolation_to_trilinear(lut)
      lut.insert_begin(stage_lab_v4_to_v2())
      lut.push(stage_lab_v2_to_v4())
      lut
    }
    Lab4 => {
      // In-memory A2B0 = identity curves, written as lutAtoB (v4).
      let lut = Pipeline::new(3, 3)
      let c = ToneCurve::parametric(1, [1.0])
      lut.push(stage_curves([c, c, c]))
      lut
    }
    Icc(p) => {
      if intent > INTENT_ABSOLUTE_COLORIMETRIC {
        raise cms_error("CmsFailure: invalid intent")
      }
      if p.device_class == SIG_NAMED_COLOR_CLASS {
        raise @bitstream.JxlError::NotSupported(
          "UnsupportedIccProfile: named color profiles",
        )
      }
      if p.is_tag(float_tag_sig(SIG_D2B0, intent)) ||
        p.is_tag(float_tag_sig(SIG_D2B0, 0)) {
        raise @bitstream.JxlError::NotSupported(
          "UnsupportedIccProfile: DToBx floating point tags",
        )
      }
      let mut tag16 = device2pcs16(intent)
      if !p.is_tag(tag16) {
        tag16 = device2pcs16(0)
      }
      guard p.read_lut_tag(tag16, true) is Some((lut, original_type)) else {
        raise cms_error("CmsFailure: no devicelink LUT")
      }
      if p.pcs == SIG_LAB_DATA {
        change_interpolation_to_trilinear(lut)
      }
      if original_type != SIG_LUT16_TYPE {
        return lut
      }
      if p.color_space == SIG_LAB_DATA {
        lut.insert_begin(stage_lab_v4_to_v2())
      }
      if p.pcs == SIG_LAB_DATA {
        lut.push(stage_lab_v2_to_v4())
      }
      lut
    }
  }
}

///|
fn LinkProfile::read_input_lut(
  self : LinkProfile,
  intent : Int32,
) -> Pipeline raise @bitstream.JxlError {
  match self {
    Icc(p) => p.read_input_lut(intent)
    _ => self.read_devicelink_lut(intent)
  }
}

///|
fn LinkProfile::read_output_lut(
  self : LinkProfile,
  intent : Int32,
) -> Pipeline raise @bitstream.JxlError {
  match self {
    Icc(p) => p.read_output_lut(intent)
    _ => raise cms_error("CmsFailure: built-in profile used as output")
  }
}

///|
/// `ComputeBlackPointCompensation`
fn compute_black_point_compensation(
  bp_in : (Double, Double, Double),
  bp_out : (Double, Double, Double),
) -> (FixedArray[Double], FixedArray[Double]) {
  // Now we need to compute a matrix plus an offset m and of such of
  // [m]*bpin + off = bpout
  // [m]*D50  + off = D50
  let tx = bp_in.0 - D50_X
  let ty = bp_in.1 - D50_Y
  let tz = bp_in.2 - D50_Z
  let ax = (bp_out.0 - D50_X) / tx
  let ay = (bp_out.1 - D50_Y) / ty
  let az = (bp_out.2 - D50_Z) / tz
  let bx = -D50_X * (bp_out.0 - bp_in.0) / tx
  let by = -D50_Y * (bp_out.1 - bp_in.1) / ty
  let bz = -D50_Z * (bp_out.2 - bp_in.2) / tz
  ([ax, 0.0, 0.0, 0.0, ay, 0.0, 0.0, 0.0, az], [bx, by, bz])
}

///|
/// `IsEmptyLayer`
fn is_empty_layer(m : FixedArray[Double], off : FixedArray[Double]) -> Bool {
  let id = mat3_identity()
  let mut diff = 0.0
  for i in 0..<9 {
    diff += (m[i] - id[i]).abs()
  }
  for i in 0..<3 {
    diff += off[i].abs()
  }
  diff < 0.002
}

///|
/// `ComputeConversion`. The adaptation state is always 1.0 (lcms2's default,
/// observer fully adapted), so absolute colorimetric is a plain white point
/// scaling and the CHAD tags are not needed.
fn compute_conversion(
  i : Int32,
  profiles : Array[LinkProfile],
  intent : Int32,
  bpc : Bool,
) -> (FixedArray[Double], FixedArray[Double]) raise @bitstream.JxlError {
  let mut m = mat3_identity()
  let mut off : FixedArray[Double] = [0.0, 0.0, 0.0]
  if intent == INTENT_ABSOLUTE_COLORIMETRIC {
    let wp_in = profiles[i - 1].read_media_white_point()
    let wp_out = profiles[i].read_media_white_point()
    // ComputeAbsoluteIntent with AdaptationState == 1.0
    m = [
      wp_in.0 / wp_out.0,
      0.0,
      0.0,
      0.0,
      wp_in.1 / wp_out.1,
      0.0,
      0.0,
      0.0,
      wp_in.2 / wp_out.2,
    ]
  } else if bpc {
    let bp_in = detect_black_point(profiles[i - 1], intent)
    let bp_out = detect_destination_black_point(profiles[i], intent)
    // If black points are equal, then do nothing
    if bp_in.0 != bp_out.0 || bp_in.1 != bp_out.1 || bp_in.2 != bp_out.2 {
      let (mm, oo) = compute_black_point_compensation(bp_in, bp_out)
      m = mm
      off = oo
    }
  }
  // Offset should be adjusted because the encoding. We encode XYZ normalized
  // to 0..1.0, to do that, we divide by MAX_ENCODEABLE_XZY.
  for k in 0..<3 {
    off[k] /= max_encodeable_xyz
  }
  (m, off)
}

///|
/// `AddConversion`: handles PCS mismatches.
fn add_conversion(
  result : Pipeline,
  in_pcs : UInt32,
  out_pcs : UInt32,
  m : FixedArray[Double],
  off : FixedArray[Double],
) -> Unit raise @bitstream.JxlError {
  if in_pcs == SIG_XYZ_DATA {
    if out_pcs == SIG_XYZ_DATA {
      if !is_empty_layer(m, off) {
        result.push(stage_matrix(3, 3, m, Some(off)))
      }
    } else if out_pcs == SIG_LAB_DATA {
      if !is_empty_layer(m, off) {
        result.push(stage_matrix(3, 3, m, Some(off)))
      }
      result.push(stage_xyz2lab())
    } else {
      raise cms_error("CmsFailure: colorspace mismatch")
    }
  } else if in_pcs == SIG_LAB_DATA {
    if out_pcs == SIG_XYZ_DATA {
      result.push(stage_lab2xyz())
      if !is_empty_layer(m, off) {
        result.push(stage_matrix(3, 3, m, Some(off)))
      }
    } else if out_pcs == SIG_LAB_DATA {
      if !is_empty_layer(m, off) {
        result.push(stage_lab2xyz())
        result.push(stage_matrix(3, 3, m, Some(off)))
        result.push(stage_xyz2lab())
      }
    } else {
      raise cms_error("CmsFailure: colorspace mismatch")
    }
  } else if in_pcs != out_pcs {
    raise cms_error("CmsFailure: colorspace mismatch")
  }
}

///|
/// `ColorSpaceIsCompatible`
fn color_space_is_compatible(a : UInt32, b : UInt32) -> Bool {
  if a == b {
    return true
  }
  if a == SIG_4COLOR_DATA && b == SIG_CMYK_DATA {
    return true
  }
  if a == SIG_CMYK_DATA && b == SIG_4COLOR_DATA {
    return true
  }
  if a == SIG_XYZ_DATA && b == SIG_LAB_DATA {
    return true
  }
  if a == SIG_LAB_DATA && b == SIG_XYZ_DATA {
    return true
  }
  false
}

///|
/// `DefaultICCintents`
fn default_icc_intents(
  profiles : Array[LinkProfile],
  intents : Array[Int32],
  bpc : Array[Bool],
) -> Pipeline raise @bitstream.JxlError {
  let n = profiles.length()
  if n == 0 {
    raise cms_error("CmsFailure: no profiles")
  }
  let result = Pipeline::new(0, 0)
  let mut current = profiles[0].color_space()
  for i in 0..<n {
    let p = profiles[i]
    let class_sig = p.device_class()
    let is_device_link = class_sig == SIG_LINK_CLASS ||
      class_sig == SIG_ABSTRACT_CLASS
    // First profile is used as input unless devicelink or abstract
    let is_input = if i == 0 && !is_device_link {
      true
    } else {
      current != SIG_XYZ_DATA && current != SIG_LAB_DATA
    }
    let intent = intents[i]
    let (cs_in, cs_out) = if is_input || is_device_link {
      (p.color_space(), p.pcs())
    } else {
      (p.pcs(), p.color_space())
    }
    if !color_space_is_compatible(cs_in, current) {
      raise cms_error("CmsFailure: ColorSpace mismatch")
    }
    let lut = if is_device_link ||
      (class_sig == SIG_NAMED_COLOR_CLASS && n == 1) {
      let lut = p.read_devicelink_lut(intent)
      let (m, off) = if class_sig == SIG_ABSTRACT_CLASS && i > 0 {
        compute_conversion(i, profiles, intent, bpc[i])
      } else {
        (mat3_identity(), [0.0, 0.0, 0.0])
      }
      add_conversion(result, current, cs_in, m, off)
      lut
    } else if is_input {
      // Input direction means non-pcs connection, so proceed like devicelinks
      p.read_input_lut(intent)
    } else {
      // Output direction means PCS connection. Intent may apply here
      let lut = p.read_output_lut(intent)
      let (m, off) = compute_conversion(i, profiles, intent, bpc[i])
      add_conversion(result, current, cs_in, m, off)
      lut
    }
    result.cat(lut)
    current = cs_out
  }
  result
}

///|
/// `_cmsLinkProfiles`: decides BPC per profile, then links with the
/// default ICC intents handler (intents 0..3).
fn link_profiles(
  profiles : Array[LinkProfile],
  intents : Array[Int32],
  bpc0 : Array[Bool],
) -> Pipeline raise @bitstream.JxlError {
  let n = profiles.length()
  if n <= 0 || n > 255 {
    raise cms_error("CmsFailure: couldn't link profiles")
  }
  let bpc = bpc0.copy()
  for i in 0..<n {
    // BPC does not apply to devicelink profiles, nor to abs colorimetric,
    // and applies always on V4 perceptual and saturation.
    if intents[i] == INTENT_ABSOLUTE_COLORIMETRIC {
      bpc[i] = false
    }
    if intents[i] == INTENT_PERCEPTUAL || intents[i] == INTENT_SATURATION {
      // Force BPC for V4 profiles in perceptual and saturation
      if profiles[i].version() >= 0x4000000U {
        bpc[i] = true
      }
    }
  }
  if intents[0] < 0 || intents[0] > INTENT_ABSOLUTE_COLORIMETRIC {
    raise @bitstream.JxlError::NotSupported(
      "CmsFailure: unsupported intent \{intents[0]}",
    )
  }
  default_icc_intents(profiles, intents, bpc)
}

///|
/// `GetXFormColorSpaces`
fn get_xform_color_spaces(profiles : Array[LinkProfile]) -> (UInt32, UInt32) {
  let mut post = profiles[0].color_space()
  let mut input = 0U
  for i in 0..<profiles.length() {
    let p = profiles[i]
    let is_input = post != SIG_XYZ_DATA && post != SIG_LAB_DATA
    let cls = p.device_class()
    let (cs_in, cs_out) = if cls == SIG_NAMED_COLOR_CLASS {
      (
        0x31434C52U,
        if profiles.length() > 1 {
          p.pcs()
        } else {
          p.color_space()
        },
      )
    } else if is_input || cls == SIG_LINK_CLASS {
      (p.color_space(), p.pcs())
    } else {
      (p.pcs(), p.color_space())
    }
    if i == 0 {
      input = cs_in
    }
    post = cs_out
  }
  (input, post)
}

///|
/// Links profiles into an optimized float pipeline, as
/// `cmsCreateExtendedTransform` does for float formats (no cache, only
/// `PreOptimize`). Returns the pipeline and the entry/exit colour spaces.
fn create_pipeline(
  profiles : Array[LinkProfile],
  intents : Array[Int32],
  bpc : Array[Bool],
) -> (Pipeline, UInt32, UInt32) raise @bitstream.JxlError {
  let (entry, exit) = get_xform_color_spaces(profiles)
  let lut = link_profiles(profiles, intents, bpc)
  // Check channel count
  if channels_of_color_space(entry) != lut.in_ch ||
    channels_of_color_space(exit) != lut.out_ch {
    raise cms_error(
      "CmsFailure: channel count doesn't match. Profile is corrupted",
    )
  }
  lut.pre_optimize() |> ignore
  (lut, entry, exit)
}
