// Port of jxl-color `convert.rs`: color transformation between color encodings.

///|
/// Color encoding represented by either enum values or an ICC profile.
pub struct ColorEncodingWithProfile {
  priv encoding : ColourEncoding
  priv icc_profile : Bytes
  priv is_cmyk : Bool
}

///|
/// Creates a color encoding from enum values.
pub fn ColorEncodingWithProfile::new(
  encoding : EnumColourEncoding,
) -> ColorEncodingWithProfile {
  { encoding: Enum(encoding), icc_profile: b"", is_cmyk: false, }
}

///|
/// Creates a color encoding from ICC profile.
///
/// Raises an error if it cannot parse the ICC profile.
pub fn ColorEncodingWithProfile::with_icc(
  icc_profile : Bytes,
) -> ColorEncodingWithProfile raise @bitstream.JxlError {
  let parsed : Result[EnumColourEncoding, @bitstream.JxlError] = Ok(
    parse_icc(icc_profile),
  ) catch {
    e => Err(e)
  }
  match parsed {
    Ok(encoding) => ColorEncodingWithProfile::new(encoding)
    Err(@bitstream.Color("UnsupportedIccProfile")) => {
      let raw = parse_icc_raw(icc_profile)
      {
        encoding: IccProfile(raw.color_space()),
        icc_profile,
        is_cmyk: raw.is_cmyk(),
      }
    }
    Err(e) => raise e
  }
}

///|
/// Returns the color encoding representation.
pub fn ColorEncodingWithProfile::encoding(
  self : ColorEncodingWithProfile,
) -> ColourEncoding {
  self.encoding
}

///|
/// Returns the associated ICC profile.
pub fn ColorEncodingWithProfile::icc_profile(
  self : ColorEncodingWithProfile,
) -> Bytes {
  self.icc_profile
}

///|
/// Returns whether the color encoding describes a grayscale color space.
pub fn ColorEncodingWithProfile::is_grayscale(
  self : ColorEncodingWithProfile,
) -> Bool {
  match self.encoding {
    Enum(encoding) => encoding.colour_space == Grey
    IccProfile(color_space) => color_space == Grey
  }
}

///|
/// Returns whether the color encoding represents CMYK color space.
pub fn ColorEncodingWithProfile::is_cmyk(
  self : ColorEncodingWithProfile,
) -> Bool {
  self.is_cmyk
}

///|
fn ColorEncodingWithProfile::is_equivalent(
  self : ColorEncodingWithProfile,
  other : ColorEncodingWithProfile,
) -> Bool {
  if self.encoding.want_icc() != other.encoding.want_icc() {
    return false
  }
  if self.encoding.want_icc() {
    return self.icc_profile == other.icc_profile
  }
  match (self.encoding, other.encoding) {
    (Enum(me), Enum(other)) => {
      if me.colour_space != other.colour_space {
        return false
      }
      if me.colour_space == Xyb {
        return true
      }
      if me.rendering_intent != other.rendering_intent ||
        me.white_point != other.white_point ||
        me.tf != other.tf {
        return false
      }
      me.colour_space == Grey || me.primaries == other.primaries
    }
    _ => false
  }
}

///|
pub struct ColorTransformBuilder {
  priv mut detect_peak : Bool
  priv mut srgb_icc : Bool
  priv mut from_pq : Bool
}

///|
/// Creates a new `ColorTransform` builder.
pub fn ColorTransformBuilder::new() -> ColorTransformBuilder {
  { detect_peak: false, srgb_icc: false, from_pq: false, }
}

///|
pub fn ColorTransformBuilder::default() -> ColorTransformBuilder {
  ColorTransformBuilder::new()
}

///|
pub fn ColorTransformBuilder::set_detect_peak(
  self : ColorTransformBuilder,
  value : Bool,
) -> ColorTransformBuilder {
  self.detect_peak = value
  self
}

