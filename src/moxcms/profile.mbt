// Port of moxcms 0.9.0 `profile.rs` (types and `ColorProfile::new_from_slice`).

///|
const MAX_PROFILE_SIZE : Int32 = 1024 * 1024 * 10

///|
/// `size_of::<ProfileHeader>()` (repr(C), 132 bytes).
const PROFILE_HEADER_SIZE : Int32 = 132

///|
#derive(Eq, Debug, Compare)
pub(all) enum ProfileVersion {
  V2_0
  V2_1
  V2_2
  V2_3
  V2_4
  V4_0
  V4_1
  V4_2
  V4_3
  V4_4
  Unknown
}

///|
fn ProfileVersion::try_from(value : UInt32) -> ProfileVersion raise CmsError {
  match value {
    0x02000000 => return V2_0
    0x02100000 => return V2_1
    0x02200000 => return V2_2
    0x02300000 => return V2_3
    0x02400000 => return V2_4
    0x04000000 => return V4_0
    0x04100000 => return V4_1
    0x04200000 => return V4_2
    0x04300000 => return V4_3
    0x04400000 => return V4_4
    _ => ()
  }
  let major = (value >> 24) & 0xFF
  let minor = (value >> 20) & 0x0F
  match major {
    2 =>
      match minor {
        0 => V2_0
        1 => V2_1
        2 => V2_2
        3 => V2_3
        _ => V2_4
      }
    3 => V2_4
    4 =>
      match minor {
        0 => V4_0
        1 => V4_1
        2 => V4_2
        3 => V4_3
        _ => V4_4
      }
    _ => raise InvalidProfile
  }
}

///|
#derive(Eq, Debug)
pub(all) enum DataColorSpace {
  Xyz
  Lab
  Luv
  YCbr
  Yxy
  Rgb
  Gray
  Hsv
  Hls
  Cmyk
  Cmy
  Color2
  Color3
  Color4
  Color5
  Color6
  Color7
  Color8
  Color9
  Color10
  Color11
  Color12
  Color13
  Color14
  Color15
}

///|
fn DataColorSpace::try_from(value : UInt32) -> DataColorSpace raise CmsError {
  let table : FixedArray[(String, DataColorSpace)] = [
    ("XYZ ", Xyz),
    ("Lab ", Lab),
    ("Luv ", Luv),
    ("YCbr", YCbr),
    ("Yxy ", Yxy),
    ("RGB ", Rgb),
    ("GRAY", Gray),
    ("HSV ", Hsv),
    ("HLS ", Hls),
    ("CMYK", Cmyk),
    ("CMY ", Cmy),
    ("2CLR", Color2),
    ("3CLR", Color3),
    ("4CLR", Color4),
    ("5CLR", Color5),
    ("6CLR", Color6),
    ("7CLR", Color7),
    ("8CLR", Color8),
    ("9CLR", Color9),
    ("ACLR", Color10),
    ("BCLR", Color11),
    ("CCLR", Color12),
    ("DCLR", Color13),
    ("ECLR", Color14),
    ("FCLR", Color15),
  ]
  for entry in table {
    if fourcc(entry.0) == value {
      return entry.1
    }
  }
  raise InvalidProfile
}

///|
pub fn DataColorSpace::check_layout(
  self : DataColorSpace,
  layout : Layout,
) -> Unit raise CmsError {
  let unsupported = match self {
    Xyz => layout != Rgb
    Lab => layout != Rgb && layout != Rgba
    Luv => layout != Rgb
    YCbr => layout != Rgb
    Yxy => layout != Rgb
    Rgb => layout != Rgb && layout != Rgba
    Gray => layout != Gray && layout != GrayAlpha
    Hsv => layout != Rgb
    Hls => layout != Rgb
    Cmyk => layout != Rgba
    Cmy => layout != Rgb
    Color2 => layout != GrayAlpha
    Color3 => layout != Rgb
    Color4 => layout != Rgba
    Color5 => layout != Inks5
    Color6 => layout != Inks6
    Color7 => layout != Inks7
    Color8 => layout != Inks8
    Color9 => layout != Inks9
    Color10 => layout != Inks10
    Color11 => layout != Inks11
    Color12 => layout != Inks12
    Color13 => layout != Inks13
    Color14 => layout != Inks14
    Color15 => layout != Inks15
  }
  if unsupported {
    raise InvalidLayout
  }
}

