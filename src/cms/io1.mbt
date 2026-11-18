// Profile-to-pipeline conversion, ported from Little CMS 2.19 (as vendored by lcms2-sys 4.0.7) `cmsio1.c`.

///|
fn device2pcs16(intent : Int32) -> UInt32 {
  match intent {
    0 => SIG_A2B0
    1 => SIG_A2B1
    2 => SIG_A2B2
    _ => SIG_A2B1
  }
}

///|
fn pcs2device16(intent : Int32) -> UInt32 {
  match intent {
    0 => SIG_B2A0
    1 => SIG_B2A1
    2 => SIG_B2A2
    _ => SIG_B2A1
  }
}

///|
/// D2Bx / B2Dx (float tags, `multiProcessElementType`). They take precedence
/// in lcms2; this port does not implement MPE and reports them unsupported.
fn float_tag_sig(base : UInt32, intent : Int32) -> UInt32 {
  base + intent.reinterpret_as_uint()
}

///|
/// `_cmsReadMediaWhitePoint`
fn Profile::read_media_white_point(
  self : Profile,
) -> (Double, Double, Double) raise @bitstream.JxlError {
  guard self.read_xyz(SIG_MEDIA_WHITE_POINT) is Some(wp) else {
    return (D50_X, D50_Y, D50_Z)
  }
  // V2 display profiles should give D50
  if self.version < 0x4000000U && self.device_class == SIG_DISPLAY_CLASS {
    return (D50_X, D50_Y, D50_Z)
  }
  wp
}

///|
/// `ReadICCMatrixRGB2XYZ`
fn Profile::read_matrix_rgb2xyz(
  self : Profile,
) -> FixedArray[Double]? raise @bitstream.JxlError {
  guard self.read_xyz(SIG_RED_COLORANT) is Some(r) else { return None }
  guard self.read_xyz(SIG_GREEN_COLORANT) is Some(g) else { return None }
  guard self.read_xyz(SIG_BLUE_COLORANT) is Some(b) else { return None }
  Some([r.0, g.0, b.0, r.1, g.1, b.1, r.2, g.2, b.2])
}

///|
/// `BuildGrayInputMatrixPipeline`
fn Profile::build_gray_input_matrix_pipeline(
  self : Profile,
) -> Pipeline raise @bitstream.JxlError {
  guard self.read_trc(SIG_GRAY_TRC) is Some(gray_trc) else {
    raise cms_error("CmsFailure: missing kTRC")
  }
  let lut = Pipeline::new(1, 3)
  if self.pcs == SIG_LAB_DATA {
    // An identity matrix plus 3 tone curves
    let empty_tab = ToneCurve::tabulated16([0x8080, 0x8080])
    lut.push(stage_matrix(3, 1, [1.0, 1.0, 1.0], None))
    lut.push(stage_curves([gray_trc, empty_tab, empty_tab]))
  } else {
    let inp_adj = 1.0 / max_encodeable_xyz
    lut.push(stage_curves([gray_trc]))
    lut.push(
      stage_matrix(
        3,
        1,
        [inp_adj * D50_X, inp_adj * D50_Y, inp_adj * D50_Z],
        None,
      ),
    )
  }
  lut
}

///|
/// `BuildRGBInputMatrixShaper`
fn Profile::build_rgb_input_matrix_shaper(
  self : Profile,
) -> Pipeline raise @bitstream.JxlError {
  guard self.read_matrix_rgb2xyz() is Some(mat) else {
    raise cms_error("CmsFailure: missing colorants")
  }
  // XYZ PCS in encoded in 1.15 format, and the matrix output comes in
  // 0..0xffff range, so we need to adjust the output by a factor of
  // (0x10000/0xffff) to put data in a 1.16 range, and then a >> 1 to obtain
  // 1.15. The total factor is (65536.0)/(65535.0*2)
  let inp_adj = 1.0 / max_encodeable_xyz
  for i in 0..<9 {
    mat[i] *= inp_adj
  }
  guard self.read_trc(SIG_RED_TRC) is Some(r) &&
    self.read_trc(SIG_GREEN_TRC) is Some(g) &&
    self.read_trc(SIG_BLUE_TRC) is Some(b) else {
    raise cms_error("CmsFailure: missing TRC")
  }
  let lut = Pipeline::new(3, 3)
  lut.push(stage_curves([r, g, b]))
  lut.push(stage_matrix(3, 3, mat, None))
  // Note that it is certainly possible a single profile would have a LUT
  // based tag for output working in lab and a matrix-shaper for the fallback
  // cases. This is not allowed by the spec, but this code is tolerant to
  // those cases
  if self.pcs == SIG_LAB_DATA {
    lut.push(stage_xyz2lab())
  }
  lut
}

