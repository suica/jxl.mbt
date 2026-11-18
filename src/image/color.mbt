// Types related to color encoding (port of jxl-image/src/color.rs).

///|
/// Color encoding, either represented by enum values, or a signal of existence of ICC profile.
#derive(Debug, Eq)
pub(all) enum ColourEncoding {
  /// Color encoding is represented by enum values.
  Enum(EnumColourEncoding)
  /// Color encoding is described by embedded (external) ICC profile.
  IccProfile(ColourSpace)
}

///|
pub fn ColourEncoding::default() -> ColourEncoding {
  Enum(EnumColourEncoding::default())
}

///|
pub fn ColourEncoding::parse(
  bs : @bitstream.Bitstream,
) -> ColourEncoding raise @bitstream.JxlError {
  let all_default = bs.read_bool()
  if all_default {
    return ColourEncoding::default()
  }
  let want_icc = bs.read_bool()
  let colour_space = ColourSpace::from_raw(bs.read_enum_raw())
  if want_icc {
    return IccProfile(colour_space)
  }
  let white_point = if colour_space == Xyb {
    WhitePoint::D65
  } else {
    WhitePoint::parse(bs)
  }
  let primaries = if colour_space is (Xyb | Grey) {
    Primaries::Srgb
  } else {
    Primaries::parse(bs)
  }
  let tf = TransferFunction::parse(bs)
  let rendering_intent = RenderingIntent::from_raw(bs.read_enum_raw())
  Enum({ colour_space, white_point, primaries, tf, rendering_intent, })
}

///|
pub fn ColourEncoding::colour_space(self : ColourEncoding) -> ColourSpace {
  match self {
    Enum(e) => e.colour_space
    IccProfile(x) => x
  }
}

///|
pub fn ColourEncoding::want_icc(self : ColourEncoding) -> Bool {
  self is IccProfile(_)
}

///|
/// Returns whether this `ColourEncoding` represents the sRGB colorspace.
pub fn ColourEncoding::is_srgb(self : ColourEncoding) -> Bool {
  match self {
    Enum(e) => e.is_srgb()
    _ => false
  }
}

///|
pub fn ColourEncoding::is_srgb_gamut(self : ColourEncoding) -> Bool {
  match self {
    Enum(e) => e.is_srgb_gamut()
    _ => false
  }
}

///|
/// Returns the CICP tag which represents this `ColourEncoding`.
pub fn ColourEncoding::cicp(self : ColourEncoding) -> FixedArray[Int32]? {
  match self {
    Enum(e) => e.cicp()
    _ => None
  }
}

///|
/// "Enum color encoding" represented by JPEG XL enum values.
#derive(Debug, Eq)
pub(all) struct EnumColourEncoding {
  mut colour_space : ColourSpace
  mut white_point : WhitePoint
  mut primaries : Primaries
  mut tf : TransferFunction
  mut rendering_intent : RenderingIntent
}

///|
pub fn EnumColourEncoding::default() -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: Srgb,
    tf: Srgb,
    rendering_intent: Relative,
  }
}

///|
/// An independent copy (Rust `Clone`).
pub fn EnumColourEncoding::clone(
  self : EnumColourEncoding,
) -> EnumColourEncoding {
  {
    colour_space: self.colour_space,
    white_point: self.white_point,
    primaries: self.primaries,
    tf: self.tf,
    rendering_intent: self.rendering_intent,
  }
}

///|
/// An independent copy (Rust `Clone`).
pub fn ColourEncoding::clone(self : ColourEncoding) -> ColourEncoding {
  match self {
    Enum(e) => Enum(e.clone())
    IccProfile(x) => IccProfile(x)
  }
}

///|
/// Creates an XYB color encoding.
pub fn EnumColourEncoding::xyb(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Xyb,
    rendering_intent,
    // Below are ignored for XYB color encoding
    white_point: D65,
    primaries: Srgb,
    tf: Linear,
  }
}

///|
/// Creates an sRGB color encoding.
pub fn EnumColourEncoding::srgb(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: Srgb,
    tf: Srgb,
    rendering_intent,
  }
}

///|
/// Creates an sRGB color encoding with gamma of 2.2 (instead of sRGB transfer curve).
pub fn EnumColourEncoding::srgb_gamma22(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: Srgb,
    tf: Gamma(g=22000000, inverted=false),
    rendering_intent,
  }
}

///|
/// Creates an sRGB color encoding with linear transfer (instead of sRGB transfer curve).
pub fn EnumColourEncoding::srgb_linear(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: Srgb,
    tf: Linear,
    rendering_intent,
  }
}