///|
fn DataColorSpace::is_three_channels(self : DataColorSpace) -> Bool {
  match self {
    Xyz | Lab | Luv | YCbr | Yxy | Rgb | Hsv | Hls | Cmy | Color3 => true
    _ => false
  }
}

///|
#derive(Eq, Debug)
pub(all) enum ProfileClass {
  InputDevice
  DisplayDevice
  OutputDevice
  DeviceLink
  ColorSpace
  Abstract
  Named
}

///|
fn ProfileClass::try_from(value : UInt32) -> ProfileClass raise CmsError {
  let table : FixedArray[(String, ProfileClass)] = [
    ("scnr", InputDevice),
    ("mntr", DisplayDevice),
    ("prtr", OutputDevice),
    ("link", DeviceLink),
    ("spac", ColorSpace),
    ("abst", Abstract),
    ("nmcl", Named),
  ]
  for entry in table {
    if fourcc(entry.0) == value {
      return entry.1
    }
  }
  raise InvalidProfile
}

///|
/// `LutStore`: `Store8(Vec<u8>)` / `Store16(Vec<u16>)`, both kept as `Int`.
pub(all) enum LutStore {
  Store8(FixedArray[Int32])
  Store16(FixedArray[Int32])
}

///|
#derive(Eq, Debug)
pub(all) enum LutType {
  Lut8
  Lut16
  LutMab
  LutMba
}

///|
fn LutType::try_from(value : UInt32) -> LutType raise CmsError {
  if value == fourcc("mft1") {
    Lut8
  } else if value == fourcc("mft2") {
    Lut16
  } else if value == fourcc("mAB ") {
    LutMab
  } else if value == fourcc("mBA ") {
    LutMba
  } else {
    raise InvalidProfile
  }
}

///|
pub(all) struct LutDataType {
  num_input_channels : Int32
  num_output_channels : Int32
  num_clut_grid_points : Int32
  matrix : Matrix3d
  num_input_table_entries : Int32
  num_output_table_entries : Int32
  input_table : LutStore
  clut_table : LutStore
  output_table : LutStore
  lut_type : LutType
}

///|
fn LutDataType::has_same_kind(self : LutDataType) -> Bool {
  match (self.input_table, self.clut_table, self.output_table) {
    (Store8(_), Store8(_), Store8(_)) => true
    (Store16(_), Store16(_), Store16(_)) => true
    _ => false
  }
}

///|
pub(all) struct LutMultidimensionalType {
  num_input_channels : Int32
  num_output_channels : Int32
  grid_points : FixedArray[Int32]
  clut : LutStore?
  a_curves : Array[ToneReprCurve]
  b_curves : Array[ToneReprCurve]
  m_curves : Array[ToneReprCurve]
  matrix : Matrix3d
  bias : Vector3d
}

///|
pub(all) enum LutWarehouse {
  Lut(LutDataType)
  Multidimensional(LutMultidimensionalType)
}

///|
#derive(Eq, Debug)
pub(all) enum RenderingIntent {
  AbsoluteColorimetric
  Saturation
  RelativeColorimetric
  Perceptual
}

///|
fn RenderingIntent::try_from(value : UInt32) -> RenderingIntent {
  match value {
    0 => Perceptual
    1 => RelativeColorimetric
    2 => Saturation
    3 => AbsoluteColorimetric
    _ => Perceptual
  }
}

///|
#derive(Eq, Debug)
pub(all) struct ColorDateTime {
  year : Int32
  month : Int32
  day_of_the_month : Int32
  hours : Int32
  minutes : Int32
  seconds : Int32
}

