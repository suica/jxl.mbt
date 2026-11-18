// Parts of jxl-vardct `dequant.rs` that need jxl-modular.

///|
/// Parameters for decoding `DequantMatrixSet`.
pub struct DequantMatrixSetParams {
  priv dct_select : TransformType
  priv bit_depth : Int32
  priv stream_index : Int32
  priv global_ma_config : @modular.MaConfig?
  priv tracker : @grid.AllocTracker?
  priv pool : @threadpool.JxlThreadPool
}

///|
/// Create a new `DequantMatrixSetParams` with the given information.
///
/// `num_lf_groups` is used to compute the stream index for Modular images.
pub fn DequantMatrixSetParams::new(
  bit_depth : Int32,
  num_lf_groups : Int32,
  global_ma_config : @modular.MaConfig?,
  tracker : @grid.AllocTracker?,
  pool : @threadpool.JxlThreadPool,
) -> DequantMatrixSetParams {
  {
    dct_select: Dct8,
    bit_depth,
    stream_index: 1 + num_lf_groups * 3,
    global_ma_config,
    tracker,
    pool,
  }
}

///|
/// Decodes the Modular image of a raw (encoding mode 7) dequantization matrix,
/// returning its three channels.
fn decode_raw_dequant_matrix(
  bitstream : @bitstream.Bitstream,
  width : Int32,
  height : Int32,
  params : DequantMatrixSetParams,
) -> FixedArray[FixedArray[Int32]] raise @bitstream.JxlError {
  let modular_params = @modular.ModularParams::new(
    width,
    height,
    256,
    params.bit_depth,
    [
      @modular.ChannelShift::from_shift(0),
      @modular.ChannelShift::from_shift(0),
      @modular.ChannelShift::from_shift(0),
    ],
    params.global_ma_config,
    params.tracker,
  )
  let modular = @modular.Modular::parse(bitstream, modular_params)
  let image = modular.image_mut().unwrap()
  let subimage = image.prepare_subimage()
  subimage.decode(bitstream, params.stream_index, false)
  // `subimage.finish(pool)`: jxl-modular's `finish` runs sequentially, which is
  // what upstream does with `JxlThreadPool::none()`.
  ignore(params.pool)
  ignore(subimage.finish())
  let channels = modular.into_image().unwrap().into_image_channels()
  FixedArray::makei(3, c => channels[c].buf())
}
