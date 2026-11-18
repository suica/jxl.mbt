// Port of jxl-image/src/lib.rs: JPEG XL image header types.

///|
/// JPEG XL image header.
#derive(Debug)
pub(all) struct ImageHeader {
  /// Image size information.
  mut size : SizeHeader
  /// Image metadata.
  mut metadata : ImageMetadata
}

///|
pub fn ImageHeader::parse(
  bs : @bitstream.Bitstream,
) -> ImageHeader raise @bitstream.JxlError {
  let signature = bs.read_bits(16)
  if signature != 0xaff {
    raise @bitstream.ValidationFailed("JPEG XL signature mismatch")
  }
  let size = SizeHeader::parse(bs)
  let metadata = ImageMetadata::parse(bs)
  if metadata.ec_info.length() > 256 {
    raise @bitstream.ProfileConformance("num_extra too large")
  }
  let tone_mapping = metadata.tone_mapping
  if tone_mapping.intensity_target <= 0.0 {
    raise @bitstream.ValidationFailed("Invalid intensity target")
  }
  if tone_mapping.min_nits < 0.0 ||
    tone_mapping.min_nits > tone_mapping.intensity_target {
    raise @bitstream.ValidationFailed("Invalid tone mapping min_nits")
  }
  if tone_mapping.linear_below < 0.0 ||
    (tone_mapping.relative_to_max_display && tone_mapping.linear_below > 1.0) {
    raise @bitstream.ValidationFailed("Invalid tone mapping linear_below")
  }
  { size, metadata, }
}

///|
/// Returns the image width with orientation applied.
pub fn ImageHeader::width_with_orientation(self : ImageHeader) -> Int32 {
  self.metadata.apply_orientation(
    self.size.width,
    self.size.height,
    0,
    0,
    false,
  ).0
}

///|
/// Returns the image height with orientation applied.
pub fn ImageHeader::height_with_orientation(self : ImageHeader) -> Int32 {
  self.metadata.apply_orientation(
    self.size.width,
    self.size.height,
    0,
    0,
    false,
  ).1
}

///|
fn read_u32_int(
  bs : @bitstream.Bitstream,
  d0 : @bitstream.U32Spec,
  d1 : @bitstream.U32Spec,
  d2 : @bitstream.U32Spec,
  d3 : @bitstream.U32Spec,
) -> Int32 raise @bitstream.JxlError {
  bs.read_u32(d0, d1, d2, d3).reinterpret_as_int()
}

///|
/// Image size information.
#derive(Debug)
pub(all) struct SizeHeader {
  priv div8 : Bool
  priv h_div8 : Int32
  /// Image height.
  mut height : Int32
  priv ratio : Int32
  priv w_div8 : Int32
  /// Image width.
  mut width : Int32
}

///|
pub fn SizeHeader::parse(
  bs : @bitstream.Bitstream,
) -> SizeHeader raise @bitstream.JxlError {
  let div8 = bs.read_bool()
  let h_div8 = if div8 { bs.read_bits_int(5) + 1 } else { 0 }
  let height = if !div8 {
    read_u32_int(
      bs,
      @bitstream.cu(1, 9),
      @bitstream.cu(1, 13),
      @bitstream.cu(1, 18),
      @bitstream.cu(1, 30),
    )
  } else {
    8 * h_div8
  }
  let ratio = bs.read_bits_int(3)
  let w_div8 = if div8 && ratio == 0 { bs.read_bits_int(5) + 1 } else { 0 }
  let width = if !div8 && ratio == 0 {
    read_u32_int(
      bs,
      @bitstream.cu(1, 9),
      @bitstream.cu(1, 13),
      @bitstream.cu(1, 18),
      @bitstream.cu(1, 30),
    )
  } else {
    SizeHeader::compute_default_width(ratio, w_div8, height)
  }
  { div8, h_div8, height, ratio, w_div8, width, }
}

///|
pub fn SizeHeader::default() -> SizeHeader {
  let height = 0
  {
    div8: false,
    h_div8: 0,
    height,
    ratio: 0,
    w_div8: 0,
    width: SizeHeader::compute_default_width(0, 0, height),
  }
}

