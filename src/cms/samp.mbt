// Black point detection, ported from Little CMS 2.19 (as vendored by lcms2-sys 4.0.7) `cmssamp.c`.
// The auxiliary transforms are built with the same linking code and
// evaluated through the float pipeline, as lcms2 does for its Lab double
// output formats.

///|
fn LinkProfile::is_matrix_shaper(self : LinkProfile) -> Bool {
  match self {
    Icc(p) => p.is_matrix_shaper()
    _ => false
  }
}

///|
fn LinkProfile::is_clut(
  self : LinkProfile,
  intent : Int32,
  as_input : Bool,
) -> Bool {
  match self {
    Icc(p) => p.is_clut(intent, as_input)
    // Built-in Lab profiles only have an AToB0 tag
    _ => as_input && intent == 0
  }
}

///|
fn LinkProfile::is_intent_supported(
  self : LinkProfile,
  intent : Int32,
  as_input : Bool,
) -> Bool {
  self.is_clut(intent, as_input) || self.is_matrix_shaper()
}

///|
/// Evaluates a float pipeline on one pixel.
fn eval_pixel(lut : Pipeline, inp : FixedArray[Float]) -> FixedArray[Float] {
  let out = FixedArray::make(MAX_STAGE_CHANNELS, Float::from_double(0.0))
  let b0 = FixedArray::make(MAX_STAGE_CHANNELS, Float::from_double(0.0))
  let b1 = FixedArray::make(MAX_STAGE_CHANNELS, Float::from_double(0.0))
  lut.eval_float(inp, out, b0, b1, EvalScratch::new())
  out
}

///|
/// `_cmsEndPointsBySpace` (black only).
fn black_by_space(cs : UInt32) -> FixedArray[Int32]? {
  if cs == SIG_GRAY_DATA {
    Some([0])
  } else if cs == SIG_RGB_DATA {
    Some([0, 0, 0])
  } else if cs == SIG_LAB_DATA {
    Some([0, 0x8080, 0x8080])
  } else if cs == SIG_CMYK_DATA {
    Some([0xffff, 0xffff, 0xffff, 0xffff])
  } else if cs == SIG_CMY_DATA {
    Some([0xffff, 0xffff, 0xffff])
  } else {
    None
  }
}

///|
/// `isInkColorspace` (CMY, CMYK, MCH1..MCHF, 1CLR..FCLR)
fn is_ink_colorspace(c : UInt32) -> Bool {
  if c == SIG_CMYK_DATA || c == SIG_CMY_DATA {
    return true
  }
  let hi = c >> 8
  let lo = c & 0xFF
  let digit = lo == 0x31 ||
    lo == 0x32 ||
    lo == 0x33 ||
    lo == 0x34 ||
    lo == 0x35 ||
    lo == 0x36 ||
    lo == 0x37 ||
    lo == 0x38 ||
    lo == 0x39 ||
    (lo >= 0x41 && lo <= 0x46)
  if hi == 0x4D4348 && digit {
    return true // MCHx
  }
  let first = c >> 24
  let rest = c & 0xFFFFFF
  let digit1 = (first >= 0x31 && first <= 0x39) ||
    (first >= 0x41 && first <= 0x46)
  rest == 0x434C52 && digit1 // xCLR
}

///|
let zero_xyz : (Double, Double, Double) = (0.0, 0.0, 0.0)