///|
/// Creates a grayscale color encoding with white point of D65 and sRGB transfer curve.
pub fn EnumColourEncoding::gray_srgb(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Grey,
    white_point: D65,
    primaries: Srgb,
    tf: Srgb,
    rendering_intent,
  }
}

///|
/// Creates a grayscale color encoding with white point of D65 and gamma of 2.2.
pub fn EnumColourEncoding::gray_gamma22(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Grey,
    white_point: D65,
    primaries: Srgb,
    tf: Gamma(g=22000000, inverted=false),
    rendering_intent,
  }
}

///|
/// Creates a BT.709 color encoding.
pub fn EnumColourEncoding::bt709(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: Srgb,
    tf: Bt709,
    rendering_intent,
  }
}

///|
/// Creates a DCI-P3 color encoding.
pub fn EnumColourEncoding::dci_p3(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: Dci,
    primaries: P3,
    tf: Dci,
    rendering_intent,
  }
}

///|
/// Creates a Display P3 color encoding.
pub fn EnumColourEncoding::display_p3(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: P3,
    tf: Srgb,
    rendering_intent,
  }
}

///|
/// Creates a Display P3 color encoding with PQ transfer function.
pub fn EnumColourEncoding::display_p3_pq(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: P3,
    tf: Pq,
    rendering_intent,
  }
}

///|
/// Creates a BT.2100 color encoding with PQ transfer function.
pub fn EnumColourEncoding::bt2100_pq(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: Bt2100,
    tf: Pq,
    rendering_intent,
  }
}

///|
/// Creates a BT.2100 color encoding with hybrid log-gamma transfer function.
pub fn EnumColourEncoding::bt2100_hlg(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    white_point: D65,
    primaries: Bt2100,
    tf: Hlg,
    rendering_intent,
  }
}

///|
/// Returns whether the color encoding represents the sRGB colorspace.
pub fn EnumColourEncoding::is_srgb(self : EnumColourEncoding) -> Bool {
  self.colour_space is Rgb &&
  self.white_point is D65 &&
  self.primaries is Srgb &&
  self.tf is Srgb
}

///|
/// Returns whether color gamut of the color encoding equals to sRGB (BT.709), and white point
/// equals to D65.
pub fn EnumColourEncoding::is_srgb_gamut(self : EnumColourEncoding) -> Bool {
  self.colour_space is Rgb && self.white_point is D65 && self.primaries is Srgb
}

///|
/// Returns whether transfer function of the color encoding is capable of encoding HDR signals.
pub fn EnumColourEncoding::is_hdr(self : EnumColourEncoding) -> Bool {
  self.tf is (Pq | Hlg)
}

///|
/// Returns the CICP tag which represents this color encoding.
pub fn EnumColourEncoding::cicp(
  self : EnumColourEncoding,
) -> FixedArray[Int32]? {
  match (self.primaries.cicp(), self.tf.cicp()) {
    (Some(primaries), Some(tf)) => Some([primaries, tf, 0, 1])
    _ => None
  }
}

///|
/// Custom xy-chromaticity coordinate.
///
/// Coordinate values are scaled by `1e6` (`1_000_000`).
#derive(Debug, Eq)
pub(all) struct Customxy {
  x : Int32
  y : Int32
}

///|
pub fn Customxy::parse(
  bs : @bitstream.Bitstream,
) -> Customxy raise @bitstream.JxlError {
  let x = read_customxy_component(bs)
  let y = read_customxy_component(bs)
  { x, y, }
}

///|
fn read_customxy_component(
  bs : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  @bitstream.unpack_signed(
    bs.read_u32(
      @bitstream.u(19),
      @bitstream.cu(524288, 19),
      @bitstream.cu(1048576, 20),
      @bitstream.cu(2097152, 21),
    ),
  )
}

///|
/// Returns the xy-chromaticity coordinate as floating point values.
pub fn Customxy::as_float(self : Customxy) -> FixedArray[Float] {
  [Float::from_int(self.x) / 1.0e6, Float::from_int(self.y) / 1.0e6]
}

///|
/// HDR tone mapping metadata.
#derive(Debug)
pub(all) struct ToneMapping {
  all_default : Bool
  intensity_target : Float
  min_nits : Float
  relative_to_max_display : Bool
  linear_below : Float
}

///|
pub fn ToneMapping::default() -> ToneMapping {
  {
    all_default: true,
    intensity_target: 255.0,
    min_nits: 0.0,
    relative_to_max_display: false,
    linear_below: 0.0,
  }
}

