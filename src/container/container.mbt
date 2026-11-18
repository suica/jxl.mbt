///|
/// Types for JPEG XL container format.

///|
/// Structure of the decoded bitstream.
#derive(Eq, Debug)
pub(all) enum BitstreamKind {
  /// Decoder can't determine structure of the bitstream.
  Unknown
  /// Bitstream is a direct JPEG XL codestream without box structure.
  BareCodestream
  /// Bitstream is a JPEG XL container with box structure.
  Container
  /// Bitstream is not a valid JPEG XL image.
  Invalid
}

///|
priv enum DetectState {
  WaitingSignature
  WaitingBoxHeader
  WaitingJxlpIndex(ContainerBoxHeader)
  InAuxBox(
    header~ : ContainerBoxHeader,
    brotli_box_type~ : ContainerBoxType?,
    bytes_left~ : Int64?
  )
  InCodestream(
    kind~ : BitstreamKind,
    bytes_left~ : Int64?,
    pending_no_more_aux_box~ : Bool
  )
}

///|
priv enum JxlpIndexState {
  Initial
  SingleJxlc
  Jxlp(UInt32)
  JxlpFinished
}

///|
/// Parser that detects the kind of bitstream and emits parser events.
pub struct ContainerParser {
  priv mut state : DetectState
  priv mut jxlp_index_state : JxlpIndexState
  priv mut previous_consumed_bytes : Int32
}

///|
/// Creates a new parser.
pub fn ContainerParser::new() -> ContainerParser {
  {
    state: WaitingSignature,
    jxlp_index_state: Initial,
    previous_consumed_bytes: 0,
  }
}

///|
/// Returns the kind of this bitstream currently recognized.
pub fn ContainerParser::kind(self : ContainerParser) -> BitstreamKind {
  match self.state {
    WaitingSignature => Unknown
    WaitingBoxHeader | WaitingJxlpIndex(_) | InAuxBox(..) => Container
    InCodestream(kind~, ..) => kind
  }
}

///|
/// Feeds bytes to the parser, and receives parser events.
///
/// The parser might not consume all of the buffer. Use `previous_consumed_bytes` to get how
/// many bytes are consumed. Bytes not consumed by the parser should be fed into the parser
/// again.
pub fn ContainerParser::feed_bytes(
  self : ContainerParser,
  input : BytesView,
) -> ParseEvents {
  ParseEvents::new(self, input)
}

///|
/// Get how many bytes are consumed by the previous call to `feed_bytes`.
///
/// Bytes not consumed by the parser should be fed into the parser again.
pub fn ContainerParser::previous_consumed_bytes(
  self : ContainerParser,
) -> Int32 {
  self.previous_consumed_bytes
}

///|
pub impl Show for BitstreamKind with fn output(self, logger) {
  logger.write_string(
    match self {
      Unknown => "Unknown"
      BareCodestream => "BareCodestream"
      Container => "Container"
      Invalid => "Invalid"
    },
  )
}
