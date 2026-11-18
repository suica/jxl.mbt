///|
pub(all) struct LfGlobal {
  patches : Patches?
  splines : Splines?
  noise : NoiseParameters?
  lf_dequant : @vardct.LfChannelDequantization
  vardct : LfGlobalVarDct?
  gmodular : GlobalModular
}

///|
pub(all) struct LfGlobalParams {
  image_header : @image.ImageHeader
  frame_header : FrameHeader
  tracker : @grid.AllocTracker?
  allow_partial : Bool
}

///|
pub fn LfGlobalParams::new(
  image_header : @image.ImageHeader,
  frame_header : FrameHeader,
  tracker : @grid.AllocTracker?,
  allow_partial : Bool,
) -> LfGlobalParams {
  { image_header, frame_header, tracker, allow_partial, }
}

///|
pub fn LfGlobal::parse(
  bs : @bitstream.Bitstream,
  params : LfGlobalParams,
) -> LfGlobal raise @bitstream.JxlError {
  let { image_header, frame_header: header, .. } = params
  // `(header.width * header.height) as u64` (u32 multiplication)
  let image_size = (header.width.reinterpret_as_uint() *
  header.height.reinterpret_as_uint()).to_uint64()
  let patches = if header.flags.patches() {
    let patches = Patches::parse(bs, image_header, header)
    for patch in patches.patches {
      for target in patch.patch_targets {
        for blending_info in target.blending {
          if blending_info.mode.use_alpha() &&
            blending_info.alpha_channel >=
            image_header.metadata.ec_info.length() {
            raise ValidationFailed("blending_info.alpha_channel out of range")
          }
        }
      }
    }
    Some(patches)
  } else {
    None
  }
  let splines = if header.flags.splines() {
    Some(Splines::parse(bs, header))
  } else {
    None
  }
  let noise = if header.flags.noise() {
    Some(NoiseParameters::parse(bs))
  } else {
    None
  }
  let lf_dequant = @vardct.LfChannelDequantization::parse(bs)
  let modular_dequants : FixedArray[Float] = [
    lf_dequant.m_x_lf_unscaled(),
    lf_dequant.m_y_lf_unscaled(),
    lf_dequant.m_b_lf_unscaled(),
  ]
  let min_weight : Float = 1.0e-8
  if modular_dequants.iter().any(v => v < min_weight) {
    raise ValidationFailed("Modular dequant weight is too small")
  }
  let vardct = if header.encoding == VarDct {
    Some(LfGlobalVarDct::parse(bs))
  } else {
    None
  }
  if splines is Some(splines) {
    let base_correlation_xb = match vardct {
      Some(vardct) => {
        let lf_chan_corr = vardct.lf_chan_corr
        Some((lf_chan_corr.base_correlation_x, lf_chan_corr.base_correlation_b))
      }
      None => None
    }
    let estimated_area = splines.estimate_area(base_correlation_xb)
    // Maximum total_estimated_area_reached for Level 10
    let a = 1UL << 42
    let b = 1024UL * image_size + (1UL << 32)
    let max_estimated_area = if a < b { a } else { b }
    if estimated_area > max_estimated_area {
      raise ProfileConformance("too large estimated area for splines")
    }
    // Upstream warns (Level 5 limit) here; logging is dropped.
  }
  let gmodular = GlobalModular::parse(bs, params)
  { patches, splines, noise, lf_dequant, vardct, gmodular, }
}

///|
pub(all) struct LfGlobalVarDct {
  quantizer : @vardct.Quantizer
  hf_block_ctx : @vardct.HfBlockContext
  lf_chan_corr : @vardct.LfChannelCorrelation
}

///|
pub fn LfGlobalVarDct::parse(
  bs : @bitstream.Bitstream,
) -> LfGlobalVarDct raise @bitstream.JxlError {
  let quantizer = @vardct.Quantizer::parse(bs)
  let hf_block_ctx = @vardct.HfBlockContext::parse(bs)
  let lf_chan_corr = @vardct.LfChannelCorrelation::parse(bs)
  { quantizer, hf_block_ctx, lf_chan_corr, }
}

