///|
/// jxl-modular `Error` variants map onto `@bitstream.JxlError`:
/// `InvalidMaTree`, `GlobalMaTreeNotAvailable`, `InvalidRctParams`,
/// `InvalidPaletteParams` and `InvalidSqueezeParams` become
/// `Modular("<VariantName>")`; bitstream, decoder and buffer errors are
/// propagated as they are.
fn modular_error(name : String) -> @bitstream.JxlError {
  @bitstream.Modular(name)
}
