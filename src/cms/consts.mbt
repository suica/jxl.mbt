// Constants mirroring lcms2.h / lcms2_internal.h (Little CMS 2.19 (as vendored by lcms2-sys 4.0.7), MIT).

///|
/// Maximum number of channels a pipeline stage may handle (`MAX_STAGE_CHANNELS`).
const MAX_STAGE_CHANNELS : Int32 = 128

///|
/// Maximum number of CLUT input dimensions (`MAX_INPUT_DIMENSIONS`).
const MAX_INPUT_DIMENSIONS : Int32 = 15

///|
/// `cmsMAXCHANNELS`
const CMS_MAXCHANNELS : Int32 = 16

///|
const MATRIX_DET_TOLERANCE : Double = 0.0001

///|
/// `MAX_ENCODEABLE_XYZ`: 1.0 + 32767.0/32768.0
let max_encodeable_xyz : Double = 1.0 + 32767.0 / 32768.0

///|
/// `MINUS_INF` is the float literal `-1E22F`.
let minus_inf : Double = Float::from_double(-1.0e22).to_double()

///|
/// `PLUS_INF` is the float literal `+1E22F`.
let plus_inf : Double = Float::from_double(1.0e22).to_double()

///|
const D50_X : Double = 0.9642

///|
const D50_Y : Double = 1.0

///|
const D50_Z : Double = 0.8249

///|
const PERCEPTUAL_BLACK_X : Double = 0.00336

///|
const PERCEPTUAL_BLACK_Y : Double = 0.0034731

///|
const PERCEPTUAL_BLACK_Z : Double = 0.00287

// Profile class signatures

///|
const SIG_INPUT_CLASS : UInt32 = 0x73636E72 // 'scnr'

///|
const SIG_DISPLAY_CLASS : UInt32 = 0x6D6E7472 // 'mntr'

///|
const SIG_OUTPUT_CLASS : UInt32 = 0x70727472 // 'prtr'

///|
const SIG_LINK_CLASS : UInt32 = 0x6C696E6B // 'link'

///|
const SIG_ABSTRACT_CLASS : UInt32 = 0x61627374 // 'abst'

///|
const SIG_COLORSPACE_CLASS : UInt32 = 0x73706163 // 'spac'

///|
const SIG_NAMED_COLOR_CLASS : UInt32 = 0x6E6D636C // 'nmcl'

// Colour space signatures

///|
const SIG_XYZ_DATA : UInt32 = 0x58595A20 // 'XYZ '

///|
const SIG_LAB_DATA : UInt32 = 0x4C616220 // 'Lab '

///|
const SIG_RGB_DATA : UInt32 = 0x52474220 // 'RGB '

///|
const SIG_GRAY_DATA : UInt32 = 0x47524159 // 'GRAY'

///|
const SIG_CMYK_DATA : UInt32 = 0x434D594B // 'CMYK'

///|
const SIG_CMY_DATA : UInt32 = 0x434D5920 // 'CMY '

///|
const SIG_4COLOR_DATA : UInt32 = 0x34434C52 // '4CLR'

// Tag signatures

///|
const SIG_A2B0 : UInt32 = 0x41324230

///|
const SIG_A2B1 : UInt32 = 0x41324231

///|
const SIG_A2B2 : UInt32 = 0x41324232

///|
const SIG_B2A0 : UInt32 = 0x42324130

///|
const SIG_B2A1 : UInt32 = 0x42324131

///|
const SIG_B2A2 : UInt32 = 0x42324132

///|
const SIG_D2B0 : UInt32 = 0x44324230

///|
const SIG_B2D0 : UInt32 = 0x42324430

///|
const SIG_RED_COLORANT : UInt32 = 0x7258595A // 'rXYZ'

///|
const SIG_GREEN_COLORANT : UInt32 = 0x6758595A // 'gXYZ'

///|
const SIG_BLUE_COLORANT : UInt32 = 0x6258595A // 'bXYZ'

///|
const SIG_RED_TRC : UInt32 = 0x72545243 // 'rTRC'

///|
const SIG_GREEN_TRC : UInt32 = 0x67545243 // 'gTRC'

///|
const SIG_BLUE_TRC : UInt32 = 0x62545243 // 'bTRC'

///|
const SIG_GRAY_TRC : UInt32 = 0x6B545243 // 'kTRC'

///|
const SIG_MEDIA_WHITE_POINT : UInt32 = 0x77747074 // 'wtpt'

// Tag type signatures

///|
const SIG_CURVE_TYPE : UInt32 = 0x63757276 // 'curv'

///|
const SIG_PARAMETRIC_CURVE_TYPE : UInt32 = 0x70617261 // 'para'

///|
const SIG_XYZ_TYPE : UInt32 = 0x58595A20 // 'XYZ '

///|
const SIG_LUT8_TYPE : UInt32 = 0x6D667431 // 'mft1'

///|
const SIG_LUT16_TYPE : UInt32 = 0x6D667432 // 'mft2'

///|
const SIG_LUT_ATOB_TYPE : UInt32 = 0x6D414220 // 'mAB '

///|
const SIG_LUT_BTOA_TYPE : UInt32 = 0x6D424120 // 'mBA '

///|
const SIG_MULTI_PROCESS_ELEMENT_TYPE : UInt32 = 0x6D706574 // 'mpet'

///|
const SIG_MAGIC_NUMBER : UInt32 = 0x61637370 // 'acsp'

///|
/// Rendering intents, as in the ICC header and `cmsCreateTransform`.
#derive(Debug, Eq)
pub(all) enum RenderingIntent {
  Perceptual
  Relative
  Saturation
  Absolute
}

///|
fn RenderingIntent::code(self : RenderingIntent) -> Int32 {
  match self {
    Perceptual => 0
    Relative => 1
    Saturation => 2
    Absolute => 3
  }
}

///|
const INTENT_PERCEPTUAL : Int32 = 0

///|
const INTENT_RELATIVE_COLORIMETRIC : Int32 = 1

///|
const INTENT_SATURATION : Int32 = 2

///|
const INTENT_ABSOLUTE_COLORIMETRIC : Int32 = 3

///|
fn cms_error(msg : String) -> @bitstream.JxlError {
  @bitstream.JxlError::Color(msg)
}