///|
pub fn ToneMapping::parse(
  bs : @bitstream.Bitstream,
) -> ToneMapping raise @bitstream.JxlError {
  let all_default = bs.read_bool()
  if all_default {
    return ToneMapping::default()
  }
  let intensity_target = bs.read_f16_as_f32()
  let min_nits = bs.read_f16_as_f32()
  let relative_to_max_display = bs.read_bool()
  let linear_below = bs.read_f16_as_f32()
  {
    all_default,
    intensity_target,
    min_nits,
    relative_to_max_display,
    linear_below,
  }
}

///|
/// Color space type.
#derive(Debug, Eq)
pub(all) enum ColourSpace {
  /// Tristimulus RGB.
  ///
  /// This includes CMYK; in that case, there is an extra channel of type `Black`, ICC profile is
  /// embedded in the image, and the profile describes an CMYK color space.
  Rgb
  /// Grayscale; luminance only.
  Grey
  /// XYB, an absolute color space.
  Xyb
  /// Unknown color space.
  Unknown
}

///|
pub fn ColourSpace::default() -> ColourSpace {
  Rgb
}

///|
pub fn ColourSpace::from_raw(
  value : UInt32,
) -> ColourSpace raise @bitstream.JxlError {
  match value {
    0 => Rgb
    1 => Grey
    2 => Xyb
    3 => Unknown
    _ => raise @bitstream.InvalidEnum("ColourSpace", value)
  }
}

///|
pub fn ColourSpace::to_raw(self : ColourSpace) -> Int32 {
  match self {
    Rgb => 0
    Grey => 1
    Xyb => 2
    Unknown => 3
  }
}

///|
/// White point.
#derive(Debug, Eq)
pub(all) enum WhitePoint {
  /// CIE Standard Illuminant D65.
  D65
  /// Custom white point.
  Custom(Customxy)
  /// CIE Standard Illuminant E.
  E
  /// DCI-P3 white point (SMPTE ST 428-1).
  Dci
}

///|
pub fn WhitePoint::default() -> WhitePoint {
  D65
}

///|
pub fn WhitePoint::parse(
  bs : @bitstream.Bitstream,
) -> WhitePoint raise @bitstream.JxlError {
  let d = bs.read_enum_raw()
  match d {
    1 => D65
    10 => E
    11 => Dci
    2 => Custom(Customxy::parse(bs))
    _ => raise @bitstream.InvalidEnum("WhitePointDiscriminator", d)
  }
}

///|
/// RGB primaries.
#derive(Debug, Eq)
pub(all) enum Primaries {
  /// sRGB primaries (same as BT.709).
  Srgb
  /// Custom RGB primaries.
  Custom(red~ : Customxy, green~ : Customxy, blue~ : Customxy)
  /// BT.2100 primaries (same as BT.2020).
  Bt2100
  /// DCI-P3 primaries.
  P3
}

///|
pub fn Primaries::default() -> Primaries {
  Srgb
}

///|
pub fn Primaries::parse(
  bs : @bitstream.Bitstream,
) -> Primaries raise @bitstream.JxlError {
  let d = bs.read_enum_raw()
  match d {
    1 => Srgb
    9 => Bt2100
    11 => P3
    2 => {
      let red = Customxy::parse(bs)
      let green = Customxy::parse(bs)
      let blue = Customxy::parse(bs)
      Custom(red~, green~, blue~)
    }
    _ => raise @bitstream.InvalidEnum("PrimariesDiscriminator", d)
  }
}

///|
/// Returns the CICP value of the primaries, if there is any.
pub fn Primaries::cicp(self : Primaries) -> Int32? {
  match self {
    Srgb => Some(1)
    Custom(..) => None
    Bt2100 => Some(9)
    P3 => Some(11)
  }
}

///|
/// Rendering intent, defined by ICC specification.
#derive(Debug, Eq)
pub(all) enum RenderingIntent {
  /// Perceptual; vendor-specific.
  Perceptual
  /// Media-relative; colorimetric.
  Relative
  /// Saturation; vendor-specific.
  Saturation
  /// ICC-absolute; colorimetric.
  Absolute
}

///|
pub fn RenderingIntent::default() -> RenderingIntent {
  Relative
}

///|
pub fn RenderingIntent::from_raw(
  value : UInt32,
) -> RenderingIntent raise @bitstream.JxlError {
  match value {
    0 => Perceptual
    1 => Relative
    2 => Saturation
    3 => Absolute
    _ => raise @bitstream.InvalidEnum("RenderingIntent", value)
  }
}