///|
fn ColorDateTime::new_from_slice(
  slice : Bytes,
  start : Int32,
  len : Int32,
) -> ColorDateTime raise CmsError {
  if len != 12 {
    raise InvalidProfile
  }
  {
    year: be_u16(slice, start),
    month: be_u16(slice, start + 2),
    day_of_the_month: be_u16(slice, start + 4),
    hours: be_u16(slice, start + 6),
    minutes: be_u16(slice, start + 8),
    seconds: be_u16(slice, start + 10),
  }
}

///|
priv struct ProfileHeader {
  size : UInt32
  version : ProfileVersion
  profile_class : ProfileClass
  data_color_space : DataColorSpace
  pcs : DataColorSpace
  creation_date_time : ColorDateTime
  rendering_intent : RenderingIntent
  illuminant : Xyz
  tag_count : UInt32
}

///|
fn ProfileHeader::new_from_slice(slice : Bytes) -> ProfileHeader raise CmsError {
  if slice.length() < PROFILE_HEADER_SIZE {
    raise InvalidProfile
  }
  let size = be_u32(slice, 0)
  let version = ProfileVersion::try_from(be_u32(slice, 8))
  let profile_class = ProfileClass::try_from(be_u32(slice, 12))
  let data_color_space = DataColorSpace::try_from(be_u32(slice, 16))
  let pcs = DataColorSpace::try_from(be_u32(slice, 20))
  let creation_date_time = ColorDateTime::new_from_slice(slice, 24, 12)
  if be_u32(slice, 36) != fourcc("acsp") {
    raise InvalidProfile
  }
  let rendering_intent = RenderingIntent::try_from(be_u32(slice, 64))
  let illuminant = Xyz::{
    x: s15_fixed16_number_to_float(be_i32(slice, 68)),
    y: s15_fixed16_number_to_float(be_i32(slice, 72)),
    z: s15_fixed16_number_to_float(be_i32(slice, 76)),
  }
  let tag_count = be_u32(slice, 128)
  {
    size,
    version,
    profile_class,
    data_color_space,
    pcs,
    creation_date_time,
    rendering_intent,
    illuminant,
    tag_count,
  }
}

///|
#derive(Eq, Debug)
pub(all) struct CicpProfile {
  color_primaries : CicpColorPrimaries
  transfer_characteristics : TransferCharacteristics
  matrix_coefficients : MatrixCoefficients
  full_range : Bool
}

///|
#derive(Debug)
pub(all) struct LocalizableString {
  language : String
  country : String
  value : String
}

///|
#derive(Debug)
pub(all) struct DescriptionString {
  ascii_string : String
  unicode_language_code : UInt32
  unicode_string : String
  script_code_code : Int32
  mac_string : String
}

///|
#derive(Debug)
pub(all) enum ProfileText {
  PlainString(String)
  Localizable(Array[LocalizableString])
  Description(DescriptionString)
}

///|
#derive(Eq, Debug)
pub(all) enum StandardObserver {
  D50
  D65
  Unknown
}

///|
fn StandardObserver::from(value : UInt32) -> StandardObserver {
  if value == 1 {
    D50
  } else if value == 2 {
    D65
  } else {
    Unknown
  }
}

///|
#derive(Debug)
pub(all) struct ViewingConditions {
  illuminant : Xyz
  surround : Xyz
  observer : StandardObserver
}

///|
#derive(Eq, Debug)
pub(all) enum MeasurementGeometry {
  Unknown
  D45to45
  D0to0
}

///|
#derive(Eq, Debug)
pub(all) enum StandardIlluminant {
  Unknown
  D50
  D65
  D93
  F2
  D55
  A
  EquiPower
  F8
}

///|
fn StandardIlluminant::from(value : UInt32) -> StandardIlluminant {
  match value {
    1 => D50
    2 => D65
    3 => D93
    4 => F2
    5 => D55
    6 => A
    7 => EquiPower
    8 => F8
    _ => Unknown
  }
}