///|
pub fn ColorTransformBuilder::set_srgb_icc(
  self : ColorTransformBuilder,
  value : Bool,
) -> ColorTransformBuilder {
  self.srgb_icc = value
  self
}

///|
pub fn ColorTransformBuilder::from_pq(
  self : ColorTransformBuilder,
  from_pq : Bool,
) -> ColorTransformBuilder {
  self.from_pq = from_pq
  self
}

///|
pub fn ColorTransformBuilder::build(
  self : ColorTransformBuilder,
  from : ColorEncodingWithProfile,
  to : ColorEncodingWithProfile,
  oim : OpsinInverseMatrix,
  tone_mapping : ToneMapping,
  cms : &ColorManagementSystem,
) -> ColorTransform raise @bitstream.JxlError {
  ColorTransform::with_builder(self, from, to, oim, tone_mapping, cms)
}

///|
/// Color transformation from a color encoding to another.
pub struct ColorTransform {
  priv begin_channels : Int32
  priv ops : Array[ColorTransformOp]
}

///|
/// Creates a new `ColorTransform` builder.
pub fn ColorTransform::builder() -> ColorTransformBuilder {
  ColorTransformBuilder::new()
}

///|
/// Prepares a color transformation.
///
/// Raises an error if it cannot prepare such color transformation.
pub fn ColorTransform::new(
  from : ColorEncodingWithProfile,
  to : ColorEncodingWithProfile,
  oim : OpsinInverseMatrix,
  tone_mapping : ToneMapping,
  cms : &ColorManagementSystem,
) -> ColorTransform raise @bitstream.JxlError {
  ColorTransform::with_builder(
    ColorTransformBuilder::default(),
    from,
    to,
    oim,
    tone_mapping,
    cms,
  )
}

///|
fn luminances_of(mat : FixedArray[Float]) -> FixedArray[Float] {
  [mat[3], mat[4], mat[5]]
}