///|
/// `_cmsReadInputLUT`
fn Profile::read_input_lut(
  self : Profile,
  intent : Int32,
) -> Pipeline raise @bitstream.JxlError {
  if self.device_class == SIG_NAMED_COLOR_CLASS {
    raise @bitstream.JxlError::NotSupported(
      "UnsupportedIccProfile: named color profiles",
    )
  }
  if intent <= INTENT_ABSOLUTE_COLORIMETRIC {
    let mut tag16 = device2pcs16(intent)
    let tag_float = float_tag_sig(SIG_D2B0, intent)
    if self.is_tag(tag_float) {
      raise @bitstream.JxlError::NotSupported(
        "UnsupportedIccProfile: DToBx floating point tags",
      )
    }
    // Revert to perceptual if no tag is found
    if !self.is_tag(tag16) {
      tag16 = device2pcs16(0)
    }
    if self.read_lut_tag(tag16, true) is Some((lut, original_type)) {
      // We need to adjust data only for Lab16 on output
      if original_type != SIG_LUT16_TYPE || self.pcs != SIG_LAB_DATA {
        return lut
      }
      // If the input is Lab, add also a conversion at the begin
      if self.color_space == SIG_LAB_DATA {
        lut.insert_begin(stage_lab_v4_to_v2())
      }
      // Add a matrix for conversion V2 to V4 Lab PCS
      lut.push(stage_lab_v2_to_v4())
      return lut
    }
  }
  // Lut was not found, try to create a matrix-shaper
  if self.color_space == SIG_GRAY_DATA {
    return self.build_gray_input_matrix_pipeline()
  }
  self.build_rgb_input_matrix_shaper()
}

///|
/// `BuildGrayOutputPipeline`
fn Profile::build_gray_output_pipeline(
  self : Profile,
) -> Pipeline raise @bitstream.JxlError {
  guard self.read_trc(SIG_GRAY_TRC) is Some(gray_trc) else {
    raise cms_error("CmsFailure: missing kTRC")
  }
  let rev_gray_trc = gray_trc.reverse()
  let lut = Pipeline::new(3, 1)
  if self.pcs == SIG_LAB_DATA {
    lut.push(stage_matrix(1, 3, [1.0, 0.0, 0.0], None))
  } else {
    lut.push(stage_matrix(1, 3, [0.0, max_encodeable_xyz * D50_Y, 0.0], None))
  }
  lut.push(stage_curves([rev_gray_trc]))
  lut
}

///|
/// `BuildRGBOutputMatrixShaper`
fn Profile::build_rgb_output_matrix_shaper(
  self : Profile,
) -> Pipeline raise @bitstream.JxlError {
  guard self.read_matrix_rgb2xyz() is Some(mat) else {
    raise cms_error("CmsFailure: missing colorants")
  }
  guard mat3_inverse(mat) is Some(inv) else {
    raise cms_error("CmsFailure: singular colorant matrix")
  }
  // XYZ PCS in encoded in 1.15 format, and the matrix input should come in
  // 0..0xffff range, so we need to adjust the input by a << 1 to obtain a
  // 1.16 fixed and then by a factor of (0xffff/0x10000) to put data in
  // 0..0xffff range. Total factor is (2.0*65535.0)/65536.0;
  for i in 0..<9 {
    inv[i] *= max_encodeable_xyz
  }
  guard self.read_trc(SIG_RED_TRC) is Some(r) &&
    self.read_trc(SIG_GREEN_TRC) is Some(g) &&
    self.read_trc(SIG_BLUE_TRC) is Some(b) else {
    raise cms_error("CmsFailure: missing TRC")
  }
  let inv_shapes = [r.reverse(), g.reverse(), b.reverse()]
  let lut = Pipeline::new(3, 3)
  if self.pcs == SIG_LAB_DATA {
    lut.push(stage_lab2xyz())
  }
  lut.push(stage_matrix(3, 3, inv, None))
  lut.push(stage_curves(inv_shapes))
  lut
}

