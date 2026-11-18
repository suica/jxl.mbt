///|
/// Converts a region in the image to the corresponding region in `frame`.
pub fn image_region_to_frame(
  frame : IndexedFrame,
  image_region : Region,
  ignore_lf_level : Bool,
) -> Region {
  let image_header = frame.image_header()
  let frame_header = frame.header()
  let full_frame_region = Region::with_size(
    frame_header.width,
    frame_header.height,
  )
  let frame_region = if frame_header.frame_type is ReferenceOnly {
    full_frame_region
  } else {
    let region = apply_orientation_to_image_region(image_header, image_region)
    region
    .translate(-frame_header.x0, -frame_header.y0)
    .intersection(full_frame_region)
  }
  if ignore_lf_level {
    frame_region
  } else {
    frame_region.downsample(frame_header.lf_level * 3)
  }
}

///|
pub fn apply_orientation_to_image_region(
  image_header : @image.ImageHeader,
  image_region : Region,
) -> Region {
  image_region.apply_orientation(image_header)
}

///|
pub fn pad_lf_region(
  frame_header : @frame.FrameHeader,
  frame_region : Region,
) -> Region {
  if frame_header.lf_level != 0 {
    // Lower level frames might be padded, so apply padding to LF frames
    frame_region.pad(4 * frame_header.lf_level + 32)
  } else {
    frame_region
  }
}

///|
/// `u32::ilog2` for a positive value.
fn ilog2(x : Int32) -> Int32 {
  31 - x.clz()
}

///|
pub fn pad_upsampling(
  image_header : @image.ImageHeader,
  frame_header : @frame.FrameHeader,
  frame_region : Region,
) -> Region {
  let color_upsample_factor = frame_header.upsampling.ctz()
  let ec_info = image_header.metadata.ec_info
  let n = min_int(frame_header.ec_upsampling.length(), ec_info.length())
  let max_upsample_factor = if n == 0 {
    color_upsample_factor
  } else {
    let mut m = 0
    for i in 0..<n {
      let f = ilog2(frame_header.ec_upsampling[i]) + ec_info[i].dim_shift
      if i == 0 || f > m {
        m = f
      }
    }
    m
  }
  if max_upsample_factor > 0 {
    // Additional upsampling pass is needed for every 3 levels of upsampling factor.
    frame_region
    .downsample(max_upsample_factor)
    .pad(2 + (max_upsample_factor - 1) / 3)
    .upsample(max_upsample_factor)
  } else {
    frame_region
  }
}

///|
pub fn pad_color_region(
  image_header : @image.ImageHeader,
  frame_header : @frame.FrameHeader,
  frame_region : Region,
) -> Region {
  let color_upsample_factor = ilog2(frame_header.upsampling)
  let mut color_padded_region = pad_upsampling(
    image_header, frame_header, frame_region,
  ).downsample(color_upsample_factor)
  // TODO: actual region could be smaller.
  if frame_header.restoration_filter.epf is Enabled(epf_params) {
    // EPF references adjacent samples.
    let iters = epf_params.iters
    color_padded_region = if iters == 1 {
      color_padded_region.pad(2)
    } else if iters == 2 {
      color_padded_region.pad(5)
    } else {
      color_padded_region.pad(6)
    }
  }
  if frame_header.restoration_filter.gab.enabled() {
    // Gabor-like filter references adjacent samples.
    color_padded_region = color_padded_region.pad(1)
  }
  if frame_header.do_ycbcr {
    // Chroma upsampling references adjacent samples.
    color_padded_region = color_padded_region.pad(1).downsample(2).upsample(2)
  }
  if frame_header.restoration_filter.epf.enabled() {
    // EPF performs filtering in 8x8 blocks.
    color_padded_region = color_padded_region.container_aligned(8)
  }
  color_padded_region
}

///|
/// jxl-grid `MutableSubgrid::into_groups_with_fixed_count`.
fn[T] into_groups_with_fixed_count(
  grid : @grid.SubGrid[T],
  group_width : Int32,
  group_height : Int32,
  num_cols : Int32,
  num_rows : Int32,
) -> Array[@grid.SubGrid[T]] {
  let width = grid.width
  let height = grid.height
  let groups = []
  for gy in 0..<num_rows {
    let y = min_int(gy * group_height, height)
    let gh = min_int(height - y, group_height)
    for gx in 0..<num_cols {
      let x = min_int(gx * group_width, width)
      let gw = min_int(width - x, group_width)
      let offset = if gh > 0 && width > 0 { y * grid.stride + x } else { 0 }
      groups.push(
        @grid.SubGrid::from_buf(
          grid.buf,
          grid.offset + offset,
          gw,
          gh,
          grid.stride,
        ),
      )
    }
  }
  groups
}

///|
priv struct LfGroupJob {
  idx : Int32
  mut lf_group : @frame.LfGroup?
  mut modular : @modular.TransformedModularSubimage?
  lf_xyb : FixedArray[@grid.SubGrid[Float]]?
}