///|
fn ColorTransform::with_builder(
  builder : ColorTransformBuilder,
  from : ColorEncodingWithProfile,
  to : ColorEncodingWithProfile,
  oim : OpsinInverseMatrix,
  tone_mapping : ToneMapping,
  cms : &ColorManagementSystem,
) -> ColorTransform raise @bitstream.JxlError {
  let detect_peak = builder.detect_peak
  let srgb_icc = builder.srgb_icc
  let from_pq = builder.from_pq
  let connecting_tf : TransferFunction = if srgb_icc { Srgb } else { Linear }
  let intensity_target = tone_mapping.intensity_target
  let min_nits = tone_mapping.min_nits
  let begin_channels = match from.encoding {
    Enum({ colour_space: Grey, .. }) => 1
    Enum(_) => 3
    IccProfile(_) => {
      let profile = from.icc_profile
      if profile.length() < 0x14 {
        3
      } else {
        let cs = profile[0x10:0x14]
        if cs == b"GRAY"[:] {
          1
        } else if cs == b"CMYK"[:] {
          4
        } else {
          3
        }
      }
    }
  }
  if from.is_equivalent(to) {
    return { begin_channels, ops: [], }
  }
  let ops : Array[ColorTransformOp] = []
  let mut current_encoding : EnumColourEncoding = match from.encoding {
    IccProfile(_) => {
      let rendering_intent = parse_icc_raw(from.icc_profile).header.rendering_intent
      match to.encoding {
        IccProfile(_) => {
          let transform = cms.prepare_transform(
            from.icc_profile,
            to.icc_profile,
            rendering_intent,
          )
          return { begin_channels, ops: [IccToIcc(transform)], }
        }
        Enum(encoding) => {
          let target_encoding = { ..encoding, tf: connecting_tf, }
          let to_icc = colour_encoding_to_icc(target_encoding)
          let transform = cms.prepare_transform(
            from.icc_profile,
            to_icc,
            rendering_intent,
          )
          ops.push(IccToIcc(transform))
          target_encoding
        }
      }
    }
    Enum({ colour_space: Xyb, rendering_intent, .. }) => {
      let inv_mat = oim.inv_mat
      let matrix : FixedArray[Float] = [
        inv_mat[0][0],
        inv_mat[0][1],
        inv_mat[0][2],
        inv_mat[1][0],
        inv_mat[1][1],
        inv_mat[1][2],
        inv_mat[2][0],
        inv_mat[2][1],
        inv_mat[2][2],
      ]
      ops.push(XybToMixedLms(opsin_bias=oim.opsin_bias, intensity_target~))
      ops.push(Matrix(matrix))
      // result: RGB; D65 illuminant, sRGB primaries, linear tf
      EnumColourEncoding::srgb_linear(rendering_intent)
    }
    Enum({ colour_space: Rgb, white_point, primaries, tf, .. } as encoding) => {
      let mat = primaries_to_xyz_mat(primaries, white_point)
      let luminances = luminances_of(mat)
      ops.push(
        TransferFunction(
          tf~,
          hdr_params={ luminances, intensity_target, min_nits, },
          inverse=true,
        ),
      )
      { ..encoding, tf: Linear, }
    }
    Enum({ colour_space: Grey, white_point, tf, .. } as encoding) => {
      // primaries don't matter for grayscale
      let mat = primaries_to_xyz_mat(Primaries::Srgb, white_point)
      let luminances = luminances_of(mat)
      ops.push(
        TransferFunction(
          tf~,
          hdr_params={ luminances, intensity_target, min_nits, },
          inverse=true,
        ),
      )
      { ..encoding, tf: Linear, }
    }
    Enum(_) => raise @bitstream.Color("UnsupportedColorEncoding")
  }
  let target_encoding = match to.encoding {
    Enum(encoding) => encoding
    IccProfile(_) => {
      let from_icc = colour_encoding_to_icc(current_encoding)
      let transform = cms.prepare_transform(
        from_icc,
        to.icc_profile,
        current_encoding.rendering_intent,
      )
      ops.push(IccToIcc(transform))
      return { begin_channels, ops, }
    }
  }
  if current_encoding.tf != Linear {
    ops.push(
      TransferFunction(
        tf=current_encoding.tf,
        hdr_params={ luminances: [0.0, 0.0, 0.0], intensity_target, min_nits, },
        inverse=true,
      ),
    )
    current_encoding = { ..current_encoding, tf: Linear, }
  }
  if current_encoding.colour_space != target_encoding.colour_space ||
    current_encoding.white_point != target_encoding.white_point ||
    (
      current_encoding.colour_space == Rgb &&
      current_encoding.primaries != target_encoding.primaries
    ) {
    if current_encoding.rendering_intent == Perceptual {
      let mat = primaries_to_xyz_mat(
        current_encoding.primaries,
        current_encoding.white_point,
      )
      ops.push(GamutMap(luminances=luminances_of(mat), saturation_factor=0.3))
    } else {
      ops.push(Clip)
    }
    match current_encoding.colour_space {
      Rgb => {
        // RGB to XYZ
        let mat = primaries_to_xyz_mat(
          current_encoding.primaries,
          current_encoding.white_point,
        )
        ops.push(Matrix(mat))
      }
      Grey => {
        // Yxy to XYZ
        let illuminant = AsIlluminant::as_illuminant(
          current_encoding.white_point,
        )
        ops.push(LumaToXyz(illuminant~))
      }
      Xyb | Unknown => abort("unreachable")
    }
    if current_encoding.rendering_intent != Absolute {
      // Chromatic adaptation: XYZ to XYZ
      let adapt = adapt_mat(
        current_encoding.white_point,
        target_encoding.white_point,
      )
      ops.push(Matrix(adapt))
    }
    match target_encoding.colour_space {
      Rgb => {
        // XYZ to RGB
        let mat = xyz_to_primaries_mat(
          target_encoding.primaries,
          target_encoding.white_point,
        )
        ops.push(Matrix(mat))
      }
      Grey =>
        // XYZ to Yxy
        ops.push(XyzToLuma)
      Xyb | Unknown => raise @bitstream.Color("UnsupportedColorEncoding")
    }
    current_encoding = {
      ..current_encoding,
      colour_space: target_encoding.colour_space,
      white_point: target_encoding.white_point,
      primaries: target_encoding.primaries,
    }
  }
  let mat = primaries_to_xyz_mat(
    current_encoding.primaries,
    current_encoding.white_point,
  )
  let luminances = luminances_of(mat)
  let mut hdr_params : HdrParams = { luminances, intensity_target, min_nits, }
  if intensity_target > 255.0 && !target_encoding.is_hdr() {
    if current_encoding.colour_space == Grey {
      ops.push(
        ToneMapLumaRec2408(
          hdr_params~,
          target_display_luminance=255.0,
          detect_peak~,
        ),
      )
    } else {
      ops.push(
        ToneMapRec2408(
          hdr_params~,
          target_display_luminance=255.0,
          detect_peak~,
        ),
      )
      if current_encoding.rendering_intent == Perceptual {
        ops.push(GamutMap(luminances~, saturation_factor=0.3))
      }
    }
  }

  // PQ to HLG: tonemap to peak 1000 nits before applying inverse OOTF.
  if from_pq && target_encoding.tf == Hlg {
    if !(hdr_params.intensity_target >= 999.0 &&
      hdr_params.intensity_target <= 1001.0) {
      if current_encoding.colour_space == Grey {
        ops.push(
          ToneMapLumaRec2408(
            hdr_params~,
            target_display_luminance=1000.0,
            detect_peak=false,
          ),
        )
      } else {
        ops.push(
          ToneMapRec2408(
            hdr_params~,
            target_display_luminance=1000.0,
            detect_peak=false,
          ),
        )
      }
      hdr_params = { ..hdr_params, intensity_target: 1000.0, }
      ops.push(HlgInverseOotf(hdr_params))
    }
    if current_encoding.colour_space != Grey &&
      current_encoding.rendering_intent == Perceptual {
      ops.push(GamutMap(luminances~, saturation_factor=0.1))
    }

    // Skip inverse OOTF in transfer funcion conversion.
    hdr_params = { ..hdr_params, intensity_target: 300.0, }
  }
  if target_encoding.tf != Linear {
    ops.push(
      TransferFunction(tf=target_encoding.tf, hdr_params~, inverse=false),
    )
  }
  let ret : ColorTransform = { begin_channels, ops, }
  ret.optimize()
}

