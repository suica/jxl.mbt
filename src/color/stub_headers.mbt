// STUB: minimal mirror of the header/ICC half of jxl-color (owned by the
// color-headers port). Drop this file when the real one is merged.

///|
#derive(Eq, Debug)
pub(all) enum ColourSpace {
  Rgb
  Grey
  Xyb
  Unknown
}

///|
#derive(Eq, Debug)
pub(all) struct Customxy {
  x : Int32
  y : Int32
}

///|
pub fn Customxy::as_float(self : Customxy) -> FixedArray[Float] {
  [Float::from_int(self.x) / 1.0e6, Float::from_int(self.y) / 1.0e6]
}

///|
#derive(Eq, Debug)
pub(all) enum WhitePoint {
  D65
  Custom(Customxy)
  E
  Dci
}

///|
#derive(Eq, Debug)
pub(all) enum Primaries {
  Srgb
  Custom(red~ : Customxy, green~ : Customxy, blue~ : Customxy)
  Bt2100
  P3
}

///|
#derive(Eq, Debug)
pub(all) enum RenderingIntent {
  Perceptual
  Relative
  Saturation
  Absolute
}

///|
#derive(Eq, Debug)
pub(all) enum TransferFunction {
  Gamma(g~ : Int32, inverted~ : Bool)
  Bt709
  Unknown
  Linear
  Srgb
  Pq
  Dci
  Hlg
}

///|
#derive(Eq, Debug)
pub(all) struct EnumColourEncoding {
  colour_space : ColourSpace
  white_point : WhitePoint
  primaries : Primaries
  tf : TransferFunction
  rendering_intent : RenderingIntent
}

///|
pub fn EnumColourEncoding::xyb(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Xyb,
    rendering_intent,
    white_point: D65,
    primaries: Srgb,
    tf: Linear,
  }
}

///|
pub fn EnumColourEncoding::srgb(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    rendering_intent,
    white_point: D65,
    primaries: Srgb,
    tf: Srgb,
  }
}

///|
pub fn EnumColourEncoding::srgb_linear(
  rendering_intent : RenderingIntent,
) -> EnumColourEncoding {
  {
    colour_space: Rgb,
    rendering_intent,
    white_point: D65,
    primaries: Srgb,
    tf: Linear,
  }
}

///|
pub fn EnumColourEncoding::is_hdr(self : EnumColourEncoding) -> Bool {
  self.tf is (Pq | Hlg)
}

///|
#derive(Debug)
pub(all) enum ColourEncoding {
  Enum(EnumColourEncoding)
  IccProfile(ColourSpace)
}

///|
pub fn ColourEncoding::want_icc(self : ColourEncoding) -> Bool {
  self is IccProfile(_)
}

///|
#derive(Debug)
pub(all) struct ToneMapping {
  all_default : Bool
  intensity_target : Float
  min_nits : Float
  relative_to_max_display : Bool
  linear_below : Float
}

///|
#derive(Debug)
pub(all) struct OpsinInverseMatrix {
  all_default : Bool
  inv_mat : FixedArray[FixedArray[Float]]
  opsin_bias : FixedArray[Float]
  quant_bias : FixedArray[Float]
  quant_bias_numerator : Float
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
pub let primaries_srgb : FixedArray[FixedArray[Float]] = [
  [0.639998686, 0.330010138],
  [0.300003784, 0.600003357],
  [0.150002046, 0.059997204],
]

///|
pub trait AsIlluminant {
  fn as_illuminant(Self) -> FixedArray[Float]
}

///|
pub trait AsPrimaries {
  fn as_primaries(Self) -> FixedArray[FixedArray[Float]]
}

///|
pub impl AsIlluminant for WhitePoint with fn as_illuminant(self) {
  match self {
    D65 => [0.3127, 0.329]
    Custom(xy) => xy.as_float()
    E => [1.0 / 3.0, 1.0 / 3.0]
    Dci => [0.314, 0.351]
  }
}

///|
pub impl AsPrimaries for Primaries with fn as_primaries(self) {
  match self {
    Srgb => primaries_srgb
    Custom(red~, green~, blue~) =>
      [red.as_float(), green.as_float(), blue.as_float()]
    Bt2100 => [[0.708, 0.292], [0.170, 0.797], [0.131, 0.046]]
    P3 => [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]]
  }
}

