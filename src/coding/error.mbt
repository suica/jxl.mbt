///|
/// jxl-coding `Error` variants are mapped to `@bitstream.Decoder(name)`, where
/// `name` is the upstream variant name (plus details where upstream has them).
/// Bitstream-level errors (`Error::Bitstream`) propagate unchanged.
fn coding_error(name : String) -> @bitstream.JxlError {
  @bitstream.Decoder(name)
}