///|
/// Prepares a color transformation from XYB color encoding.
///
/// Raises an error if it cannot prepare such color transformation.
pub fn ColorTransform::xyb_to_enum(
  xyb_rendering_intent : RenderingIntent,
  encoding : EnumColourEncoding,
  oim : OpsinInverseMatrix,
  tone_mapping : ToneMapping,
) -> ColorTransform raise @bitstream.JxlError {
  ColorTransform::new(
    ColorEncodingWithProfile::new(EnumColourEncoding::xyb(xyb_rendering_intent)),
    ColorEncodingWithProfile::new(encoding),
    oim,
    tone_mapping,
    NullCms::{ }, // XYB to enum colorspace shouldn't generate ICC op
  )
}

///|
pub fn ColorTransform::is_noop(self : ColorTransform) -> Bool {
  self.ops.is_empty()
}

///|
pub fn ColorTransform::input_channels(self : ColorTransform) -> Int32 {
  self.begin_channels
}

///|
pub fn ColorTransform::output_channels(self : ColorTransform) -> Int32 {
  let mut channels = self.begin_channels
  for op in self.ops {
    if op.outputs() is Some(x) {
      channels = x
    }
  }
  channels
}

///|
/// Performs the prepared color transformation on the samples.
///
/// Returns the number of final channels after transformation.
///
/// `channels` are planar sample data, all having the same length; samples
/// `start..start + len` (the whole buffers by default) are transformed.
///
/// Raises an error if it encountered ICC to ICC operation and the provided
/// CMS cannot handle it.
pub fn ColorTransform::run(
  self : ColorTransform,
  channels : Array[FixedArray[Float]],
  start~ : Int32 = 0,
  len~ : Int32 = (if channels.is_empty() { 0 } else { channels[0].length() }) -
    start,
) -> Int32 raise @bitstream.JxlError {
  let mut num_channels = self.begin_channels
  for op in self.ops {
    num_channels = op.run(channels, num_channels, start, len)
  }
  num_channels
}

