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
  /// Entropy decoder errors (jxl-coding `Error`, except its `Bitstream`
  /// variant, whose errors are raised unwrapped).
  Decoder(CodingError)
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

///|
/// The jxl-coding `Error` variants (without `Bitstream`).
#derive(Debug, Eq)
pub(all) enum CodingError {
  /// LZ77 decoder is being used where it's not allowed.
  Lz77NotAllowed
  /// Decoded ANS distribution is invalid.
  InvalidAnsHistogram
  /// ANS stream checksum verification has failed.
  InvalidAnsStream
  /// Hybrid integer configuration is invalid.
  InvalidIntegerConfig(
    split_exponent~ : UInt32,
    msb_in_token~ : UInt32,
    lsb_in_token~ : UInt32?,
  )
  /// Decoded permutation is invalid.
  InvalidPermutation
  /// Decoded Brotli histogram is invalid.
  InvalidPrefixHistogram
  /// Prefix code symbol is too large.
  PrefixSymbolTooLarge(Int32)
  /// Decoded cluster ID is invalid.
  InvalidCluster(UInt32)
  /// Distribution cluster has a hole.
  ClusterHole(num_expected_clusters~ : UInt32, num_actual_clusters~ : UInt32)
  /// LZ77 repeat symbol encountered without decoding any symbols.
  UnexpectedLz77Repeat
  /// Decoded LZ77 symbol is invalid.
  InvalidLz77Symbol
}

///|
/// Upstream `Display` of jxl-coding `Error`.
pub impl Show for CodingError with fn output(self, logger) {
  let msg = match self {
    Lz77NotAllowed => "LZ77-enabled decoder when it is not allowed"
    InvalidAnsHistogram => "invalid ANS distribution"
    InvalidAnsStream => "ANS stream verification failed"
    InvalidIntegerConfig(split_exponent~, msb_in_token~, lsb_in_token~) =>
      "invalid hybrid integer configuration; \{lsb_in_token.unwrap_or(0)} + \{msb_in_token} > \{split_exponent}"
    InvalidPermutation => "invalid permutation"
    InvalidPrefixHistogram => "invalid Brotli prefix code"
    PrefixSymbolTooLarge(size) => "prefix code symbol too large (\{size})"
    InvalidCluster(id) => "invalid cluster ID \{id}"
    ClusterHole(num_expected_clusters~, num_actual_clusters~) =>
      "distribution cluster has a hole; expected \{num_expected_clusters}, actual \{num_actual_clusters}"
    UnexpectedLz77Repeat =>
      "LZ77 repeat symbol encountered without decoding any symbols"
    InvalidLz77Symbol => "Invalid LZ77 symbol"
  }
  logger.write_string(msg)
}

///|
/// Upstream `Display` of jxl-bitstream `Error` for the bitstream-level
/// variants (`Eof` is `Io(UnexpectedEof)` upstream) and of jxl-coding `Error`
/// for `Decoder`. Variants owned by other crates print their payload.
pub impl Show for JxlError with fn output(self, logger) {
  let msg = match self {
    Eof => "I/O error: unexpected end of file"
    Io(e) => "I/O error: \{e}"
    InvalidBox => "invalid container"
    NonZeroPadding => "PadZeroToByte() read non-zero bits"
    InvalidFloat => "F16() read NaN or Infinity"
    InvalidEnum(name, value) =>
      "Enum(\{name}) read invalid enum value of \{value}"
    ValidationFailed(msg) => "bitstream validation failed: \{msg}"
    ProfileConformance(msg) => "not supported by current profile: \{msg}"
    CannotSkip => "target bookmark already passed"
    NotAligned => "bitstream is unaligned"
    Decoder(e) => "\{e}"
    Modular(s) => "Modular(\{s})"
    Frame(s) => "Frame(\{s})"
    IncompleteFrameData(s) => "IncompleteFrameData(\{s})"
    Color(s) => "Color(\{s})"
    Render(s) => "Render(\{s})"
    NotSupported(s) => "NotSupported(\{s})"
    OutOfMemory(n) => "OutOfMemory(\{n})"
    Jbr(s) => "Jbr(\{s})"
    Brotli(s) => "Brotli(\{s})"
  }
  logger.write_string(msg)
}
