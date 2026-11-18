// Port of jxl-color/src/error.rs.
//
// The whole decoder uses one error type, `@bitstream.JxlError`. Upstream `jxl_color::Error`
// variants map to it as follows (the String payload starts with the upstream variant name):
//
// - `Bitstream(e)` / `Decoder(e)`  -> the wrapped `JxlError` itself
// - `InvalidIccStream(s)`          -> `Color("InvalidIccStream: " + s)`
// - `IccParseFailure(s)`           -> `Color("IccParseFailure: " + s)`
// - `UnsupportedColorEncoding`     -> `Color("UnsupportedColorEncoding")`
// - `UnsupportedIccProfile`        -> `Color("UnsupportedIccProfile")`
// - `IccProfileEmbedded`           -> `Color("IccProfileEmbedded")`
// - `InvalidEnumColorspace`        -> `Color("InvalidEnumColorspace")`
// - `CmsNotAvailable`              -> `Color("CmsNotAvailable")`
// - `CmsFailure(e)`                -> `Color("CmsFailure: " + message)`

///|
fn invalid_icc_stream(msg : String) -> @bitstream.JxlError {
  @bitstream.Color("InvalidIccStream: " + msg)
}

///|
fn icc_parse_failure(msg : String) -> @bitstream.JxlError {
  @bitstream.Color("IccParseFailure: " + msg)
}