///|
fn SizeHeader::compute_default_width(
  ratio : Int32,
  w_div8 : Int32,
  height : Int32,
) -> Int32 {
  let height = height.reinterpret_as_uint().to_uint64()
  let res : UInt64 = match ratio {
    0 => 8UL * w_div8.reinterpret_as_uint().to_uint64()
    1 => height
    2 => height * 12 / 10
    3 => height * 4 / 3
    4 => height * 3 / 2
    5 => height * 16 / 9
    6 => height * 5 / 4
    7 => height * 2
    _ => abort("Invalid ratio const: \{ratio}")
  }
  res.to_uint().reinterpret_as_int()
}

///|
/// Image metadata.
#derive(Debug)
pub(all) struct ImageMetadata {
  priv all_default : Bool
  priv extra_fields : Bool
  /// Value representing image orientation.
  mut orientation : Int32
  priv have_intr_size : Bool
  /// Recommended size to display the image.
  mut intrinsic_size : SizeHeader?
  priv have_preview : Bool
  /// Size information of the preview frame, if there is any.
  mut preview : PreviewHeader?
  priv have_animation : Bool
  /// Information about the animation such as TPS, if the image is animated.
  mut animation : AnimationHeader?
  /// Bit depth information, which is used to parse Modular image samples.
  mut bit_depth : BitDepth
  /// Whether 16-bit buffer is sufficient to correctly parse Modular images.
  mut modular_16bit_buffers : Bool
  priv num_extra : Int32
  /// Information about extra channels, such as alpha and black channels.
  mut ec_info : Array[ExtraChannelInfo]
  /// Whether the image is encoded in XYB color space.
  mut xyb_encoded : Bool
  /// Color encoding of the image.
  ///
  /// If `xyb_encoded` is `true`, this is a suggestion of the color space to present the
  /// decoded image. If it's not, the decoded image is in the color space represented by this
  /// field.
  mut colour_encoding : ColourEncoding
  /// Tone mapping information, which is used to map HDR images to SDR.
  mut tone_mapping : ToneMapping
  mut extensions : Extensions
  priv default_m : Bool
  /// Opsin inverse matrix, which is used to transform XYB encoded image to sRGB color space.
  mut opsin_inverse_matrix : OpsinInverseMatrix
  priv cw_mask : Int32
  /// 2x upsampling weights.
  mut up2_weight : FixedArray[Float]
  /// 4x upsampling weights.
  mut up4_weight : FixedArray[Float]
  /// 8x upsampling weights.
  mut up8_weight : FixedArray[Float]
}

///|
fn read_f16_array(
  bs : @bitstream.Bitstream,
  n : Int32,
) -> FixedArray[Float] raise @bitstream.JxlError {
  let ret = FixedArray::make(n, (0.0 : Float))
  for i in 0..<n {
    ret[i] = bs.read_f16_as_f32()
  }
  ret
}

