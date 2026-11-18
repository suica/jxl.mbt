// Glue between the render pipeline types (ImageWithRegion, Region, frame
// headers) and the filter/feature kernels ported on plain values
// (`*_raw`/`*_grids` functions). These are the upstream entry points of
// filter/{gabor,epf,ycbcr}.rs and features/{upsampling,spline,noise,
// spot_colors}.rs.

///|
/// Gabor-like filter on the color channels of `fb` within
/// `color_padded_region`. The filtered channels are swapped into `fb`, and
/// the previous buffers end up in `fb_scratch`.
pub fn apply_gabor_like(
  fb : ImageWithRegion,
  color_padded_region : Region,
  fb_scratch : FixedArray[@grid.Grid[Float]],
  weights : FixedArray[FixedArray[Float]],
) -> Unit {
  let region = fb.regions_and_shifts()[0].0
  guard region.contains(color_padded_region) else {
    abort("apply_gabor_like: region does not contain color_padded_region")
  }
  let left = abs_diff(region.left, color_padded_region.left)
  let top = abs_diff(region.top, color_padded_region.top)
  let buffers = fb.as_color_floats_mut()
  let views = []
  for g in buffers {
    views.push(
      g
      .as_subgrid()
      .subgrid(left, top, color_padded_region.width, color_padded_region.height),
    )
  }
  apply_gabor_like_grids(
    views,
    [fb_scratch[0], fb_scratch[1], fb_scratch[2]],
    weights,
  )
  let left = color_padded_region.left
  let top = color_padded_region.top
  for idx in 0..<3 {
    let grid = fb_scratch[idx]
    let region : Region = {
      width: grid.width(),
      height: grid.height(),
      left,
      top,
    }
    fb_scratch[idx] = fb.swap_channel_f32(idx, grid, region)
  }
}

///|
/// Edge-preserving filter on the color channels of `fb`.
pub fn apply_epf(
  fb_image : ImageWithRegion,
  fb_scratch_arr : FixedArray[@grid.Grid[Float]],
  color_padded_region : Region,
  lf_groups : Map[Int32, @frame.LfGroup],
  frame_header : @frame.FrameHeader,
  epf_params : @frame.EpfParams,
) -> Unit {
  let region = fb_image.regions_and_shifts()[0].0
  guard region.contains(color_padded_region) else {
    abort("apply_epf: region does not contain color_padded_region")
  }
  let left = abs_diff(region.left, color_padded_region.left)
  let top = abs_diff(region.top, color_padded_region.top)
  let fb = []
  for g in fb_image.as_color_floats_mut() {
    fb.push(
      g
      .as_subgrid()
      .subgrid(left, top, color_padded_region.width, color_padded_region.height),
    )
  }
  let num_lf_groups = frame_header.num_lf_groups()
  let sigma_grid_map : Array[@grid.Grid[Float]?] = Array::make(
    num_lf_groups,
    None,
  )
  for lf_group_idx, lf_group in lf_groups {
    if lf_group.hf_meta is Some(hf_meta) {
      sigma_grid_map[lf_group_idx] = Some(hf_meta.epf_sigma)
    }
  }
  let params : EpfKernelParams = {
    iters: epf_params.iters,
    channel_scale: epf_params.channel_scale,
    pass0_sigma_scale: epf_params.sigma.pass0_sigma_scale,
    pass2_sigma_scale: epf_params.sigma.pass2_sigma_scale,
    border_sad_mul: epf_params.sigma.border_sad_mul,
    sigma_for_modular: epf_params.sigma_for_modular,
  }
  let scratch = [fb_scratch_arr[0], fb_scratch_arr[1], fb_scratch_arr[2]]
  let result_in_scratch = apply_epf_grids(
    fb,
    scratch,
    color_padded_region.left,
    color_padded_region.top,
    color_padded_region.width,
    color_padded_region.height,
    frame_header.group_dim(),
    frame_header.lf_groups_per_row(),
    sigma_grid_map,
    params,
  )
  if result_in_scratch {
    let left = color_padded_region.left
    let top = color_padded_region.top
    for idx, grid in scratch {
      let region : Region = {
        width: grid.width(),
        height: grid.height(),
        left,
        top,
      }
      fb_image.replace_channel(idx, F32(grid), region)
    }
  }
}