///|
let mat_bradford : FixedArray[Float] = [
  0.8951, 0.2664, -0.1614, -0.7502, 1.7135, 0.0367, 0.0389, -0.0685, 1.0296,
]

///|
let mat_bradford_inv : FixedArray[Float] = [
  0.9869929, -0.1470543, 0.1599627, 0.4323053, 0.5183603, 0.0492912, -0.0085287,
  0.0400428, 0.9684867,
]

///|
pub fn matmul3(
  a : FixedArray[Float],
  b : FixedArray[Float],
) -> FixedArray[Float] {
  let out = FixedArray::make(9, (0.0 : Float))
  for r in 0..<3 {
    for c in 0..<3 {
      out[r * 3 + c] = a[r * 3] * b[c] +
        a[r * 3 + 1] * b[3 + c] +
        a[r * 3 + 2] * b[6 + c]
    }
  }
  out
}

///|
pub fn matmul3vec(
  a : FixedArray[Float],
  b : FixedArray[Float],
) -> FixedArray[Float] {
  [
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
    a[3] * b[0] + a[4] * b[1] + a[5] * b[2],
    a[6] * b[0] + a[7] * b[1] + a[8] * b[2],
  ]
}

///|
pub fn matinv(mat : FixedArray[Float]) -> FixedArray[Float] {
  let det = mat[0] * (mat[4] * mat[8] - mat[5] * mat[7]) +
    mat[1] * (mat[5] * mat[6] - mat[3] * mat[8]) +
    mat[2] * (mat[3] * mat[7] - mat[4] * mat[6])
  [
    (mat[4] * mat[8] - mat[5] * mat[7]) / det,
    (mat[7] * mat[2] - mat[8] * mat[1]) / det,
    (mat[1] * mat[5] - mat[2] * mat[4]) / det,
    (mat[5] * mat[6] - mat[3] * mat[8]) / det,
    (mat[8] * mat[0] - mat[6] * mat[2]) / det,
    (mat[2] * mat[3] - mat[0] * mat[5]) / det,
    (mat[3] * mat[7] - mat[4] * mat[6]) / det,
    (mat[6] * mat[1] - mat[7] * mat[0]) / det,
    (mat[0] * mat[4] - mat[1] * mat[3]) / det,
  ]
}

///|
pub fn[I : AsIlluminant] illuminant_to_xyz(illuminant : I) -> FixedArray[Float] {
  let xy = illuminant.as_illuminant()
  let x = xy[0]
  let y = xy[1]
  [x / y, 1.0, (1.0 - x) / y - 1.0]
}

///|
pub fn[F : AsIlluminant, T : AsIlluminant] adapt_mat(
  from_illuminant : F,
  to_illuminant : T,
) -> FixedArray[Float] {
  let from_w = illuminant_to_xyz(from_illuminant)
  let to_w = illuminant_to_xyz(to_illuminant)
  if from_w[0] == to_w[0] && from_w[1] == to_w[1] && from_w[2] == to_w[2] {
    return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
  }
  let from_lms = matmul3vec(mat_bradford, from_w)
  let to_lms = matmul3vec(mat_bradford, to_w)
  let mul : FixedArray[Float] = [
    to_lms[0] / from_lms[0],
    to_lms[1] / from_lms[1],
    to_lms[2] / from_lms[2],
  ]
  let multiplied = FixedArray::makei(9, idx => mat_bradford[idx] * mul[idx / 3])
  matmul3(mat_bradford_inv, multiplied)
}

///|
fn[P : AsPrimaries] stub_primaries_mat(primaries : P) -> FixedArray[Float] {
  let p = primaries.as_primaries()
  [
    p[0][0],
    p[1][0],
    p[2][0],
    p[0][1],
    p[1][1],
    p[2][1],
    1.0 - p[0][0] - p[0][1],
    1.0 - p[1][0] - p[1][1],
    1.0 - p[2][0] - p[2][1],
  ]
}