///|
pub fn ImageMetadata::parse(
  bs : @bitstream.Bitstream,
) -> ImageMetadata raise @bitstream.JxlError {
  let all_default = bs.read_bool()
  let extra_fields = if !all_default { bs.read_bool() } else { false }
  let orientation = if extra_fields { bs.read_bits_int(3) + 1 } else { 1 }
  let have_intr_size = if extra_fields { bs.read_bool() } else { false }
  let intrinsic_size = if have_intr_size {
    Some(SizeHeader::parse(bs))
  } else {
    None
  }
  let have_preview = if extra_fields { bs.read_bool() } else { false }
  let preview = if have_preview { Some(PreviewHeader::parse(bs)) } else { None }
  let have_animation = if extra_fields { bs.read_bool() } else { false }
  let animation = if have_animation {
    Some(AnimationHeader::parse(bs))
  } else {
    None
  }
  let bit_depth = if !all_default {
    BitDepth::parse(bs)
  } else {
    BitDepth::default()
  }
  let modular_16bit_buffers = if !all_default { bs.read_bool() } else { true }
  let num_extra = if !all_default {
    read_u32_int(
      bs,
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.cu(2, 4),
      @bitstream.cu(1, 12),
    )
  } else {
    0
  }
  let ec_info = []
  if !all_default {
    for _ in 0..<num_extra {
      ec_info.push(ExtraChannelInfo::parse(bs))
    }
  }
  let xyb_encoded = if !all_default { bs.read_bool() } else { true }
  let colour_encoding = if !all_default {
    ColourEncoding::parse(bs)
  } else {
    ColourEncoding::default()
  }
  let tone_mapping = if extra_fields {
    ToneMapping::parse(bs)
  } else {
    ToneMapping::default()
  }
  let extensions = if !all_default {
    Extensions::parse(bs)
  } else {
    Extensions::default()
  }
  let default_m = bs.read_bool()
  let opsin_inverse_matrix = if !default_m && xyb_encoded {
    OpsinInverseMatrix::parse(bs)
  } else {
    OpsinInverseMatrix::default()
  }
  let cw_mask = if !default_m { bs.read_bits_int(3) } else { 0 }
  let up2_weight = if (cw_mask & 1) != 0 {
    read_f16_array(bs, 15)
  } else {
    d_up2.copy()
  }
  let up4_weight = if (cw_mask & 2) != 0 {
    read_f16_array(bs, 55)
  } else {
    d_up4.copy()
  }
  let up8_weight = if (cw_mask & 4) != 0 {
    read_f16_array(bs, 210)
  } else {
    d_up8.copy()
  }
  {
    all_default,
    extra_fields,
    orientation,
    have_intr_size,
    intrinsic_size,
    have_preview,
    preview,
    have_animation,
    animation,
    bit_depth,
    modular_16bit_buffers,
    num_extra,
    ec_info,
    xyb_encoded,
    colour_encoding,
    tone_mapping,
    extensions,
    default_m,
    opsin_inverse_matrix,
    cw_mask,
    up2_weight,
    up4_weight,
    up8_weight,
  }
}

///|
/// `ImageMetadata` with every field at its default value.
pub fn ImageMetadata::default() -> ImageMetadata {
  {
    all_default: true,
    extra_fields: false,
    orientation: 1,
    have_intr_size: false,
    intrinsic_size: None,
    have_preview: false,
    preview: None,
    have_animation: false,
    animation: None,
    bit_depth: BitDepth::default(),
    modular_16bit_buffers: true,
    num_extra: 0,
    ec_info: [],
    xyb_encoded: true,
    colour_encoding: ColourEncoding::default(),
    tone_mapping: ToneMapping::default(),
    extensions: Extensions::default(),
    default_m: false,
    opsin_inverse_matrix: OpsinInverseMatrix::default(),
    cw_mask: 0,
    up2_weight: d_up2.copy(),
    up4_weight: d_up4.copy(),
    up8_weight: d_up8.copy(),
  }
}

///|
#derive(Debug)
pub(all) struct PreviewHeader {
  priv div8 : Bool
  priv h_div8 : Int32
  /// Height of the preview image.
  mut height : Int32
  priv ratio : Int32
  priv w_div8 : Int32
  /// Width of the preview image.
  mut width : Int32
}

///|
fn read_preview_div8(
  bs : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  read_u32_int(
    bs,
    @bitstream.c(16),
    @bitstream.c(32),
    @bitstream.cu(1, 5),
    @bitstream.cu(33, 9),
  )
}

///|
fn read_preview_dim(
  bs : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  read_u32_int(
    bs,
    @bitstream.cu(1, 6),
    @bitstream.cu(65, 8),
    @bitstream.cu(321, 10),
    @bitstream.cu(1345, 12),
  )
}

///|
pub fn PreviewHeader::parse(
  bs : @bitstream.Bitstream,
) -> PreviewHeader raise @bitstream.JxlError {
  let div8 = bs.read_bool()
  let h_div8 = if div8 { read_preview_div8(bs) } else { 1 }
  let height = if !div8 { read_preview_dim(bs) } else { 8 * h_div8 }
  let ratio = bs.read_bits_int(3)
  let w_div8 = if div8 { read_preview_div8(bs) } else { 1 }
  let width = if !div8 {
    read_preview_dim(bs)
  } else {
    SizeHeader::compute_default_width(ratio, w_div8, height)
  }
  { div8, h_div8, height, ratio, w_div8, width, }
}

