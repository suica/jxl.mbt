///|
pub(all) struct LfGroupParams {
  frame_header : FrameHeader
  quantizer : @vardct.Quantizer?
  global_ma_config : @modular.MaConfig?
  mlf_group : @modular.TransformedModularSubimage?
  lf_group_idx : Int32
  allow_partial : Bool
  tracker : @grid.AllocTracker?
}

///|
pub(all) struct LfGroup {
  lf_coeff : @vardct.LfCoeff?
  hf_meta : @vardct.HfMetadata?
  partial : Bool
}

///|
pub fn LfGroup::parse(
  bs : @bitstream.Bitstream,
  params : LfGroupParams,
) -> LfGroup raise @bitstream.JxlError {
  let {
    frame_header,
    global_ma_config,
    mlf_group,
    lf_group_idx,
    allow_partial,
    tracker,
    ..
  } = params
  let (lf_width, lf_height) = frame_header.lf_group_size_for(lf_group_idx)
  let lf_coeff = if frame_header.encoding == VarDct &&
    !frame_header.flags.use_lf_frame() {
    let lf_coeff_params : @vardct.LfCoeffParams = {
      lf_group_idx,
      lf_width,
      lf_height,
      jpeg_upsampling: frame_header.jpeg_upsampling,
      bits_per_sample: frame_header.bit_depth.bits_per_sample(),
      global_ma_config,
      allow_partial,
      tracker,
      pool: @threadpool.JxlThreadPool::none(),
    }
    Some(@vardct.LfCoeff::parse(bs, lf_coeff_params))
  } else {
    None
  }
  if lf_coeff is Some(lf_coeff_inner) && lf_coeff_inner.partial {
    return { lf_coeff, hf_meta: None, partial: true, }
  }
  let mut is_mlf_complete = true
  if mlf_group is Some(image) && !image.is_empty() {
    let subimage = image.recursive(bs, global_ma_config, tracker)
    let subimage = subimage.prepare_subimage()
    subimage.decode(
      bs,
      1 + frame_header.num_lf_groups() + lf_group_idx,
      allow_partial,
    )
    is_mlf_complete = subimage.finish()
  }
  let hf_meta = if frame_header.encoding == VarDct && is_mlf_complete {
    let hf_meta_params : @vardct.HfMetadataParams = {
      num_lf_groups: frame_header.num_lf_groups(),
      lf_group_idx,
      lf_width,
      lf_height,
      jpeg_upsampling: frame_header.jpeg_upsampling,
      bits_per_sample: frame_header.bit_depth.bits_per_sample(),
      global_ma_config,
      epf: match frame_header.restoration_filter.epf {
        Disabled => None
        Enabled({ sharp_lut, sigma, .. }) => Some((sigma.quant_mul, sharp_lut))
      },
      quantizer_global_scale: params.quantizer.unwrap().global_scale,
      tracker,
      pool: @threadpool.JxlThreadPool::none(),
    }
    Ok(Some(@vardct.HfMetadata::parse(bs, hf_meta_params))) catch {
      e => Err(e)
    }
  } else {
    Ok(None)
  }
  match hf_meta {
    Err(e) if e.unexpected_eof() && allow_partial =>
      // Decoded partial HfMeta
      { lf_coeff, hf_meta: None, partial: true, }
    Err(e) => raise e
    Ok(hf_meta) => { lf_coeff, hf_meta, partial: !is_mlf_complete, }
  }
}
