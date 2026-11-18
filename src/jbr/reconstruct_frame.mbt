// Port of `JpegBitstreamReconstructor::new` (jxl-jbr/src/reconstruct.rs):
// decodes the VarDCT frame into `ParsedFrameData`.

///|
/// Creates a reconstruction context with given JPEG XL frame and metadata.
///
/// `icc_profile`, `exif` or `xmp` can be empty if no corresponding metadata
/// was found.
pub fn JpegBitstreamData::reconstruct(
  self : JpegBitstreamData,
  frame : @frame.Frame,
  icc_profile : Bytes,
  exif : Bytes,
  xmp : Bytes,
) -> JpegBitstreamReconstructor raise @bitstream.JxlError {
  JpegBitstreamReconstructor::new(
    self.header,
    self.data_stream.get_ref(),
    frame,
    icc_profile,
    exif,
    xmp,
  )
}

///|
pub fn JpegBitstreamReconstructor::new(
  header : JpegBitstreamHeader,
  data : Bytes,
  frame : @frame.Frame,
  icc_profile : Bytes,
  exif : Bytes,
  xmp : Bytes,
) -> JpegBitstreamReconstructor raise @bitstream.JxlError {
  check_metadata_lengths(header, icc_profile, exif, xmp)
  if frame.image_header().metadata.xyb_encoded {
    raise err_incompatible_frame()
  }
  let frame_header = frame.header()
  if frame_header.encoding != @frame.Encoding::VarDct {
    raise err_incompatible_frame()
  }
  if !frame_header.frame_type.is_normal_frame() {
    raise err_incompatible_frame()
  }
  if frame_header.flags.use_lf_frame() ||
    !frame_header.flags.skip_adaptive_lf_smoothing() {
    raise err_incompatible_frame()
  }
  let lf_global = match frame.try_parse_lf_global() {
    Some(Ok(x)) => x
    Some(Err(e)) => raise e
    None => raise err_frame_data_incomplete()
  }
  let lf_global_vardct = lf_global.vardct.unwrap()
  let global_ma_config = lf_global.gmodular.ma_config()
  let image_size = frame.image_header().size
  let info : JpegFrameInfo = {
    image_width: image_size.width,
    image_height: image_size.height,
    width: frame_header.width,
    height: frame_header.height,
    color_sample_width: frame_header.color_sample_width(),
    color_sample_height: frame_header.color_sample_height(),
    jpeg_upsampling: frame_header.jpeg_upsampling,
    do_ycbcr: frame_header.do_ycbcr,
    group_size_shift: frame_header.group_size_shift,
  }
  let jpeg_upsampling_ycbcr = info.jpeg_upsampling_ycbcr()
  let is_subsampled = jpeg_upsampling_ycbcr.iter().any(fn(x) { x != 0 })
  let upsampling_shifts_ycbcr = FixedArray::makei(3, fn(idx) {
    ChannelShift::from_jpeg_upsampling(jpeg_upsampling_ycbcr, idx)
  })
  if !is_subsampled {
    let lf_chan_corr = lf_global_vardct.lf_chan_corr
    if lf_chan_corr.colour_factor != CFL_DEFAULT_COLOR_FACTOR ||
      lf_chan_corr.base_correlation_x != 0.0 ||
      lf_chan_corr.base_correlation_b != 0.0 {
      raise err_incompatible_frame()
    }
  }
  let hf_global = match frame.try_parse_hf_global(Some(lf_global)) {
    Some(Ok(x)) => x
    Some(Err(e)) => raise e
    None => raise err_frame_data_incomplete()
  }
  let jpeg_quant_values = []
  for c in 0..<3 {
    match hf_global.dequant_matrices.jpeg_quant_values(c) {
      Some(q) => jpeg_quant_values.push(q)
      None => raise err_incompatible_frame()
    }
  }
  let num_lf_groups = frame_header.num_lf_groups()
  let lf_groups = []
  for lf_group_idx in 0..<num_lf_groups {
    match
      frame.try_parse_lf_group(
        Some(lf_global_vardct),
        global_ma_config,
        None,
        lf_group_idx,
      ) {
      Some(Ok(x)) => lf_groups.push(x)
      Some(Err(e)) => raise e
      None => raise err_frame_data_incomplete()
    }
  }
  let num_groups = frame_header.num_groups()
  let pass_groups : Array[FixedArray[@grid.Grid[Int32]]] = []
  for group_idx in 0..<num_groups {
    let (w, h) = frame_header.group_size_for(group_idx)
    pass_groups.push(
      FixedArray::makei(3, fn(c) {
        let (w8, h8) = upsampling_shifts_ycbcr[c].shift_size(
          div_ceil(w, 8),
          div_ceil(h, 8),
        )
        @grid.Grid::new(w8 * 8, h8 * 8, 0)
      }),
    )
  }
  for pass_idx in 0..<frame_header.passes.num_passes {
    for group_idx in 0..<num_groups {
      let pass_group = match frame.pass_group_bitstream(pass_idx, group_idx) {
        Some(Ok(x)) => x
        Some(Err(e)) => raise e
        None => raise err_frame_data_incomplete()
      }
      if pass_group.partial {
        raise err_frame_data_incomplete()
      }
      let bitstream = pass_group.bitstream
      let lf_group_idx = frame_header.lf_group_idx_from_group_idx(group_idx)
      let lf_group = lf_groups[lf_group_idx]
      let pg = pass_groups[group_idx]
      // decode_pass_group writes in (X, Y, B) = (Cb, Y, Cr) order.
      let hf_coeff_output : FixedArray[@grid.SubGrid[Int32]] = [
        pg[1].as_subgrid(),
        pg[0].as_subgrid(),
        pg[2].as_subgrid(),
      ]
      @frame.decode_pass_group(bitstream, {
        frame_header,
        lf_group,
        pass_idx,
        group_idx,
        global_ma_config,
        modular: None,
        vardct: Some({
          lf_vardct: lf_global_vardct,
          hf_global,
          hf_coeff_output,
        }),
        allow_partial: false,
        tracker: None,
        pool: @threadpool.JxlThreadPool::none(),
      })
    }
  }
  if !header.is_gray && !is_subsampled {
    let x_from_y = lf_groups.map(fn(g) { g.hf_meta.unwrap().x_from_y })
    let b_from_y = lf_groups.map(fn(g) { g.hf_meta.unwrap().b_from_y })
    integer_cfl(info, jpeg_quant_values, x_from_y, b_from_y, pass_groups)
  }
  let dc_offset : FixedArray[Int32] = if frame_header.do_ycbcr {
    [0, 0, 0]
  } else {
    let dequant_x = jpeg_quant_values[0]
    let dequant_y = jpeg_quant_values[1]
    let dequant_b = jpeg_quant_values[2]
    [
      to_i16(1024 / dequant_y[0]),
      to_i16(1024 / dequant_x[0]),
      to_i16(1024 / dequant_b[0]),
    ]
  }
  let lf_quant : Array[FixedArray[@grid.Grid[Int32]]] = lf_groups.map(fn(g) {
    let chans = g.lf_coeff.unwrap().lf_quant.image().unwrap().image_channels()
    let a : FixedArray[@grid.Grid[Int32]] = [chans[0], chans[1], chans[2]]
    a
  })
  let parsed : ParsedFrameData = {
    lf_quant,
    pass_groups,
    jpeg_quant_values,
    dc_offset,
  }
  JpegBitstreamReconstructor::from_parsed(
    header, data, info, parsed, icc_profile, exif, xmp,
  )
}