///|
/// Loads LF groups intersecting `lf_region` into `lf_groups`, and returns
/// dequantized LF images for VarDCT frames without an LF frame.
pub fn load_lf_groups(
  frame : IndexedFrame,
  lf_global : @frame.LfGlobal,
  lf_groups : Map[Int32, @frame.LfGroup],
  mlf_groups : Array[@modular.TransformedModularSubimage],
  lf_region : Region,
) -> ImageWithRegion? raise @bitstream.JxlError {
  let frame_header = frame.header()
  let lf_global_vardct = lf_global.vardct
  let global_ma_config = lf_global.gmodular.ma_config()
  let has_lf_frame = frame_header.flags.use_lf_frame()
  let jpeg_upsampling = frame_header.jpeg_upsampling
  let shifts_cbycr = FixedArray::makei(3, idx => {
    @modular.ChannelShift::from_jpeg_upsampling(jpeg_upsampling, idx)
  })
  let lf_xyb = if lf_global_vardct is Some(_) &&
    !frame_header.flags.use_lf_frame() {
    let tracker = frame.alloc_tracker()
    let out = ImageWithRegion::new(3, tracker)
    let width = lf_region.width
    let height = lf_region.height
    for shift in shifts_cbycr {
      let (width, height) = shift.shift_size((width, height))
      let buffer = @grid.Grid::with_alloc_tracker(
        width,
        height,
        (0.0 : Float),
        tracker,
      )
      out.append_channel_shifted(F32(buffer), lf_region, shift)
    }
    Some(out)
  } else {
    None
  }
  let lf_groups_per_row = frame_header.lf_groups_per_row()
  let group_dim = frame_header.group_dim()
  let num_lf_groups = frame_header.num_lf_groups()
  let lf_group_base_x = lf_region.left / group_dim
  let lf_group_base_y = lf_region.top / group_dim
  let num_cols = (lf_region.width + group_dim - 1) / group_dim
  let num_rows = (lf_region.height + group_dim - 1) / group_dim
  let lf_xyb_groups = match lf_xyb {
    Some(lf_xyb) => {
      let arr = lf_xyb.as_color_floats_mut()
      Some(
        FixedArray::makei(3, idx => {
          let grid = arr[idx].as_subgrid()
          let shift = shifts_cbycr[idx]
          let group_width = group_dim >> shift.hshift()
          let group_height = group_dim >> shift.vshift()
          into_groups_with_fixed_count(
            grid, group_width, group_height, num_cols, num_rows,
          )
        }),
      )
    }
    None => None
  }
  let jobs : Array[LfGroupJob] = []
  for idx in 0..<num_lf_groups {
    let modular = if idx < mlf_groups.length() {
      Some(mlf_groups[idx])
    } else {
      None
    }
    let lf_group_x = idx % lf_groups_per_row
    let lf_group_y = idx / lf_groups_per_row
    let lf_group_region : Region = {
      left: lf_group_x * group_dim,
      top: lf_group_y * group_dim,
      width: group_dim,
      height: group_dim,
    }
    if lf_region.intersection(lf_group_region).is_empty() {
      continue
    }
    let xyb_group_idx = (lf_group_y - lf_group_base_y) * num_cols +
      (lf_group_x - lf_group_base_x)
    let lf_xyb = match lf_xyb_groups {
      Some(groups) =>
        Some(
          (
            [
              groups[0][xyb_group_idx],
              groups[1][xyb_group_idx],
              groups[2][xyb_group_idx],
            ] : FixedArray[_]),
        )
      None => None
    }
    jobs.push({ idx, lf_group: None, modular, lf_xyb, })
  }
  let mut result : @bitstream.JxlError? = None
  for job in jobs {
    let idx = job.idx
    let loaded = match job.lf_group {
      Some(g) => !g.partial
      None => false
    }
    if !loaded {
      let modular = job.modular
      job.modular = None
      let parse_result = frame.try_parse_lf_group(
        lf_global_vardct, global_ma_config, modular, idx,
      ) catch {
        e => {
          result = Some(e)
          continue
        }
      }
      match parse_result {
        Some(g) => job.lf_group = Some(g)
        None => continue
      }
    }
    let lf_group = job.lf_group.unwrap()
    if !has_lf_frame && job.lf_xyb is Some(lf_xyb) {
      let lf_global_vardct = lf_global_vardct.unwrap()
      let lf_group_x = idx % lf_groups_per_row
      let lf_group_y = idx / lf_groups_per_row
      let lf_group_region : Region = {
        left: lf_group_x * frame_header.group_dim(),
        top: lf_group_y * frame_header.group_dim(),
        width: group_dim,
        height: group_dim,
      }
      if lf_region.intersection(lf_group_region).is_empty() {
        continue
      }
      let quantizer = lf_global_vardct.quantizer
      let lf_coeff = lf_group.lf_coeff.unwrap()
      let channel_data = lf_coeff.lf_quant.image().unwrap().image_channels()
      copy_lf_dequant(
        lf_xyb[0],
        quantizer,
        lf_global.lf_dequant.m_x_lf,
        channel_data[1],
        lf_coeff.extra_precision,
      )
      copy_lf_dequant(
        lf_xyb[1],
        quantizer,
        lf_global.lf_dequant.m_y_lf,
        channel_data[0],
        lf_coeff.extra_precision,
      )
      copy_lf_dequant(
        lf_xyb[2],
        quantizer,
        lf_global.lf_dequant.m_b_lf,
        channel_data[2],
        lf_coeff.extra_precision,
      )
    }
  }
  for job in jobs {
    if job.lf_group is Some(group) {
      lf_groups[job.idx] = group
    }
  }
  if result is Some(e) {
    raise e
  }
  lf_xyb
}