///|
/// JPEG-style chroma upsampling of one channel.
pub fn apply_jpeg_upsampling_single(
  grid : @grid.SubGrid[Float],
  shift : @modular.ChannelShift,
  target_region : Region,
  tracker : @grid.AllocTracker?,
) -> @grid.Grid[Float] raise @bitstream.JxlError {
  apply_jpeg_upsampling_single_raw(
    grid,
    shift.hshift(),
    shift.vshift(),
    target_region.width,
    target_region.height,
    tracker,
  )
}

///|
/// Non-separable upsampling by `1 << factor`; `out_region` is upsampled by
/// `factor`.
pub fn upsample(
  grid : @grid.SubGrid[Float],
  out_region : Ref[Region],
  image_header : @image.ImageHeader,
  factor : Int32,
  tracker : @grid.AllocTracker?,
) -> @grid.Grid[Float]? raise @bitstream.JxlError {
  let metadata = image_header.metadata
  let out = upsample_raw(
    grid,
    metadata.up2_weight,
    metadata.up4_weight,
    metadata.up8_weight,
    factor,
    tracker,
  )
  out_region.val = out_region.val.upsample(factor)
  out
}

///|
/// Renders splines onto the color channels of `base_grid`.
pub fn render_spline(
  frame_header : @frame.FrameHeader,
  base_grid : ImageWithRegion,
  splines : @frame.Splines,
  base_correlations_xb : (Float, Float)?,
) -> Unit raise @bitstream.JxlError {
  let region = base_grid.regions_and_shifts()[0].0
  let channels = base_grid.as_color_floats_mut()
  let channels = [channels[0], channels[1], channels[2]]
  for quant_spline in splines.quant_splines {
    render_spline_raw(
      frame_header.width,
      frame_header.height,
      channels,
      region.left,
      region.top,
      quant_spline.quant_points,
      quant_spline.xyb_dct,
      quant_spline.sigma_dct,
      splines.quant_adjust,
      base_correlations_xb,
    )
  }
}

///|
/// Renders noise onto the color channels of `grid`.
pub fn render_noise(
  header : @frame.FrameHeader,
  visible_frames_num : Int32,
  invisible_frames_num : Int32,
  base_correlations_xb : (Float, Float)?,
  grid : ImageWithRegion,
  params : @frame.NoiseParameters,
) -> Unit raise @bitstream.JxlError {
  let (region, shift) = grid.regions_and_shifts()[0]
  let tracker = grid.alloc_tracker()
  let xyb = grid.as_color_floats_mut()
  let full_frame_region = Region::with_size(header.width, header.height)
  let actual_region = region
    .intersection(full_frame_region)
    .downsample_with_shift(shift)
  render_noise_raw(
    header.width,
    header.height,
    header.group_dim(),
    visible_frames_num,
    invisible_frames_num,
    base_correlations_xb,
    xyb[0],
    xyb[1],
    xyb[2],
    actual_region.left,
    actual_region.top,
    actual_region.width,
    actual_region.height,
    params.lut,
    tracker,
  )
}

///|
/// Renders a spot color channel onto color_channels.
pub fn render_spot_color(
  color_channels : FixedArray[@grid.Grid[Float]],
  ec_grid : @grid.Grid[Float],
  ec_ty : @image.ExtraChannelType,
) -> Unit raise @bitstream.JxlError {
  guard ec_ty is SpotColour(red~, green~, blue~, solidity~) else {
    raise @bitstream.NotSupported("EC type is not SpotColour")
  }
  if color_channels.length() != 3 {
    return
  }
  render_spot_color_raw(
    [color_channels[0], color_channels[1], color_channels[2]],
    ec_grid,
    red,
    green,
    blue,
    solidity,
  )
}