///|
/// Animation information.
///
/// TPS (ticks per second) is computed as `tps_numerator / tps_denominator`, which means
/// `tps_denominator / tps_numerator` seconds per tick.
#derive(Debug)
pub(all) struct AnimationHeader {
  /// TPS numerator.
  mut tps_numerator : Int32
  /// TPS denominator.
  mut tps_denominator : Int32
  /// Number of loops, where 0 means it loops forever.
  mut num_loops : UInt32
  /// Whether keyframes in the image has their timecodes embedded.
  mut have_timecodes : Bool
}

///|
pub fn AnimationHeader::parse(
  bs : @bitstream.Bitstream,
) -> AnimationHeader raise @bitstream.JxlError {
  let tps_numerator = read_u32_int(
    bs,
    @bitstream.c(100),
    @bitstream.c(1000),
    @bitstream.cu(1, 10),
    @bitstream.cu(1, 30),
  )
  let tps_denominator = read_u32_int(
    bs,
    @bitstream.c(1),
    @bitstream.c(1001),
    @bitstream.cu(1, 8),
    @bitstream.cu(1, 10),
  )
  let num_loops = bs.read_u32(
    @bitstream.c(0),
    @bitstream.u(3),
    @bitstream.u(16),
    @bitstream.u(32),
  )
  let have_timecodes = bs.read_bool()
  { tps_numerator, tps_denominator, num_loops, have_timecodes, }
}

///|
#derive(Debug)
pub(all) struct Extensions {
  priv extension_bits : UInt64
}

///|
pub fn Extensions::default() -> Extensions {
  { extension_bits: 0, }
}

///|
pub fn Extensions::parse(
  bs : @bitstream.Bitstream,
) -> Extensions raise @bitstream.JxlError {
  let extension_bits = bs.read_u64()
  let mut bits = extension_bits
  let extension_data_bitlen : Array[UInt64] = []
  for _extension_idx in 0..<64 {
    if (bits & 1) != 0 {
      extension_data_bitlen.push(bs.read_u64())
    }
    bits = bits >> 1
  }
  for len in extension_data_bitlen {
    skip_bits_u64(bs, len)
  }
  { extension_bits, }
}

///|
/// `skip_bits(len as usize)` for a 64-bit length. Lengths beyond the remaining bits fail
/// with `Eof` exactly like upstream (all remaining bits are consumed first).
fn skip_bits_u64(
  bs : @bitstream.Bitstream,
  len : UInt64,
) -> Unit raise @bitstream.JxlError {
  let left = bs.bits_left()
  if len > left.to_uint64() {
    bs.skip_bits(left + 1)
  } else {
    bs.skip_bits(len.to_int())
  }
}

///|
/// Returns whether the image is grayscale.
pub fn ImageMetadata::grayscale(self : ImageMetadata) -> Bool {
  self.colour_encoding.colour_space() == Grey
}

///|
/// Returns the index of the first alpha channel in the image.
pub fn ImageMetadata::alpha(self : ImageMetadata) -> Int32? {
  for i, info in self.ec_info {
    if info.ty is Alpha(..) {
      return Some(i)
    }
  }
  None
}

///|
/// Returns where the given coordinate will be placed after the orientation is applied.
pub fn ImageMetadata::apply_orientation(
  self : ImageMetadata,
  width : Int32,
  height : Int32,
  left : Int32,
  top : Int32,
  inverse : Bool,
) -> (Int32, Int32, Int32, Int32) {
  let (left, top) = match self.orientation {
    1 => (left, top)
    2 => (width - left - 1, top)
    3 => (width - left - 1, height - top - 1)
    4 => (left, height - top - 1)
    5 => (top, left)
    6 if inverse => (top, width - left - 1)
    6 => (height - top - 1, left)
    7 => (height - top - 1, width - left - 1)
    8 if inverse => (height - top - 1, left)
    8 => (top, width - left - 1)
    _ => abort("unreachable")
  }
  let (width, height) = match self.orientation {
    1..<=4 => (width, height)
    5..<=8 => (height, width)
    _ => abort("unreachable")
  }
  (width, height, left, top)
}