///|
/// Converts the color channels for recording as a reference (save_before_ct
/// = false): YCbCr → RGB, or XYB → the signalled enum color encoding.
pub fn convert_color_for_record(
  image_header : @image.ImageHeader,
  do_ycbcr : Bool,
  fb : ImageWithRegion,
) -> Unit raise @bitstream.JxlError {
  let metadata = image_header.metadata
  if do_ycbcr {
    // xyb_encoded = false
    fb.convert_modular_color(metadata.bit_depth)
    let cby = fb.as_color_floats_mut()
    @color.ycbcr_to_rgb(cby[0].buf(), cby[1].buf(), cby[2].buf())
    if metadata.colour_encoding.colour_space() is Grey {
      fb.remove_color_channels(1)
    }
    fb.set_ct_done(true)
  } else if metadata.xyb_encoded {
    // want_icc = false || is_last = true
    // in any case, blending does not occur when want_icc = true
    guard metadata.colour_encoding is Enum(encoding) else { return }
    match encoding.colour_space {
      Xyb => return
      Unknown => return
      _ => ()
    }
    fb.convert_modular_color(metadata.bit_depth)
    let xyb = fb.as_color_floats_mut()
    let transform = @color.ColorTransform::new(
      @color.ColorEncodingWithProfile::new(
        @color.EnumColourEncoding::xyb(@color.RenderingIntent::Perceptual),
      ),
      @color.ColorEncodingWithProfile::new(encoding),
      metadata.opsin_inverse_matrix,
      metadata.tone_mapping,
      (@color.NullCms::{ } : &@color.ColorManagementSystem),
    )
    let output_channels = transform.run([
      xyb[0].buf(),
      xyb[1].buf(),
      xyb[2].buf(),
    ])
    fb.remove_color_channels(output_channels)
    fb.set_ct_done(true)
  }
}

///|
/// Mirrors `offset` into `0..len`.
pub fn mirror(offset : Int32, len : Int32) -> Int32 {
  let mut offset = offset
  while true {
    if offset < 0 {
      offset = -(offset + 1)
    } else if offset >= len {
      offset = -(offset + 1) + len * 2
    } else {
      return offset
    }
  }
  offset
}

///|
/// A grid with `padding` samples of padding on each side.
pub struct PaddedGrid[S] {
  grid : @grid.Grid[S]
  padding : Int32
}

///|
pub fn[S] PaddedGrid::with_alloc_tracker(
  width : Int32,
  height : Int32,
  padding : Int32,
  init : S,
  tracker : @grid.AllocTracker?,
) -> PaddedGrid[S] raise @bitstream.JxlError {
  {
    grid: @grid.Grid::with_alloc_tracker(
      width + padding * 2,
      height + padding * 2,
      init,
      tracker,
    ),
    padding,
  }
}

///|
pub fn[S] PaddedGrid::buf_padded(self : PaddedGrid[S]) -> FixedArray[S] {
  self.grid.buf()
}

///|
pub fn[S] PaddedGrid::buf_padded_mut(self : PaddedGrid[S]) -> FixedArray[S] {
  self.grid.buf()
}

///|
pub fn[S] PaddedGrid::mirror_edges_padding(self : PaddedGrid[S]) -> Unit {
  let padding = self.padding
  let stride = self.grid.width()
  let height = self.grid.height() - padding * 2
  // Mirror horizontally.
  let buf = self.grid.buf()
  for y in padding..<(height + padding) {
    for x in 0..<padding {
      buf[y * stride + x] = buf[y * stride + padding * 2 - x - 1]
      buf[(y + 1) * stride - x - 1] = buf[(y + 1) * stride - padding * 2 + x]
    }
  }
  // Mirror vertically.
  for i in 0..<padding {
    // out row i <- in row (2 * padding - 1 - i)
    FixedArray::blit_to(
      buf,
      buf,
      len=stride,
      src_offset=(2 * padding - 1 - i) * stride,
      dst_offset=i * stride,
    )
  }
  let total_rows = height + padding * 2
  for i in 0..<padding {
    // out row (height + padding + i) <- in row (height + padding - 1 - i)
    let out_row = height + padding + i
    if out_row >= total_rows {
      break
    }
    FixedArray::blit_to(
      buf,
      buf,
      len=stride,
      src_offset=(height + padding - 1 - i) * stride,
      dst_offset=out_row * stride,
    )
  }
}