///|
#derive(Debug)
pub(all) struct Measurement {
  observer : StandardObserver
  backing : Xyz
  geometry : MeasurementGeometry
  flare : Float
  illuminant : StandardIlluminant
}

///|
/// `TechnologySignatures`, kept as its signature (`Unknown(u32)` included).
#derive(Eq, Debug)
pub(all) struct TechnologySignatures {
  signature : UInt32
}

///|
pub(all) struct ColorProfile {
  mut pcs : DataColorSpace
  mut color_space : DataColorSpace
  mut profile_class : ProfileClass
  mut rendering_intent : RenderingIntent
  mut red_colorant : Xyzd
  mut green_colorant : Xyzd
  mut blue_colorant : Xyzd
  mut white_point : Xyzd
  mut black_point : Xyzd?
  mut media_white_point : Xyzd?
  mut luminance : Xyzd?
  mut measurement : Measurement?
  mut red_trc : ToneReprCurve?
  mut green_trc : ToneReprCurve?
  mut blue_trc : ToneReprCurve?
  mut gray_trc : ToneReprCurve?
  mut cicp : CicpProfile?
  mut chromatic_adaptation : Matrix3d?
  mut lut_a_to_b_perceptual : LutWarehouse?
  mut lut_a_to_b_colorimetric : LutWarehouse?
  mut lut_a_to_b_saturation : LutWarehouse?
  mut lut_b_to_a_perceptual : LutWarehouse?
  mut lut_b_to_a_colorimetric : LutWarehouse?
  mut lut_b_to_a_saturation : LutWarehouse?
  mut gamut : LutWarehouse?
  mut copyright : ProfileText?
  mut description : ProfileText?
  mut device_manufacturer : ProfileText?
  mut device_model : ProfileText?
  mut char_target : ProfileText?
  mut viewing_conditions : ViewingConditions?
  mut viewing_conditions_description : ProfileText?
  mut technology : TechnologySignatures?
  mut calibration_date : ColorDateTime?
  mut creation_date_time : ColorDateTime
  mut version_internal : ProfileVersion
}

///|
pub(all) struct ParsingOptions {
  max_profile_size : Int32
  max_allowed_clut_size : Int32
  max_allowed_trc_size : Int32
}

///|
pub fn ParsingOptions::default() -> ParsingOptions {
  {
    max_profile_size: MAX_PROFILE_SIZE,
    max_allowed_clut_size: 10_000_000,
    max_allowed_trc_size: 40_000,
  }
}

///|
pub fn ColorProfile::version(self : ColorProfile) -> ProfileVersion {
  self.version_internal
}

///|
pub fn ColorProfile::new_from_slice(
  slice : Bytes,
) -> ColorProfile raise CmsError {
  ColorProfile::new_from_slice_with_options(slice, ParsingOptions::default())
}