///|
/// `BlackPointAsDarkerColorant`
fn black_point_as_darker_colorant(
  p : LinkProfile,
  intent : Int32,
) -> (Double, Double, Double) {
  // If the profile does not support input direction, assume Black point 0
  if !p.is_intent_supported(intent, true) {
    return zero_xyz
  }
  guard black_by_space(p.color_space()) is Some(black) else { return zero_xyz }
  if black.length() != channels_of_color_space(p.color_space()) {
    return zero_xyz
  }
  // Lab will be used as the output space, but lab2 will avoid recursion
  let (lut, _, _) = create_pipeline([p, Lab2], [intent, intent], [false, false]) catch {
    _ => return zero_xyz
  }
  let inp = FixedArray::make(MAX_STAGE_CHANNELS, Float::from_double(0.0))
  for i in 0..<black.length() {
    // Unroll16ToFloat: float division by 65535.0F
    inp[i] = Float::from_int(black[i]) / Float::from_double(65535.0)
  }
  let out = eval_pixel(lut, inp)
  let mut l = out[0].to_double() * 100.0
  let a = out[1].to_double() * 255.0 - 128.0
  let b = out[2].to_double() * 255.0 - 128.0
  if l > 95.0 {
    l = 0.0 // for synthetical negative profiles
  } else if l < 0.0 {
    l = 0.0
  } else if l > 50.0 {
    l = 50.0
  }
  // Convert from Lab (which is now clipped) to XYZ.
  lab_to_xyz(l, a, b)
}

///|
/// `CreateRoundtripXForm` evaluated on one Lab colour.
fn roundtrip_lab(
  lut : Pipeline,
  l : Double,
  a : Double,
  b : Double,
) -> (Double, Double, Double) {
  let inp = FixedArray::make(MAX_STAGE_CHANNELS, Float::from_double(0.0))
  inp[0] = Float::from_double(l / 100.0)
  inp[1] = Float::from_double((a + 128.0) / 255.0)
  inp[2] = Float::from_double((b + 128.0) / 255.0)
  let out = eval_pixel(lut, inp)
  (
    out[0].to_double() * 100.0,
    out[1].to_double() * 255.0 - 128.0,
    out[2].to_double() * 255.0 - 128.0,
  )
}

///|
fn create_roundtrip(
  p : LinkProfile,
  intent : Int32,
) -> Pipeline raise @bitstream.JxlError {
  let (lut, _, _) = create_pipeline(
    [Lab4, p, p, Lab4],
    [
      INTENT_RELATIVE_COLORIMETRIC,
      intent,
      INTENT_RELATIVE_COLORIMETRIC,
      INTENT_RELATIVE_COLORIMETRIC,
    ],
    [false, false, false, false],
  )
  lut
}

///|
/// `BlackPointUsingPerceptualBlack`
fn black_point_using_perceptual_black(
  p : LinkProfile,
) -> (Double, Double, Double) {
  // Is the intent supported by the profile?
  if !p.is_intent_supported(INTENT_PERCEPTUAL, true) {
    return zero_xyz
  }
  let lut = create_roundtrip(p, INTENT_PERCEPTUAL) catch {
    _ => return zero_xyz
  }
  let (l0, _, _) = roundtrip_lab(lut, 0.0, 0.0, 0.0)
  // Clip Lab to reasonable limits
  let l = if l0 > 50.0 { 50.0 } else { l0 }
  lab_to_xyz(l, 0.0, 0.0)
}

///|
/// `cmsDetectBlackPoint`
fn detect_black_point(
  p : LinkProfile,
  intent : Int32,
) -> (Double, Double, Double) {
  let dev_class = p.device_class()
  // Make sure the device class is adequate
  if dev_class == SIG_LINK_CLASS ||
    dev_class == SIG_ABSTRACT_CLASS ||
    dev_class == SIG_NAMED_COLOR_CLASS {
    return zero_xyz
  }
  // Make sure intent is adequate
  if intent != INTENT_PERCEPTUAL &&
    intent != INTENT_RELATIVE_COLORIMETRIC &&
    intent != INTENT_SATURATION {
    return zero_xyz
  }
  // v4 + perceptual & saturation intents does have its own black point, and
  // it is well specified enough to use it. Black point tag is deprecated in
  // V4.
  if p.version() >= 0x4000000U &&
    (intent == INTENT_PERCEPTUAL || intent == INTENT_SATURATION) {
    // Matrix shaper share MRC & perceptual intents
    if p.is_matrix_shaper() {
      return black_point_as_darker_colorant(p, INTENT_RELATIVE_COLORIMETRIC)
    }
    // Get Perceptual black out of v4 profiles. That is fixed for perceptual
    // & saturation intents
    return (PERCEPTUAL_BLACK_X, PERCEPTUAL_BLACK_Y, PERCEPTUAL_BLACK_Z)
  }
  // If output profile, discount ink-limiting and that's all
  if intent == INTENT_RELATIVE_COLORIMETRIC &&
    dev_class == SIG_OUTPUT_CLASS &&
    is_ink_colorspace(p.color_space()) {
    return black_point_using_perceptual_black(p)
  }
  // Nope, compute BP using current intent.
  black_point_as_darker_colorant(p, intent)
}