///|
pub fn[P : AsPrimaries, W : AsIlluminant] primaries_to_xyz_mat(
  primaries : P,
  wp : W,
) -> FixedArray[Float] {
  let primaries = stub_primaries_mat(primaries)
  let primaries_inv = matinv(primaries)
  let w_xyz = illuminant_to_xyz(wp)
  let mul = matmul3vec(primaries_inv, w_xyz)
  for idx in 0..<9 {
    primaries[idx] = primaries[idx] * mul[idx % 3]
  }
  primaries
}

///|
pub fn[P : AsPrimaries, W : AsIlluminant] xyz_to_primaries_mat(
  primaries : P,
  wp : W,
) -> FixedArray[Float] {
  let primaries = stub_primaries_mat(primaries)
  let primaries_inv = matinv(primaries)
  let w_xyz = illuminant_to_xyz(wp)
  let mul = matmul3vec(primaries_inv, w_xyz)
  for idx in 0..<9 {
    primaries_inv[idx] = primaries_inv[idx] / mul[idx / 3]
  }
  primaries_inv
}

///|
fn map_gamut_generic(
  rgb : FixedArray[Float],
  luminance : FixedArray[Float],
  saturation_factor : Float,
) -> FixedArray[Float] {
  let r = rgb[0]
  let g = rgb[1]
  let b = rgb[2]
  let y = r * luminance[0] + g * luminance[1] + b * luminance[2]
  let mut gray_saturation : Float = 0.0
  let mut gray_luminance : Float = 0.0
  for v in rgb {
    let v_sub_y = v - y
    let inv_v_sub_y = (1.0 : Float) /
      (if v_sub_y == 0.0 { 1.0 } else { v_sub_y })
    let v_over_v_sub_y = v * inv_v_sub_y
    gray_saturation = if v_sub_y >= 0.0 {
      gray_saturation
    } else {
      gray_saturation.max(v_over_v_sub_y)
    }
    gray_luminance = (if v_sub_y <= 0.0 {
      gray_saturation
    } else {
      v_over_v_sub_y - inv_v_sub_y
    }).max(gray_luminance)
  }
  let gm = saturation_factor * (gray_saturation - gray_luminance) +
    gray_luminance
  let gray_mix : Float = if gm < 0.0 {
    0.0
  } else if gm > 1.0 {
    1.0
  } else {
    gm
  }
  let mut max_color_val : Float = 1.0
  for v in rgb {
    max_color_val = v.max(max_color_val)
  }
  FixedArray::makei(3, i => (gray_mix * (y - rgb[i]) + rgb[i]) / max_color_val)
}

///|
pub(all) struct IccHeader {
  color_space : Bytes
  rendering_intent : RenderingIntent
}

///|
pub(all) struct IccProfile {
  header : IccHeader
}

///|
pub fn IccProfile::color_space(self : IccProfile) -> ColourSpace {
  let cs = self.header.color_space
  if cs == b"RGB " || cs == b"CMYK" {
    Rgb
  } else if cs == b"GRAY" {
    Grey
  } else {
    Unknown
  }
}

///|
pub fn IccProfile::is_cmyk(self : IccProfile) -> Bool {
  self.header.color_space == b"CMYK"
}

///|
fn parse_icc_raw(profile : Bytes) -> IccProfile raise @bitstream.JxlError {
  if profile.length() < 128 {
    raise @bitstream.Color("IccParseFailure: profile too short")
  }
  let size = (profile[0].to_int() << 24) |
    (profile[1].to_int() << 16) |
    (profile[2].to_int() << 8) |
    profile[3].to_int()
  if profile.length() != size {
    raise @bitstream.Color("IccParseFailure: profile size mismatch")
  }
  let ri = match profile[67] {
    0 => Perceptual
    1 => Relative
    2 => Saturation
    _ => Absolute
  }
  { header: { color_space: profile[16:20].to_owned(), rendering_intent: ri, }, }
}

///|
fn parse_icc(_profile : Bytes) -> EnumColourEncoding raise @bitstream.JxlError {
  raise @bitstream.Color("UnsupportedIccProfile")
}

///|
pub fn colour_encoding_to_icc(_encoding : EnumColourEncoding) -> Bytes {
  b"STUBICC"
}