///|
/// `ChangeInterpolationToTrilinear`
fn change_interpolation_to_trilinear(lut : Pipeline) -> Unit {
  for s in lut.stages {
    if s.data is CLut16(params, _) {
      params.trilinear = true
    }
  }
}

///|
/// `_cmsReadOutputLUT`
fn Profile::read_output_lut(
  self : Profile,
  intent : Int32,
) -> Pipeline raise @bitstream.JxlError {
  if intent <= INTENT_ABSOLUTE_COLORIMETRIC {
    let mut tag16 = pcs2device16(intent)
    let tag_float = float_tag_sig(SIG_B2D0, intent)
    if self.is_tag(tag_float) {
      raise @bitstream.JxlError::NotSupported(
        "UnsupportedIccProfile: BToDx floating point tags",
      )
    }
    // Revert to perceptual if no tag is found
    if !self.is_tag(tag16) {
      tag16 = pcs2device16(0)
    }
    if self.read_lut_tag(tag16, false) is Some((lut, original_type)) {
      // Now it is time for a controversial stuff. I found that for 3D LUTS
      // using Lab used as indexer space, trilinear interpolation should be
      // used
      if self.pcs == SIG_LAB_DATA {
        change_interpolation_to_trilinear(lut)
      }
      // We need to adjust data only for Lab and Lut16 type
      if original_type != SIG_LUT16_TYPE || self.pcs != SIG_LAB_DATA {
        return lut
      }
      // Add a matrix for conversion V4 to V2 Lab PCS
      lut.insert_begin(stage_lab_v4_to_v2())
      // If the output is Lab, add also a conversion at the end
      if self.color_space == SIG_LAB_DATA {
        lut.push(stage_lab_v2_to_v4())
      }
      return lut
    }
  }
  // Lut not found, try to create a matrix-shaper
  if self.color_space == SIG_GRAY_DATA {
    return self.build_gray_output_pipeline()
  }
  self.build_rgb_output_matrix_shaper()
}

///|
/// `cmsIsMatrixShaper`
fn Profile::is_matrix_shaper(self : Profile) -> Bool {
  if self.color_space == SIG_GRAY_DATA {
    self.is_tag(SIG_GRAY_TRC)
  } else if self.color_space == SIG_RGB_DATA {
    self.is_tag(SIG_RED_COLORANT) &&
    self.is_tag(SIG_GREEN_COLORANT) &&
    self.is_tag(SIG_BLUE_COLORANT) &&
    self.is_tag(SIG_RED_TRC) &&
    self.is_tag(SIG_GREEN_TRC) &&
    self.is_tag(SIG_BLUE_TRC)
  } else {
    false
  }
}

///|
/// `cmsIsCLUT`; `as_input` selects the AToB (true) or BToA (false) table.
fn Profile::is_clut(self : Profile, intent : Int32, as_input : Bool) -> Bool {
  // For devicelinks, the supported intent is that one stated in the header
  if self.device_class == SIG_LINK_CLASS {
    return self.rendering_intent == intent.reinterpret_as_uint()
  }
  if intent > INTENT_ABSOLUTE_COLORIMETRIC {
    return false
  }
  if as_input {
    self.is_tag(device2pcs16(intent))
  } else {
    self.is_tag(pcs2device16(intent))
  }
}