///|
/// Performs the prepared color transformation on the samples, in chunks of
/// 65536 samples (jxl-oxide runs the chunks on a thread pool; here they run
/// sequentially). Peak detection of tone mapping operates per chunk.
///
/// Returns the number of final channels after transformation.
pub fn ColorTransform::run_with_threads(
  self : ColorTransform,
  channels : Array[FixedArray[Float]],
) -> Int32 raise @bitstream.JxlError {
  let total = channels.fold(init=-1, (acc, ch) => {
    if acc < 0 || ch.length() < acc {
      ch.length()
    } else {
      acc
    }
  })
  let mut ret = self.begin_channels
  let mut start = 0
  while start < total {
    let len = (total - start).min(65536)
    ret = self.run(channels, start~, len~)
    start += len
  }
  ret
}

///|
fn ColorTransform::optimize(self : ColorTransform) -> ColorTransform {
  let ops : Array[ColorTransformOp] = []
  let mut in_matrix_run = false
  for op in self.ops {
    match op {
      Matrix(mat) =>
        if in_matrix_run {
          guard ops.pop() is Some(Matrix(matrix)) else { abort("unreachable") }
          ops.push(Matrix(matmul3(mat, matrix)))
        } else {
          in_matrix_run = true
          ops.push(op)
        }
      _ => {
        in_matrix_run = false
        ops.push(op)
      }
    }
  }
  { begin_channels: self.begin_channels, ops, }
}

///|
priv struct HdrParams {
  luminances : FixedArray[Float]
  intensity_target : Float
  min_nits : Float
}

///|
enum ColorTransformOp {
  XybToMixedLms(opsin_bias~ : FixedArray[Float], intensity_target~ : Float)
  LumaToXyz(illuminant~ : FixedArray[Float])
  XyzToLuma
  Matrix(FixedArray[Float])
  TransferFunction(
    tf~ : TransferFunction,
    hdr_params~ : HdrParams,
    inverse~ : Bool,
  )
  HlgInverseOotf(HdrParams)
  ToneMapRec2408(
    hdr_params~ : HdrParams,
    target_display_luminance~ : Float,
    detect_peak~ : Bool,
  )
  ToneMapLumaRec2408(
    hdr_params~ : HdrParams,
    target_display_luminance~ : Float,
    detect_peak~ : Bool,
  )
  GamutMap(luminances~ : FixedArray[Float], saturation_factor~ : Float)
  Clip
  IccToIcc(&PreparedTransform)
}

///|
fn ColorTransformOp::inputs(self : ColorTransformOp) -> Int32? {
  match self {
    XybToMixedLms(..) | Matrix(_) => Some(3)
    LumaToXyz(..) => Some(1)
    XyzToLuma => Some(3)
    TransferFunction(tf=Hlg, ..) => Some(3)
    TransferFunction(..) => None
    HlgInverseOotf(_) => Some(3)
    ToneMapRec2408(..) => Some(3)
    ToneMapLumaRec2408(..) => Some(1)
    GamutMap(..) => Some(3)
    Clip => None
    IccToIcc(transform) => Some(transform.num_input_channels())
  }
}

