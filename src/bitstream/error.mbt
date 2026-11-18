///|
/// The single error type of the whole decoder. Every package raises this,
/// mirroring the union of jxl-oxide's per-crate `Error` enums.
#derive(Debug, Eq)
pub(all) suberror JxlError {
  /// Reading past the end of the available data (`UnexpectedEof`).
  Eof
  /// An I/O-like failure other than EOF.
  Io(String)
  InvalidBox
  NonZeroPadding
  InvalidFloat
  InvalidEnum(String, UInt32)
  /// `ValidationFailed(msg)` and the many crate-specific "invalid X" errors.
  ValidationFailed(String)
  ProfileConformance(String)
  CannotSkip
  NotAligned
  /// Entropy decoder errors (jxl-coding), e.g. "InvalidAnsHistogram".
  Decoder(String)
  /// Modular stream errors (jxl-modular), e.g. "InvalidMaTree".
  Modular(String)
  /// Frame errors (jxl-frame), e.g. "InvalidTocPermutation".
  Frame(String)
  /// Incomplete frame data; the field name is given.
  IncompleteFrameData(String)
  /// Color errors (jxl-color), e.g. "UnsupportedIccProfile".
  Color(String)
  /// Render errors (jxl-render), e.g. "IncompleteFrame", "NotReady".
  Render(String)
  NotSupported(String)
  /// Allocation would exceed the tracker's limit; bytes requested.
  OutOfMemory(Int32)
  /// JPEG bitstream reconstruction errors (jxl-jbr).
  Jbr(String)
  /// Brotli decoding errors.
  Brotli(String)
}

///|
pub fn JxlError::unexpected_eof(self : JxlError) -> Bool {
  self is Eof
}