///|
pub struct GlobalModular {
  ma_config : @modular.MaConfig?
  modular : @modular.Modular
  priv extra_channel_from : Int32
  priv is_partial : Bool
}

///|
pub fn GlobalModular::try_clone(self : GlobalModular) -> GlobalModular {
  {
    ma_config: self.ma_config,
    modular: self.modular.try_clone(),
    extra_channel_from: self.extra_channel_from,
    is_partial: self.is_partial,
  }
}

///|
pub fn GlobalModular::ma_config(self : GlobalModular) -> @modular.MaConfig? {
  self.ma_config
}

///|
pub fn GlobalModular::extra_channel_from(self : GlobalModular) -> Int32 {
  self.extra_channel_from
}

///|
pub fn GlobalModular::is_partial(self : GlobalModular) -> Bool {
  self.is_partial
}

///|
pub fn GlobalModular::parse(
  bs : @bitstream.Bitstream,
  params : LfGlobalParams,
) -> GlobalModular raise @bitstream.JxlError {
  let { image_header, frame_header: header, tracker, allow_partial, } = params
  let num_channels = (header.encoded_color_channels() +
  image_header.metadata.ec_info.length()).to_uint64()
  let max_global_ma_nodes = 1024UL +
    header.width.reinterpret_as_uint().to_uint64() *
    header.height.reinterpret_as_uint().to_uint64() *
    num_channels /
    16UL
  let max_global_ma_nodes = if max_global_ma_nodes < 1UL << 22 {
    max_global_ma_nodes.to_int()
  } else {
    1 << 22
  }
  let ma_config_params : @modular.MaConfigParams = {
    tracker,
    node_limit: max_global_ma_nodes,
    depth_limit: 2048,
  }
  let ma_config = if bs.read_bool() {
    Some(@modular.MaConfig::parse(bs, ma_config_params))
  } else {
    None
  }
  let color_width = header.color_sample_width()
  let color_height = header.color_sample_height()
  let shifts : Array[@modular.ModularChannelParams] = []
  if header.encoding == Modular {
    if header.do_ycbcr {
      // Cb, Y, Cr
      for idx in 0..<3 {
        shifts.push(
          @modular.ModularChannelParams::jpeg(
            color_width,
            color_height,
            header.jpeg_upsampling,
            idx,
          ),
        )
      }
    } else {
      let channel_param = @modular.ModularChannelParams::new(
        color_width, color_height,
      )
      let channels = header.encoded_color_channels()
      for _ in 0..<channels {
        shifts.push(channel_param)
      }
    }
  }
  let extra_channel_from = shifts.length()
  let color_upsampling_shift = header.upsampling.ctz()
  let n = @cmp.minimum(
    header.ec_upsampling.length(),
    image_header.metadata.ec_info.length(),
  )
  for i in 0..<n {
    let ec_upsampling = header.ec_upsampling[i]
    let ec_info = image_header.metadata.ec_info[i]
    let ec_upsampling_shift = ec_upsampling.ctz()
    let dim_shift = ec_info.dim_shift
    let actual_dim_shift = ec_upsampling_shift +
      dim_shift -
      color_upsampling_shift
    let shift = @modular.ChannelShift::from_shift(actual_dim_shift)
    shifts.push(
      @modular.ModularChannelParams::with_shift(
        color_width, color_height, shift,
      ),
    )
  }
  let group_dim = header.group_dim()
  let modular_params = @modular.ModularParams::with_channels(
    group_dim,
    image_header.metadata.bit_depth.bits_per_sample(),
    shifts,
    ma_config,
    tracker,
  )
  let modular = @modular.Modular::parse(bs, modular_params)
  let mut is_partial = false
  if modular.image_mut() is Some(image) {
    let gmodular = image.prepare_gmodular()
    gmodular.decode(bs, 0, allow_partial)
    is_partial = gmodular.is_partial()
  }
  { ma_config, modular, extra_channel_from, is_partial, }
}