///|
fn ColorTransformOp::outputs(self : ColorTransformOp) -> Int32? {
  match self {
    XybToMixedLms(..) | Matrix(_) => Some(3)
    LumaToXyz(..) => Some(3)
    XyzToLuma => Some(1)
    TransferFunction(tf=Hlg, ..) => Some(3)
    TransferFunction(..) => None
    HlgInverseOotf(_) => Some(3)
    ToneMapRec2408(..) => Some(3)
    ToneMapLumaRec2408(..) => Some(1)
    GamutMap(..) => Some(3)
    Clip => None
    IccToIcc(transform) => Some(transform.num_output_channels())
  }
}

///|
fn ColorTransformOp::run(
  self : ColorTransformOp,
  channels : Array[FixedArray[Float]],
  num_input_channels : Int32,
  start : Int32,
  len : Int32,
) -> Int32 raise @bitstream.JxlError {
  let channel_count = channels.length()
  if self.inputs() is Some(inputs) {
    guard channel_count >= inputs else { abort("not enough channels") }
  }
  if self.outputs() is Some(outputs) {
    guard channel_count >= outputs else { abort("not enough channels") }
  }
  match self {
    XybToMixedLms(opsin_bias~, intensity_target~) => {
      xyb_run(
        channels[0],
        channels[1],
        channels[2],
        opsin_bias,
        intensity_target,
        start~,
        len~,
      )
      3
    }
    LumaToXyz(illuminant~) => {
      let a = channels[0]
      let b = channels[1]
      let c = channels[2]
      let x = illuminant[0]
      let y = illuminant[1]
      for i in start..<(start + len) {
        let luma_div_y = a[i] / y
        b[i] = a[i]
        a[i] = x * luma_div_y
        c[i] = (1.0 - x - y) * luma_div_y
      }
      3
    }
    XyzToLuma => {
      let x = channels[0]
      let y = channels[1]
      for i in start..<(start + len) {
        x[i] = y[i]
      }
      1
    }
    Matrix(matrix) => {
      let a = channels[0]
      let b = channels[1]
      let c = channels[2]
      for i in start..<(start + len) {
        let av = a[i]
        let bv = b[i]
        let cv = c[i]
        a[i] = matrix[0] * av + matrix[1] * bv + matrix[2] * cv
        b[i] = matrix[3] * av + matrix[4] * bv + matrix[5] * cv
        c[i] = matrix[6] * av + matrix[7] * bv + matrix[8] * cv
      }
      3
    }
    TransferFunction(tf~, hdr_params~, inverse=false) => {
      apply_transfer_function(
        channels, num_input_channels, tf, hdr_params, start, len,
      )
      num_input_channels
    }
    TransferFunction(tf~, hdr_params~, inverse=true) => {
      apply_inverse_transfer_function(
        channels, num_input_channels, tf, hdr_params, start, len,
      )
      num_input_channels
    }
    HlgInverseOotf({ luminances, intensity_target, .. }) => {
      // FIXME: allow grayscale images.
      hlg_inverse_oo(
        channels[0],
        channels[1],
        channels[2],
        luminances,
        intensity_target,
        start~,
        len~,
      )
      3
    }
    ToneMapRec2408(hdr_params~, target_display_luminance~, detect_peak~) => {
      tone_map(
        channels[0],
        channels[1],
        channels[2],
        hdr_params,
        target_display_luminance,
        detect_peak,
        start,
        len,
      )
      3
    }
    ToneMapLumaRec2408(hdr_params~, target_display_luminance~, detect_peak~) => {
      tone_map_luma(
        channels[0],
        hdr_params,
        target_display_luminance,
        detect_peak,
        start,
        len,
      )
      1
    }
    GamutMap(luminances~, saturation_factor~) => {
      gamut_map(
        channels[0],
        channels[1],
        channels[2],
        luminances,
        saturation_factor,
        start,
        len,
      )
      3
    }
    Clip => {
      for c in 0..<num_input_channels {
        let buf = channels[c]
        for i in start..<(start + len) {
          let v = buf[i]
          // `f32::clamp(0.0, 1.0)`: NaN stays NaN.
          buf[i] = if v < 0.0 { 0.0 } else if v > 1.0 { 1.0 } else { v }
        }
      }
      num_input_channels
    }
    IccToIcc(transform) => {
      transform.transform(channels, start, len)
      transform.num_output_channels()
    }
  }
}