///|
/// The numeric value (`as u8`).
pub fn RenderingIntent::to_raw(self : RenderingIntent) -> Int32 {
  match self {
    Perceptual => 0
    Relative => 1
    Saturation => 2
    Absolute => 3
  }
}

///|
/// Transfer function (tone curve).
#derive(Debug, Eq)
pub(all) enum TransferFunction {
  /// Pure gamma curve.
  ///
  /// `g`: gamma value, scaled by `1e7` (`10_000_000`).
  /// `inverted`: whether the gamma value is inverted. If `true`, `g <= 10_000_000`.
  Gamma(g~ : Int32, inverted~ : Bool)
  /// BT.709 transfer function.
  Bt709
  /// Unknown transfer function.
  Unknown
  /// Linear (gamma of 1).
  Linear
  /// sRGB transfer function.
  Srgb
  /// Perceptual quantizer (HDR).
  Pq
  /// DCI transfer function (gamma of 2.6).
  Dci
  /// Hybrid log-gamma (HDR).
  Hlg
}

///|
pub fn TransferFunction::default() -> TransferFunction {
  Srgb
}

///|
pub fn TransferFunction::from_raw(
  value : UInt32,
) -> TransferFunction raise @bitstream.JxlError {
  match value {
    1 => Bt709
    2 => Unknown
    8 => Linear
    13 => Srgb
    16 => Pq
    17 => Dci
    18 => Hlg
    _ => raise @bitstream.InvalidEnum("TransferFunction", value)
  }
}

///|
pub fn TransferFunction::parse(
  bs : @bitstream.Bitstream,
) -> TransferFunction raise @bitstream.JxlError {
  let has_gamma = bs.read_bool()
  if has_gamma {
    let gamma = bs.read_bits_int(24)
    Gamma(g=gamma, inverted=true)
  } else {
    TransferFunction::from_raw(bs.read_enum_raw())
  }
}

///|
/// Returns the CICP value of transfer function, if there is any.
pub fn TransferFunction::cicp(self : TransferFunction) -> Int32? {
  match self {
    Gamma(..) => None
    Bt709 => Some(1)
    Unknown => None
    Linear => Some(8)
    Srgb => Some(13)
    Pq => Some(16)
    Dci => Some(17)
    Hlg => Some(18)
  }
}

///|
/// Opsin inverse metadata.
#derive(Debug)
pub(all) struct OpsinInverseMatrix {
  all_default : Bool
  inv_mat : FixedArray[FixedArray[Float]]
  opsin_bias : FixedArray[Float]
  quant_bias : FixedArray[Float]
  quant_bias_numerator : Float
}

///|
pub fn OpsinInverseMatrix::default() -> OpsinInverseMatrix {
  {
    all_default: true,
    inv_mat: [
      [11.031566901960783, -9.866943921568629, -0.16462299647058826],
      [-3.254147380392157, 4.418770392156863, -0.16462299647058826],
      [-3.6588512862745097, 2.7129230470588235, 1.9459282392156863],
    ],
    opsin_bias: [
      -0.0037930732552754493, -0.0037930732552754493, -0.0037930732552754493,
    ],
    quant_bias: [
      (1.0 : Float) - 0.05465007330715401,
      (1.0 : Float) - 0.07005449891748593,
      (1.0 : Float) - 0.049935103337343655,
    ],
    quant_bias_numerator: 0.145,
  }
}

///|
pub fn OpsinInverseMatrix::parse(
  bs : @bitstream.Bitstream,
) -> OpsinInverseMatrix raise @bitstream.JxlError {
  let all_default = bs.read_bool()
  if all_default {
    return OpsinInverseMatrix::default()
  }
  let inv_mat : FixedArray[FixedArray[Float]] = FixedArray::makei(3, _ => {
    [0.0, 0.0, 0.0]
  })
  for i in 0..<3 {
    for j in 0..<3 {
      inv_mat[i][j] = bs.read_f16_as_f32()
    }
  }
  let opsin_bias : FixedArray[Float] = [0.0, 0.0, 0.0]
  for i in 0..<3 {
    opsin_bias[i] = bs.read_f16_as_f32()
  }
  let quant_bias : FixedArray[Float] = [0.0, 0.0, 0.0]
  for i in 0..<3 {
    quant_bias[i] = bs.read_f16_as_f32()
  }
  let quant_bias_numerator = bs.read_f16_as_f32()
  { all_default, inv_mat, opsin_bias, quant_bias, quant_bias_numerator, }
}
