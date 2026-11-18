// Port of moxcms 0.9.0 `err.rs`.
// moxcms: Copyright (c) Radzivon Bartoshyk. BSD-3-Clause OR Apache-2.0.

///|
#derive(Debug, Eq)
pub(all) struct MalformedSize {
  size : Int32
  expected : Int32
}

///|
/// Errors of the colour management system (`moxcms::CmsError`).
#derive(Eq)
pub(all) suberror CmsError {
  LaneSizeMismatch
  LaneMultipleOfChannels
  InvalidProfile
  InvalidTrcCurve
  InvalidCicp
  CurveLutIsTooLarge
  ParametricCurveZeroDivision
  InvalidRenderingIntent
  DivisionByZero
  UnsupportedColorPrimaries(Int32)
  UnsupportedTrc(Int32)
  InvalidLayout
  UnsupportedProfileConnection
  BuildTransferFunction
  UnsupportedChannelConfiguration
  UnknownTag(UInt32)
  UnknownTagTypeDefinition(UInt32)
  UnsupportedLutRenderingIntent(RenderingIntent)
  InvalidAtoBLut
  OverflowingError
  LUTTablesInvalidKind
  MalformedClut(MalformedSize)
  MalformedCurveLutTable(MalformedSize)
  InvalidInksCountForProfile
  MalformedTrcCurve(String)
  OutOfMemory(Int32)
  IncorrectlyFormedLut(String)
}

///|
/// `Display` text of the error, as upstream formats it.
pub fn CmsError::message(self : CmsError) -> String {
  match self {
    LaneSizeMismatch => "Lanes length must match"
    LaneMultipleOfChannels =>
      "Lane length must not be multiple of channel count"
    InvalidProfile => "Invalid ICC profile"
    InvalidCicp => "Invalid Code Independent point (CICP) in ICC profile"
    InvalidTrcCurve => "Invalid TRC curve"
    CurveLutIsTooLarge => "Curve Lut is too large"
    ParametricCurveZeroDivision =>
      "Parametric Curve definition causes division by zero"
    InvalidRenderingIntent => "Invalid rendering intent"
    DivisionByZero => "Division by zero"
    UnsupportedColorPrimaries(v) => "Unsupported color primaries, \{v}"
    UnsupportedTrc(v) => "Unsupported TRC \{v}"
    InvalidLayout => "Invalid layout"
    UnsupportedProfileConnection => "Unsupported profile connection"
    BuildTransferFunction => "Can't reconstruct transfer function"
    UnsupportedChannelConfiguration => "Can't reconstruct channel configuration"
    UnknownTag(t) => "Unknown tag: \{t}"
    UnknownTagTypeDefinition(t) => "Unknown tag type definition: \{t}"
    UnsupportedLutRenderingIntent(intent) =>
      "Can't find LUT for rendering intent: \{intent.name()}"
    InvalidAtoBLut => "Invalid A to B Lut"
    OverflowingError => "Overflowing was happen, that is not allowed"
    LUTTablesInvalidKind => "All LUT curves must have same kind"
    MalformedClut(size) =>
      "Invalid CLUT size: MalformedSize { size: \{size.size}, expected: \{size.expected} }"
    MalformedCurveLutTable(size) =>
      "Malformed curve LUT size: MalformedSize { size: \{size.size}, expected: \{size.expected} }"
    InvalidInksCountForProfile => "Invalid inks count for profile was provided"
    MalformedTrcCurve(s) => s
    OutOfMemory(capacity) =>
      "There is no enough memory to allocate \{capacity} bytes"
    IncorrectlyFormedLut(s) => s
  }
}

///|
pub impl Show for CmsError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
// `SafeAdd`/`SafeMul` (`safe_math.rs`) on `usize` (64-bit on the upstream
// target): offsets are kept in `Int64`, which cannot overflow for the u32
// sums and products the parser computes; checks against `usize::MAX` are
// therefore never hit and are omitted.

///|
/// `u32::safe_mul`.
fn safe_mul_u32(a : UInt32, b : UInt32) -> UInt32 raise CmsError {
  let r = a.to_uint64() * b.to_uint64()
  if r > 0xFFFFFFFFUL {
    raise OverflowingError
  }
  r.to_uint()
}

///|
/// `u32::safe_powi`.
fn safe_powi_u32(a : UInt32, power : UInt32) -> UInt32 raise CmsError {
  let mut acc = 1U
  for _ in 0U..<power {
    acc = safe_mul_u32(acc, a)
  }
  acc
}