///|
fn apply_transfer_function(
  channels : Array[FixedArray[Float]],
  num_channels : Int32,
  tf : TransferFunction,
  hdr_params : HdrParams,
  start : Int32,
  len : Int32,
) -> Unit {
  match tf {
    Gamma(g~, inverted=false) => {
      let gamma = (1.0e7 : Float) / Float::from_int(g)
      for c in 0..<num_channels {
        apply_gamma(channels[c], gamma, start~, len~)
      }
    }
    Gamma(g~, inverted=true) => {
      let gamma = Float::from_int(g) / 1.0e7
      for c in 0..<num_channels {
        apply_gamma(channels[c], gamma, start~, len~)
      }
    }
    Bt709 =>
      for c in 0..<num_channels {
        linear_to_bt709(channels[c], start~, len~)
      }
    Unknown => ()
    Linear => ()
    Srgb =>
      for c in 0..<num_channels {
        linear_to_srgb(channels[c], start~, len~)
      }
    Pq => {
      let intensity_target = hdr_params.intensity_target
      for c in 0..<num_channels {
        linear_to_pq(channels[c], intensity_target, start~, len~)
      }
    }
    Dci => {
      let gamma : Float = 1.0 / 2.6
      for c in 0..<num_channels {
        apply_gamma(channels[c], gamma, start~, len~)
      }
    }
    Hlg => {
      guard num_channels >= 3 else { abort("HLG needs three channels") }
      let r = channels[0]
      let g = channels[1]
      let b = channels[2]
      let luminances = hdr_params.luminances
      let intensity_target = hdr_params.intensity_target
      hlg_inverse_oo(r, g, b, luminances, intensity_target, start~, len~)
      linear_to_hlg(r, start~, len~)
      linear_to_hlg(g, start~, len~)
      linear_to_hlg(b, start~, len~)
    }
  }
}

///|
fn apply_inverse_transfer_function(
  channels : Array[FixedArray[Float]],
  num_channels : Int32,
  tf : TransferFunction,
  hdr_params : HdrParams,
  start : Int32,
  len : Int32,
) -> Unit {
  match tf {
    Gamma(g~, inverted=false) => {
      let gamma = Float::from_int(g) / 1.0e7
      for c in 0..<num_channels {
        apply_gamma(channels[c], gamma, start~, len~)
      }
    }
    Gamma(g~, inverted=true) => {
      let gamma = (1.0e7 : Float) / Float::from_int(g)
      for c in 0..<num_channels {
        apply_gamma(channels[c], gamma, start~, len~)
      }
    }
    Bt709 =>
      for c in 0..<num_channels {
        bt709_to_linear(channels[c], start~, len~)
      }
    Unknown => ()
    Linear => ()
    Srgb =>
      for c in 0..<num_channels {
        srgb_to_linear(channels[c], start~, len~)
      }
    Pq => {
      let intensity_target = hdr_params.intensity_target
      for c in 0..<num_channels {
        pq_to_linear(channels[c], intensity_target, start~, len~)
      }
    }
    Dci => {
      let gamma : Float = 2.6
      for c in 0..<num_channels {
        apply_gamma(channels[c], gamma, start~, len~)
      }
    }
    Hlg => {
      guard num_channels >= 3 else { abort("HLG needs three channels") }
      let r = channels[0]
      let g = channels[1]
      let b = channels[2]
      let luminances = hdr_params.luminances
      let intensity_target = hdr_params.intensity_target
      hlg_to_linear(r, start~, len~)
      hlg_to_linear(g, start~, len~)
      hlg_to_linear(b, start~, len~)
      hlg_oo(r, g, b, luminances, intensity_target, start~, len~)
    }
  }
}
