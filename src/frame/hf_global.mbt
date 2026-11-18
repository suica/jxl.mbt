///|
pub(all) struct HfGlobalParams {
  metadata : @image.ImageMetadata
  frame_header : FrameHeader
  ma_config : @modular.MaConfig?
  hf_block_ctx : @vardct.HfBlockContext
  tracker : @grid.AllocTracker?
}

///|
pub fn HfGlobalParams::new(
  metadata : @image.ImageMetadata,
  frame_header : FrameHeader,
  lf_global : LfGlobal,
  tracker : @grid.AllocTracker?,
) -> HfGlobalParams {
  guard lf_global.vardct is Some(lf_vardct) else {
    abort("VarDCT not initialized")
  }
  {
    metadata,
    frame_header,
    ma_config: lf_global.gmodular.ma_config,
    hf_block_ctx: lf_vardct.hf_block_ctx,
    tracker,
  }
}

///|
pub(all) struct HfGlobal {
  dequant_matrices : @vardct.DequantMatrixSet
  num_hf_presets : Int32
  hf_passes : Array[@vardct.HfPass]
}

///|
pub fn HfGlobal::parse(
  bs : @bitstream.Bitstream,
  params : HfGlobalParams,
) -> HfGlobal raise @bitstream.JxlError {
  let { metadata, frame_header, ma_config, hf_block_ctx, tracker, } = params
  let dequant_matrix_params = @vardct.DequantMatrixSetParams::new(
    metadata.bit_depth.bits_per_sample(),
    frame_header.num_lf_groups(),
    ma_config,
    tracker,
    @threadpool.JxlThreadPool::none(),
  )
  let dequant_matrices = @vardct.DequantMatrixSet::parse(
    bs, dequant_matrix_params,
  )
  let num_groups = frame_header.num_groups()
  // `num_groups.next_power_of_two().trailing_zeros()`
  let nbits = if num_groups <= 1 { 0 } else { 32 - (num_groups - 1).clz() }
  let num_hf_presets = bs.read_bits_int(nbits) + 1
  let hf_pass_params = @vardct.HfPassParams::new(hf_block_ctx, num_hf_presets)
  let hf_passes = []
  for _ in 0..<frame_header.passes.num_passes {
    hf_passes.push(@vardct.HfPass::parse(bs, hf_pass_params))
  }
  { dequant_matrices, num_hf_presets, hf_passes, }
}