///|
/// `RootOfLeastSquaresFitQuadraticCurve`
fn root_of_least_squares_fit_quadratic_curve(
  n : Int32,
  x : FixedArray[Double],
  y : FixedArray[Double],
) -> Double {
  let mut sum_x = 0.0
  let mut sum_x2 = 0.0
  let mut sum_x3 = 0.0
  let mut sum_x4 = 0.0
  let mut sum_y = 0.0
  let mut sum_yx = 0.0
  let mut sum_yx2 = 0.0
  if n < 4 {
    return 0.0
  }
  for i in 0..<n {
    let xn = x[i]
    let yn = y[i]
    sum_x += xn
    sum_x2 += xn * xn
    sum_x3 += xn * xn * xn
    sum_x4 += xn * xn * xn * xn
    sum_y += yn
    sum_yx += yn * xn
    sum_yx2 += yn * xn * xn
  }
  let nn = n.to_double()
  let m : FixedArray[Double] = [
    nn, sum_x, sum_x2, sum_x, sum_x2, sum_x3, sum_x2, sum_x3, sum_x4,
  ]
  guard mat3_solve(m, (sum_y, sum_yx, sum_yx2)) is Some(res) else { return 0.0 }
  let a = res.2
  let b = res.1
  let c = res.0
  if a.abs() < 1.0e-10 {
    if b.abs() < 1.0e-10 {
      return 0.0
    }
    let v = -c / b
    let mn = if 50.0 < v { 50.0 } else { v }
    if 0.0 > mn {
      0.0
    } else {
      mn
    }
  } else {
    let d = b * b - 4.0 * a * c
    if d <= 0.0 {
      0.0
    } else {
      let rt = (-b + d.sqrt()) / (2.0 * a)
      let mn = if 50.0 < rt { 50.0 } else { rt }
      if 0.0 > mn {
        0.0
      } else {
        mn
      }
    }
  }
}