///|
pub fn ColorProfile::new_from_slice_with_options(
  slice : Bytes,
  options : ParsingOptions,
) -> ColorProfile raise CmsError {
  let header = ProfileHeader::new_from_slice(slice)
  let tags_count = header.tag_count.to_uint64().reinterpret_as_int64()
  if slice.length() >= options.max_profile_size {
    raise InvalidProfile
  }
  let tags_end = tags_count * TAG_SIZE.to_int64() +
    PROFILE_HEADER_SIZE.to_int64()
  if slice.length().to_int64() < tags_end {
    raise InvalidProfile
  }
  let profile = ColorProfile::{
    pcs: header.pcs,
    color_space: header.data_color_space,
    profile_class: header.profile_class,
    rendering_intent: header.rendering_intent,
    red_colorant: Xyzd::default(),
    green_colorant: Xyzd::default(),
    blue_colorant: Xyzd::default(),
    white_point: header.illuminant.to_xyzd(),
    black_point: None,
    media_white_point: None,
    luminance: None,
    measurement: None,
    red_trc: None,
    green_trc: None,
    blue_trc: None,
    gray_trc: None,
    cicp: None,
    chromatic_adaptation: None,
    lut_a_to_b_perceptual: None,
    lut_a_to_b_colorimetric: None,
    lut_a_to_b_saturation: None,
    lut_b_to_a_perceptual: None,
    lut_b_to_a_colorimetric: None,
    lut_b_to_a_saturation: None,
    gamut: None,
    copyright: None,
    description: None,
    device_manufacturer: None,
    device_model: None,
    char_target: None,
    viewing_conditions: None,
    viewing_conditions_description: None,
    technology: None,
    calibration_date: None,
    creation_date_time: header.creation_date_time,
    version_internal: header.version,
  }
  let color_space = profile.color_space
  let count = tags_count.to_int()
  for t in 0..<count {
    let off = PROFILE_HEADER_SIZE + t * TAG_SIZE
    let tag_value = be_u32(slice, off)
    let tag_entry = be_u32(slice, off + 4).to_uint64().reinterpret_as_int64()
    let tag_size = be_u32(slice, off + 8).to_uint64().reinterpret_as_int64()
    // Just ignore unknown tags
    let tag = Tag::try_from(tag_value) catch { _ => continue }
    match tag {
      RedXyz =>
        if color_space == Rgb {
          profile.red_colorant = read_xyz_tag(slice, tag_entry, tag_size)
        }
      GreenXyz =>
        if color_space == Rgb {
          profile.green_colorant = read_xyz_tag(slice, tag_entry, tag_size)
        }
      BlueXyz =>
        if color_space == Rgb {
          profile.blue_colorant = read_xyz_tag(slice, tag_entry, tag_size)
        }
      RedToneReproduction =>
        if color_space == Rgb {
          profile.red_trc = read_trc_tag_s(slice, tag_entry, tag_size, options)
        }
      GreenToneReproduction =>
        if color_space == Rgb {
          profile.green_trc = read_trc_tag_s(
            slice, tag_entry, tag_size, options,
          )
        }
      BlueToneReproduction =>
        if color_space == Rgb {
          profile.blue_trc = read_trc_tag_s(slice, tag_entry, tag_size, options)
        }
      GreyToneReproduction =>
        if color_space == Gray {
          profile.gray_trc = read_trc_tag_s(slice, tag_entry, tag_size, options)
        }
      MediaWhitePoint =>
        profile.media_white_point = Some(
          read_xyz_tag(slice, tag_entry, tag_size),
        )
      Luminance =>
        profile.luminance = Some(read_xyz_tag(slice, tag_entry, tag_size))
      Measurement =>
        profile.measurement = read_meas_tag(slice, tag_entry, tag_size)
      CodeIndependentPoints =>
        if (
            profile.profile_class == InputDevice ||
            profile.profile_class == DisplayDevice
          ) &&
          (
            profile.color_space == Rgb ||
            profile.color_space == YCbr ||
            profile.color_space == Xyz
          ) {
          profile.cicp = read_cicp_tag(slice, tag_entry, tag_size)
        }
      ChromaticAdaptation =>
        profile.chromatic_adaptation = read_chad_tag(slice, tag_entry, tag_size)
      BlackPoint =>
        profile.black_point = Some(read_xyz_tag(slice, tag_entry, tag_size))
      DeviceToPcsLutPerceptual =>
        profile.lut_a_to_b_perceptual = read_lut_tag(
          slice, tag_entry, tag_size, options,
        )
      DeviceToPcsLutColorimetric =>
        profile.lut_a_to_b_colorimetric = read_lut_tag(
          slice, tag_entry, tag_size, options,
        )
      DeviceToPcsLutSaturation =>
        profile.lut_a_to_b_saturation = read_lut_tag(
          slice, tag_entry, tag_size, options,
        )
      PcsToDeviceLutPerceptual =>
        profile.lut_b_to_a_perceptual = read_lut_tag(
          slice, tag_entry, tag_size, options,
        )
      PcsToDeviceLutColorimetric =>
        profile.lut_b_to_a_colorimetric = read_lut_tag(
          slice, tag_entry, tag_size, options,
        )
      PcsToDeviceLutSaturation =>
        profile.lut_b_to_a_saturation = read_lut_tag(
          slice, tag_entry, tag_size, options,
        )
      Gamut => profile.gamut = read_lut_tag(slice, tag_entry, tag_size, options)
      Copyright =>
        profile.copyright = read_string_tag(slice, tag_entry, tag_size)
      ProfileDescription =>
        profile.description = read_string_tag(slice, tag_entry, tag_size)
      ViewingConditionsDescription =>
        profile.viewing_conditions_description = read_string_tag(
          slice, tag_entry, tag_size,
        )
      DeviceModel =>
        profile.device_model = read_string_tag(slice, tag_entry, tag_size)
      DeviceManufacturer =>
        profile.device_manufacturer = read_string_tag(
          slice, tag_entry, tag_size,
        )
      CharTarget =>
        profile.char_target = read_string_tag(slice, tag_entry, tag_size)
      Chromaticity => ()
      ObserverConditions =>
        profile.viewing_conditions = read_viewing_conditions(
          slice, tag_entry, tag_size,
        )
      Technology =>
        profile.technology = read_tech_tag(slice, tag_entry, tag_size)
      CalibrationDateTime =>
        profile.calibration_date = read_date_time_tag(
          slice, tag_entry, tag_size,
        )
    }
  }
  profile
}

