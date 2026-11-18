// Port of jxl-jbr/src/error.rs.
//
// jxl-jbr's `Error` enum maps onto `@bitstream.JxlError`:
// - `Bitstream(e)` / `FrameParse(e)`: the underlying error is passed through;
// - `Brotli(e)`: `Brotli(..)` from the brotli package;
// - every other variant: `Jbr("<VariantName>")`.

///|
fn err_invalid_data() -> @bitstream.JxlError {
  @bitstream.JxlError::Jbr("InvalidData")
}

///|
fn err_huffman_lookup() -> @bitstream.JxlError {
  @bitstream.JxlError::Jbr("HuffmanLookup")
}

///|
fn err_frame_data_incomplete() -> @bitstream.JxlError {
  @bitstream.JxlError::Jbr("FrameDataIncomplete")
}

///|
fn err_incompatible_frame() -> @bitstream.JxlError {
  @bitstream.JxlError::Jbr("IncompatibleFrame")
}