///|
/// Information about an extra channel.
#derive(Debug)
pub(all) struct ExtraChannelInfo {
  /// Type and associated parameters of the channel.
  mut ty : ExtraChannelType
  /// Bit depth information about the channel.
  mut bit_depth : BitDepth
  /// `dim_shift` used to decode Modular image.
  mut dim_shift : Int32
  /// Name of the channel.
  mut name : String
}

///|
pub fn ExtraChannelInfo::default() -> ExtraChannelInfo {
  {
    ty: ExtraChannelType::default(),
    bit_depth: BitDepth::default(),
    dim_shift: 0,
    name: "",
  }
}

///|
pub fn ExtraChannelInfo::parse(
  bs : @bitstream.Bitstream,
) -> ExtraChannelInfo raise @bitstream.JxlError {
  let default_alpha_channel = bs.read_bool()
  if default_alpha_channel {
    return ExtraChannelInfo::default()
  }
  let ty_id = bs.read_enum_raw()
  match ty_id {
    0..<=6 | 15 | 16 => ()
    _ => raise @bitstream.InvalidEnum("jxl_image::ExtraChannelTypeRaw", ty_id)
  }
  let bit_depth = BitDepth::parse(bs)
  let dim_shift = read_u32_int(
    bs,
    @bitstream.c(0),
    @bitstream.c(3),
    @bitstream.c(4),
    @bitstream.cu(1, 3),
  )
  let name = @bitstream.read_name(bs)
  let ty : ExtraChannelType = match ty_id {
    0 => Alpha(alpha_associated=bs.read_bool())
    1 => Depth
    2 => {
      let red = bs.read_f16_as_f32()
      let green = bs.read_f16_as_f32()
      let blue = bs.read_f16_as_f32()
      let solidity = bs.read_f16_as_f32()
      SpotColour(red~, green~, blue~, solidity~)
    }
    3 => SelectionMask
    4 => Black
    5 =>
      Cfa(
        cfa_channel=read_u32_int(
          bs,
          @bitstream.c(1),
          @bitstream.u(2),
          @bitstream.cu(3, 4),
          @bitstream.cu(19, 8),
        ),
      )
    6 => Thermal
    15 => NonOptional
    _ => Optional
  }
  { ty, bit_depth, dim_shift, name, }
}

///|
/// An independent copy (Rust `Clone`).
pub fn ExtraChannelInfo::clone(self : ExtraChannelInfo) -> ExtraChannelInfo {
  {
    ty: self.ty,
    bit_depth: self.bit_depth,
    dim_shift: self.dim_shift,
    name: self.name,
  }
}

///|
/// Returns whether this is an alpha channel.
pub fn ExtraChannelInfo::is_alpha(self : ExtraChannelInfo) -> Bool {
  self.ty is Alpha(..)
}

///|
/// Returns whether the alpha channel has premultiplied semantics.
pub fn ExtraChannelInfo::alpha_associated(self : ExtraChannelInfo) -> Bool? {
  match self.ty {
    Alpha(alpha_associated~) => Some(alpha_associated)
    _ => None
  }
}

///|
/// Returns whether this is a black channel of a CMYK image.
pub fn ExtraChannelInfo::is_black(self : ExtraChannelInfo) -> Bool {
  self.ty == Black
}

///|
/// Type of an extra channel.
#derive(Debug, Eq)
pub(all) enum ExtraChannelType {
  Alpha(alpha_associated~ : Bool)
  Depth
  SpotColour(red~ : Float, green~ : Float, blue~ : Float, solidity~ : Float)
  SelectionMask
  Black
  Cfa(cfa_channel~ : Int32)
  Thermal
  NonOptional
  Optional
}

///|
pub fn ExtraChannelType::default() -> ExtraChannelType {
  Alpha(alpha_associated=false)
}

///|
/// Bit depth information.
#derive(Debug, Eq)
pub(all) enum BitDepth {
  /// Modular image samples represent integer values, where the range
  /// `0..=(1 << bits_per_sample) - 1` corresponds to \[0.0, 1.0\], scaled linearly.
  ///
  /// The value outside of the \[0.0, 1.0\] range is *not* clamped.
  IntegerSample(bits_per_sample~ : Int32)
  /// Modular image samples represent bitcast of floating point values with a sign bit,
  /// `exp_bits` exponential bits, and the remaining mantissa bits.
  FloatSample(bits_per_sample~ : Int32, exp_bits~ : Int32)
}