///|
pub fn ColorProfile::colorant_matrix(self : ColorProfile) -> Matrix3d {
  {
    v: [
      [self.red_colorant.x, self.green_colorant.x, self.blue_colorant.x],
      [self.red_colorant.y, self.green_colorant.y, self.blue_colorant.y],
      [self.red_colorant.z, self.green_colorant.z, self.blue_colorant.z],
    ],
  }
}

///|
pub fn ColorProfile::rgb_to_xyz_matrix(self : ColorProfile) -> Matrix3d {
  self.colorant_matrix()
}

///|
pub fn ColorProfile::transform_matrix(
  self : ColorProfile,
  dest : ColorProfile,
) -> Matrix3d {
  let source = self.rgb_to_xyz_matrix()
  let dst = dest.rgb_to_xyz_matrix()
  let dest_inverse = dst.inverse()
  dest_inverse.mat_mul(source)
}

///|
fn ColorProfile::has_device_to_pcs_lut(self : ColorProfile) -> Bool {
  self.lut_a_to_b_perceptual is Some(_) ||
  self.lut_a_to_b_saturation is Some(_) ||
  self.lut_a_to_b_colorimetric is Some(_)
}

///|
fn ColorProfile::has_pcs_to_device_lut(self : ColorProfile) -> Bool {
  self.lut_b_to_a_perceptual is Some(_) ||
  self.lut_b_to_a_saturation is Some(_) ||
  self.lut_b_to_a_colorimetric is Some(_)
}

///|
/// `ColorProfile::is_matrix_shaper` (`transform.rs`).
pub fn ColorProfile::is_matrix_shaper(self : ColorProfile) -> Bool {
  self.color_space == Rgb &&
  self.red_colorant != Xyzd::default() &&
  self.green_colorant != Xyzd::default() &&
  self.blue_colorant != Xyzd::default() &&
  self.red_trc is Some(_) &&
  self.green_trc is Some(_) &&
  self.blue_trc is Some(_)
}

///|
/// Rust `Debug` name of the intent.
pub fn RenderingIntent::name(self : RenderingIntent) -> String {
  match self {
    AbsoluteColorimetric => "AbsoluteColorimetric"
    Saturation => "Saturation"
    RelativeColorimetric => "RelativeColorimetric"
    Perceptual => "Perceptual"
  }
}