///|
/// `cmsDetectDestinationBlackPoint`: the Adobe black point algorithm.
fn detect_destination_black_point(
  p : LinkProfile,
  intent : Int32,
) -> (Double, Double, Double) {
  let dev_class = p.device_class()
  if dev_class == SIG_LINK_CLASS ||
    dev_class == SIG_ABSTRACT_CLASS ||
    dev_class == SIG_NAMED_COLOR_CLASS {
    return zero_xyz
  }
  if intent != INTENT_PERCEPTUAL &&
    intent != INTENT_RELATIVE_COLORIMETRIC &&
    intent != INTENT_SATURATION {
    return zero_xyz
  }
  if p.version() >= 0x4000000U &&
    (intent == INTENT_PERCEPTUAL || intent == INTENT_SATURATION) {
    if p.is_matrix_shaper() {
      return black_point_as_darker_colorant(p, INTENT_RELATIVE_COLORIMETRIC)
    }
    return (PERCEPTUAL_BLACK_X, PERCEPTUAL_BLACK_Y, PERCEPTUAL_BLACK_Z)
  }
  // Check if the profile is lut based and gray, rgb or cmyk (7.2 in Adobe's
  // document)
  let cs = p.color_space()
  if !p.is_clut(intent, false) ||
    (cs != SIG_GRAY_DATA && cs != SIG_RGB_DATA && !is_ink_colorspace(cs)) {
    // In this case, handle as input case
    return detect_black_point(p, intent)
  }
  // Set a first guess, that should work on good profiles.
  let initial_lab = if intent == INTENT_RELATIVE_COLORIMETRIC {
    // calculate initial Lab as source black point
    let ini_xyz = detect_black_point(p, intent)
    xyz_to_lab(ini_xyz.0, ini_xyz.1, ini_xyz.2)
  } else {
    (0.0, 0.0, 0.0)
  }
  // Create a roundtrip. Define a Transform BT for all x in L*a*b*
  let round_trip = create_roundtrip(p, intent) catch { _ => return zero_xyz }
  let in_ramp = FixedArray::make(256, 0.0)
  let out_ramp = FixedArray::make(256, 0.0)
  let clamp50 = fn(v : Double) {
    let mx = if -50.0 > v { -50.0 } else { v }
    if 50.0 < mx {
      50.0
    } else {
      mx
    }
  }
  for l in 0..<256 {
    let ll = l.to_double() * 100.0 / 255.0
    let (dl, _, _) = roundtrip_lab(
      round_trip,
      ll,
      clamp50(initial_lab.1),
      clamp50(initial_lab.2),
    )
    in_ramp[l] = ll
    out_ramp[l] = dl
  }
  // Make monotonic
  for l = 254; l > 0; l = l - 1 {
    out_ramp[l] = if out_ramp[l] < out_ramp[l + 1] {
      out_ramp[l]
    } else {
      out_ramp[l + 1]
    }
  }
  // Check
  if !(out_ramp[0] < out_ramp[255]) {
    return zero_xyz
  }
  // Test for mid range straight (only on relative colorimetric)
  let min_l = out_ramp[0]
  let max_l = out_ramp[255]
  if intent == INTENT_RELATIVE_COLORIMETRIC {
    let mut nearly_straight_midrange = true
    for l in 0..<256 {
      if !(in_ramp[l] <= min_l + 0.2 * (max_l - min_l) ||
        (in_ramp[l] - out_ramp[l]).abs() < 4.0) {
        nearly_straight_midrange = false
      }
    }
    // If the mid range is straight (as determined above) then the
    // DestinationBlackPoint shall be the same as initialLab. Otherwise, the
    // DestinationBlackPoint shall be determined using curve fitting.
    if nearly_straight_midrange {
      return lab_to_xyz(initial_lab.0, initial_lab.1, initial_lab.2)
    }
  }
  // curve fitting: The round-trip curve normally looks like a nearly constant
  // section at the black point, with a corner and a nearly straight line to
  // the white point.
  let y_ramp = FixedArray::make(256, 0.0)
  for l in 0..<256 {
    y_ramp[l] = (out_ramp[l] - min_l) / (max_l - min_l)
  }
  // find the black point using the least squares error quadratic curve
  // fitting
  let (lo, hi) = if intent == INTENT_RELATIVE_COLORIMETRIC {
    (0.1, 0.5)
  } else {
    // Perceptual and saturation
    (0.03, 0.25)
  }
  // Capture shadow points for the fitting.
  let x = FixedArray::make(256, 0.0)
  let y = FixedArray::make(256, 0.0)
  let mut n = 0
  for l in 0..<256 {
    let ff = y_ramp[l]
    if ff >= lo && ff < hi {
      x[n] = in_ramp[l]
      y[n] = y_ramp[l]
      n += 1
    }
  }
  // No suitable points
  if n < 3 {
    return zero_xyz
  }
  // fit and get the vertex of quadratic curve
  let mut l = root_of_least_squares_fit_quadratic_curve(n, x, y)
  if l < 0.0 {
    // clip to zero L* if the vertex is negative
    l = 0.0
  }
  lab_to_xyz(l, initial_lab.1, initial_lab.2)
}
