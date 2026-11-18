///|
pub(all) struct PassGroupParams {
  frame_header : FrameHeader
  lf_group : LfGroup
  pass_idx : Int32
  group_idx : Int32
  global_ma_config : @modular.MaConfig?
  modular : @modular.TransformedModularSubimage?
  vardct : PassGroupParamsVardct?
  allow_partial : Bool
  tracker : @grid.AllocTracker?
  pool : @threadpool.JxlThreadPool
}

///|
pub(all) struct PassGroupParamsVardct {
  lf_vardct : LfGlobalVarDct
  hf_global : HfGlobal
  hf_coeff_output : FixedArray[@grid.SubGrid[Int32]]
}

///|
pub fn decode_pass_group(
  bs : @bitstream.Bitstream,
  params : PassGroupParams,
) -> Unit raise @bitstream.JxlError {
  let {
    frame_header,
    lf_group,
    pass_idx,
    group_idx,
    global_ma_config,
    modular,
    vardct,
    allow_partial,
    tracker,
    pool,
  } = params
  if vardct is Some({ lf_vardct, hf_global, hf_coeff_output, }) &&
    lf_group.hf_meta is Some(hf_meta) {
    let hf_pass = hf_global.hf_passes[pass_idx]
    let coeff_shift = if pass_idx < frame_header.passes.shift.length() {
      frame_header.passes.shift[pass_idx]
    } else {
      0
    }
    let group_col = group_idx % frame_header.groups_per_row()
    let group_row = group_idx / frame_header.groups_per_row()
    let lf_col = group_col % 8
    let lf_row = group_row % 8
    let group_dim_blocks = frame_header.group_dim() / 8
    let block_info = hf_meta.block_info
    let block_left = lf_col * group_dim_blocks
    let block_top = lf_row * group_dim_blocks
    let block_width = @cmp.minimum(
      block_info.width() - block_left,
      group_dim_blocks,
    )
    let block_height = @cmp.minimum(
      block_info.height() - block_top,
      group_dim_blocks,
    )
    let jpeg_upsampling = frame_header.jpeg_upsampling
    let block_info = block_info
      .as_subgrid()
      .subgrid(block_left, block_top, block_width, block_height)
    let lf_quant : FixedArray[@grid.SubGrid[Int32]]? = match lf_group.lf_coeff {
      Some(lf_coeff) => {
        let lf_quant_channels = lf_coeff.lf_quant
          .image()
          .unwrap()
          .image_channels()
        Some(
          FixedArray::makei(3, idx => {
            let lf_quant = lf_quant_channels[[1, 0, 2][idx]]
            let shift = @modular.ChannelShift::from_jpeg_upsampling(
              jpeg_upsampling, idx,
            )
            let block_left = block_left >> shift.hshift()
            let block_top = block_top >> shift.vshift()
            let (block_width, block_height) = shift.shift_size(
              (block_width, block_height),
            )
            lf_quant
            .as_subgrid()
            .subgrid(block_left, block_top, block_width, block_height)
          }),
        )
      }
      None => None
    }
    let params : @vardct.HfCoeffParams = {
      num_hf_presets: hf_global.num_hf_presets,
      hf_block_ctx: lf_vardct.hf_block_ctx,
      block_info,
      jpeg_upsampling,
      lf_quant,
      hf_pass,
      coeff_shift,
      tracker,
    }
    @vardct.write_hf_coeff(bs, params, hf_coeff_output) catch {
      e if e.unexpected_eof() && allow_partial =>
        // Partially decoded HfCoeff
        return
      e => raise e
    }
  }
  if modular is Some(modular) {
    decode_pass_group_modular(
      bs, frame_header, global_ma_config, pass_idx, group_idx, modular, allow_partial,
      tracker, pool,
    )
  }
}

///|
pub fn decode_pass_group_modular(
  bs : @bitstream.Bitstream,
  frame_header : FrameHeader,
  global_ma_config : @modular.MaConfig?,
  pass_idx : Int32,
  group_idx : Int32,
  modular : @modular.TransformedModularSubimage,
  allow_partial : Bool,
  tracker : @grid.AllocTracker?,
  pool : @threadpool.JxlThreadPool,
) -> Unit raise @bitstream.JxlError {
  // `subimage.finish(pool)` upstream; `@modular`'s `finish` runs sequentially.
  let _ = pool
  if modular.is_empty() {
    return
  }
  let modular = modular.recursive(bs, global_ma_config, tracker)
  let subimage = modular.prepare_subimage()
  subimage.decode(
    bs,
    1 +
    3 * frame_header.num_lf_groups() +
    17 +
    pass_idx * frame_header.num_groups() +
    group_idx,
    allow_partial,
  )
  subimage.finish() |> ignore
}