///|
pub fn BitDepth::default() -> BitDepth {
  IntegerSample(bits_per_sample=8)
}

///|
pub fn BitDepth::bits_per_sample(self : BitDepth) -> Int32 {
  match self {
    IntegerSample(bits_per_sample~) => bits_per_sample
    FloatSample(bits_per_sample~, ..) => bits_per_sample
  }
}

///|
/// Parses the given Modular image sample to a `Float`.
/// Note: This function can return non-finite values.
pub fn BitDepth::parse_integer_sample(self : BitDepth, sample : Int32) -> Float {
  match self {
    IntegerSample(bits_per_sample~) => {
      let div = (1 << bits_per_sample) - 1
      Float::from_int(sample) / Float::from_int(div)
    }
    FloatSample(bits_per_sample~, exp_bits~) => {
      let sample = sample.reinterpret_as_uint()
      let bits_per_sample = bits_per_sample.reinterpret_as_uint()
      let exp_bits = exp_bits.reinterpret_as_uint()
      let mantissa_bits = bits_per_sample - exp_bits - 1
      let mantissa_mask = (1U << mantissa_bits.reinterpret_as_int()) - 1
      let exp_mask = ((1U << (bits_per_sample - 1).reinterpret_as_int()) - 1) ^
        mantissa_mask
      let is_signed = (
          sample & (1U << (bits_per_sample - 1).reinterpret_as_int())
        ) !=
        0
      let mantissa = sample & mantissa_mask
      let exp = ((sample & exp_mask) >> mantissa_bits.reinterpret_as_int()).reinterpret_as_int()
      let exp = exp - ((1 << (exp_bits - 1).reinterpret_as_int()) - 1)

      // TODO: handle subnormal values.
      let f32_mantissa_bits = 23U
      let mantissa = if mantissa_bits < f32_mantissa_bits {
        mantissa << (f32_mantissa_bits - mantissa_bits).reinterpret_as_int()
      } else if mantissa_bits > f32_mantissa_bits {
        mantissa >> (mantissa_bits - f32_mantissa_bits).reinterpret_as_int()
      } else {
        mantissa
      }
      let exp = (exp + 127).reinterpret_as_uint()
      let sign : UInt32 = if is_signed { 1 } else { 0 }
      let bits = (sign << 31) |
        (exp << f32_mantissa_bits.reinterpret_as_int()) |
        mantissa
      Float::reinterpret_from_uint(bits)
    }
  }
}

///|
pub fn BitDepth::parse(
  bs : @bitstream.Bitstream,
) -> BitDepth raise @bitstream.JxlError {
  if bs.read_bool() {
    // float_sample
    let bits_per_sample = bs.read_u32(
      @bitstream.c(32),
      @bitstream.c(16),
      @bitstream.c(24),
      @bitstream.cu(1, 6),
    )
    let exp_bits = bs.read_bits(4) + 1
    if !(exp_bits >= 2 && exp_bits <= 8) {
      raise @bitstream.ValidationFailed("Invalid exp_bits per float sample")
    }
    let mantissa_bits = bits_per_sample - (exp_bits + 1)
    if !(mantissa_bits >= 2 && mantissa_bits <= 23) {
      raise @bitstream.ValidationFailed(
        "Invalid mantissa_bits per float sample",
      )
    }
    FloatSample(
      bits_per_sample=bits_per_sample.reinterpret_as_int(),
      exp_bits=exp_bits.reinterpret_as_int(),
    )
  } else {
    let bits_per_sample = bs.read_u32(
      @bitstream.c(8),
      @bitstream.c(10),
      @bitstream.c(12),
      @bitstream.cu(1, 6),
    )
    if bits_per_sample > 31 {
      raise @bitstream.ValidationFailed("Invalid bits_per_sample")
    }
    IntegerSample(bits_per_sample=bits_per_sample.reinterpret_as_int())
  }
}
