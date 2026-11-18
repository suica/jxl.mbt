// Parts of jxl-vardct `dequant.rs` that need jxl-modular.

///|
/// Parameters for decoding `DequantMatrixSet`.
pub struct DequantMatrixSetParams {
  priv dct_select : TransformType
  priv bit_depth : Int32
  priv stream_index : Int32
  priv tracker : @grid.AllocTracker?
}

///|
/// Create a new `DequantMatrixSetParams` with the given information.
///
/// `num_lf_groups` is used to compute the stream index for Modular images.
pub fn DequantMatrixSetParams::new(
  bit_depth : Int32,
  num_lf_groups : Int32,
  tracker : @grid.AllocTracker?,
) -> DequantMatrixSetParams {
  { dct_select: Dct8, bit_depth, stream_index: 1 + num_lf_groups * 3, tracker, }
}

///|
/// Decodes the Modular image of a raw (encoding mode 7) dequantization matrix,
/// returning its three channels.
fn decode_raw_dequant_matrix(
  _bitstream : @bitstream.Bitstream,
  _width : Int32,
  _height : Int32,
  _params : DequantMatrixSetParams,
) -> FixedArray[FixedArray[Int32]] raise @bitstream.JxlError {
  raise @bitstream.NotSupported(
    "raw dequant matrix: jxl-modular not merged yet",
  )
}
