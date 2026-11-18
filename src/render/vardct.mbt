// Port of jxl-render vardct/mod.rs: VarDCT frame rendering glue. The
// transforms themselves live in package `vardct`.
//
// Upstream decodes the quantized HF coefficients as `i32` into the same
// buffers that later hold the dequantized `f32` coefficients (by
// reinterpreting the grid). Here the coefficients are decoded into separate
// `Int` grids of the same shape, and dequantization reads them from there.

///|
priv struct VardctGroupJob {
  group_idx : Int32
  grid_xyb : FixedArray[@grid.SubGrid[Float]]
  coeff_xyb : FixedArray[@grid.SubGrid[Int32]]
  lf_group : @frame.LfGroup
}

///|
fn render_vardct(
  frame : IndexedFrame,
  lf_frame : Reference?,
  cache : RenderCache,
  region : Region,
  pool : @threadpool.JxlThreadPool,
) -> ImageWithRegion raise @bitstream.JxlError {
  let image_header = frame.image_header()
  let frame_header = frame.header()
  let tracker = frame.alloc_tracker()
  let jpeg_upsampling = frame_header.jpeg_upsampling
  let subsampled = jpeg_upsampling[0] != 0 ||
    jpeg_upsampling[1] != 0 ||
    jpeg_upsampling[2] != 0
  let shifts_cbycr = FixedArray::makei(3, idx => {
    @modular.ChannelShift::from_jpeg_upsampling(jpeg_upsampling, idx)
  })
  let lf_global = match cache.lf_global {
    Some(x) if !x.gmodular.is_partial() => x
    _ => {
      guard unwrap_opt_result(parse_lf_global(frame, cache.narrow))
        is Some(lf_global) else {
        raise incomplete_frame()
      }
      cache.lf_global = Some(lf_global)
      lf_global
    }
  }
  if lf_frame is Some(_) && lf_global.gmodular.is_partial() {
    raise incomplete_frame()
  }
  let gmodular = lf_global.gmodular.try_clone()
  let lf_global_vardct = lf_global.vardct.unwrap()
  let width = frame_header.color_sample_width()
  let height = frame_header.color_sample_height()
  let (width_rounded, height_rounded) = {
    let mut bw = (width + 7) / 8
    let mut bh = (height + 7) / 8
    let mut h_upsample = false
    let mut v_upsample = false
    for j in jpeg_upsampling {
      if j == 1 || j == 2 {
        h_upsample = true
      }
      if j == 1 || j == 3 {
        v_upsample = true
      }
    }
    if h_upsample {
      bw = (bw + 1) / 2 * 2
    }
    if v_upsample {
      bh = (bh + 1) / 2 * 2
    }
    (bw * 8, bh * 8)
  }
  let aligned_region = region.container_aligned(frame_header.group_dim())
  let aligned_lf_region = {
    // group_dim is multiple of 8
    let aligned_region_div8 : Region = {
      left: aligned_region.left / 8,
      top: aligned_region.top / 8,
      width: aligned_region.width / 8,
      height: aligned_region.height / 8,
    }
    let r = if frame_header.flags.skip_adaptive_lf_smoothing() {
      aligned_region_div8
    } else {
      aligned_region_div8.pad(1)
    }
    r.container_aligned(frame_header.group_dim())
  }
  let aligned_region = aligned_region.intersection(
    Region::with_size(width_rounded, height_rounded),
  )
  let aligned_lf_region = aligned_lf_region.intersection(
    Region::with_size(width_rounded / 8, height_rounded / 8),
  )
  let modular_region = compute_modular_region(
    frame_header, gmodular, aligned_region, false,
  )
  let modular_lf_region = compute_modular_region(
    frame_header, gmodular, aligned_lf_region, true,
  ).intersection(Region::with_size(width_rounded / 8, height_rounded / 8))
  let modular_image = gmodular.modular.image_mut()
  let (lf_group_image, pass_group_image) = match modular_image {
    Some(image) => {
      let groups = image.prepare_groups(frame.pass_shifts())
      (groups.lf_groups, groups.pass_groups)
    }
    None => {
      let passes = frame_header.passes.num_passes
      let ret : Array[Array[@modular.TransformedModularSubimage]] = []
      for _ in 0..<passes {
        ret.push([])
      }
      ([], ret)
    }
  }
  let group_dim = frame_header.group_dim()
  let result : Ref[@bitstream.JxlError?] = Ref(None)
  let (fb, lf_xyb) = pool.scope(scope => {
    if cache.hf_global is None {
      scope.spawn(_ => {
        // Parse HfGlobal
        try
          unwrap_opt_result(frame.try_parse_hf_global(Some(lf_global)))
        catch {
          e => result.val = Some(e)
        } noraise {
          hf_global => cache.hf_global = hf_global
        }
      })
    }
    // Load LF groups
    let lf_xyb = load_lf_groups(
      frame,
      lf_global,
      cache.lf_groups,
      lf_group_image,
      modular_lf_region,
      pool,
    )
    let lf_xyb = match lf_frame {
      Some(x) => {
        // Copy LFQuant
        let lf_frame = x.image.run_with_image()
        lf_frame.blend(None).try_clone()
      }
      None => {
        let lf_xyb = lf_xyb.unwrap()
        if !subsampled {
          // LF CfL
          chroma_from_luma_lf(
            lf_xyb.as_color_floats_mut(),
            lf_global_vardct.lf_chan_corr,
          )
        }
        if !frame_header.flags.skip_adaptive_lf_smoothing() {
          adaptive_lf_smoothing(
            shifts_cbycr,
            lf_xyb.as_color_floats_mut(),
            lf_global.lf_dequant,
            lf_global_vardct.quantizer,
            tracker,
          )
        }
        lf_xyb
      }
    }
    let fb = {
      let width = modular_region.width
      let height = modular_region.height
      let fb = ImageWithRegion::new(3, tracker)
      for shift in shifts_cbycr {
        let (w8, h8) = shift.shift_size(((width + 7) / 8, (height + 7) / 8))
        let width = w8 * 8
        let height = h8 * 8
        let buffer = @grid.Grid::with_alloc_tracker(
          width,
          height,
          (0.0 : Float),
          tracker,
        )
        fb.append_channel_shifted(F32(buffer), modular_region, shift)
      }
      fb
    }
    (fb, lf_xyb)
  })
  if result.val is Some(e) {
    raise e
  }
  let hf_global = cache.hf_global
  let lf_groups = cache.lf_groups
  // Prepare PassGroup
  let it : Array[VardctGroupJob] = []
  for item in fb.color_groups_with_group_id(frame_header) {
    let (group_idx, grid_xyb) = item
    let lf_group_idx = frame_header.lf_group_idx_from_group_idx(group_idx)
    guard lf_groups.get(lf_group_idx) is Some(lf_group) else { continue }
    let coeff_xyb = FixedArray::makei(3, c => {
      let g = grid_xyb[c]
      @grid.Grid::new(g.width, g.height, 0).as_subgrid()
    })
    it.push({ group_idx, grid_xyb, coeff_xyb, lf_group, })
  }
  // Decode PassGroup
  if hf_global is Some(hf_global) {
    let mut result : @bitstream.JxlError? = None
    for pass_idx, pass_image in pass_group_image {
      let global_ma_config = gmodular.ma_config
      for job in it {
        let group_idx = job.group_idx
        if job.lf_group.hf_meta is None {
          continue
        }
        let bitstream = match frame.pass_group_bitstream(pass_idx, group_idx) {
          Some(Ok(bitstream)) => bitstream
          Some(Err(e)) => {
            result = Some(e)
            continue
          }
          None => continue
        }
        let allow_partial = bitstream.partial
        let modular = if group_idx < pass_image.length() {
          Some(pass_image[group_idx])
        } else {
          None
        }
        @frame.decode_pass_group(bitstream.bitstream, {
          frame_header,
          lf_group: job.lf_group,
          pass_idx,
          group_idx,
          global_ma_config,
          modular,
          vardct: Some({
            lf_vardct: lf_global_vardct,
            hf_global,
            hf_coeff_output: job.coeff_xyb,
          }),
          allow_partial,
          tracker,
        }) catch {
          e => if !allow_partial { result = Some(e) }
        }
      }
    }
    if result is Some(e) {
      raise e
    }
  }
  // Dequant and transform
  let groups_per_row = frame_header.groups_per_row()
  for job in it {
    let group_idx = job.group_idx
    let grid_xyb = job.grid_xyb
    let lf_group = job.lf_group
    let group_x = group_idx % groups_per_row
    let group_y = group_idx / groups_per_row
    let transform_hf = {
      let group_region : Region = {
        left: group_x * group_dim,
        top: group_y * group_dim,
        width: group_dim,
        height: group_dim,
      }
      !group_region.intersection(aligned_region).is_empty()
    }
    guard lf_group.hf_meta is Some(hf_meta) &&
      hf_global is Some(hf_global) &&
      transform_hf else {
      transform_with_lf_grouped(
        lf_xyb, grid_xyb, group_idx, frame_header, lf_groups,
      )
      continue
    }
    dequant_hf_varblock_grouped(
      grid_xyb,
      job.coeff_xyb,
      group_idx,
      image_header,
      frame_header,
      lf_global,
      lf_groups,
      hf_global,
    )
    if !subsampled {
      let lf_chan_corr = lf_global_vardct.lf_chan_corr
      let cfl_base_x = group_x % 8 * group_dim / 64
      let cfl_base_y = group_y % 8 * group_dim / 64
      let gw = (grid_xyb[0].width + 63) / 64
      let gh = (grid_xyb[0].height + 63) / 64
      let x_from_y = hf_meta.x_from_y
        .as_subgrid()
        .subgrid(cfl_base_x, cfl_base_y, gw, gh)
      let b_from_y = hf_meta.b_from_y
        .as_subgrid()
        .subgrid(cfl_base_x, cfl_base_y, gw, gh)
      chroma_from_luma_hf_grouped(grid_xyb, x_from_y, b_from_y, lf_chan_corr)
    }
    transform_with_lf_grouped(
      lf_xyb, grid_xyb, group_idx, frame_header, lf_groups,
    )
  }
  if modular_image is Some(modular_image) {
    // Extra channel inverse transform
    let subimage = modular_image.prepare_subimage() catch {
      e => abort("prepare_subimage: \{@debug.to_string(e)}")
    }
    ignore(subimage.finish())
    fb.extend_from_gmodular(gmodular, narrow=cache.narrow)
  }
  fb
}

///|
/// Dequantizes LF coefficients of one channel into `grid`.
fn copy_lf_dequant(
  grid : @grid.SubGrid[Float],
  quantizer : @vardct.Quantizer,
  m_lf : Float,
  channel_data : @grid.Grid[Int32],
  extra_precision : Int32,
) -> Unit {
  guard grid.width >= channel_data.width() &&
    grid.height >= channel_data.height() else {
    abort("copy_lf_dequant: grid too small")
  }
  let precision_scale = 1 << (9 - extra_precision)
  let scale_inv = quantizer.global_scale.to_uint64() *
    quantizer.quant_lf.to_uint64()
  let scale = Float::from_double(
    m_lf.to_double() * precision_scale.to_double() / scale_inv.to_double(),
  )
  let width = channel_data.width()
  let height = channel_data.height()
  let buf = channel_data.buf()
  for y in 0..<height {
    let row = grid.row_offset(y)
    let quant = y * width
    for x in 0..<width {
      grid.buf[row + x] = Float::from_int(buf[quant + x]) * scale
    }
  }
}

///|
/// Adaptive LF smoothing of the dequantized LF image.
fn adaptive_lf_smoothing(
  shifts : FixedArray[@modular.ChannelShift],
  lf_image : FixedArray[@grid.Grid[Float]],
  lf_dequant : @vardct.LfChannelDequantization,
  quantizer : @vardct.Quantizer,
  tracker : @grid.AllocTracker?,
) -> Unit raise @bitstream.JxlError {
  let scale_inv = (quantizer.global_scale.to_uint64() *
  quantizer.quant_lf.to_uint64()).to_double()
  let lf_x = Float::from_double(
    512.0 * lf_dequant.m_x_lf.to_double() / scale_inv,
  )
  let lf_y = Float::from_double(
    512.0 * lf_dequant.m_y_lf.to_double() / scale_inv,
  )
  let lf_b = Float::from_double(
    512.0 * lf_dequant.m_b_lf.to_double() / scale_inv,
  )
  let in_x = lf_image[0]
  let in_y = lf_image[1]
  let in_b = lf_image[2]
  let width = max_int(in_x.width(), max_int(in_y.width(), in_b.width()))
  let height = max_int(in_x.height(), max_int(in_y.height(), in_b.height()))
  adaptive_lf_smoothing_impl(
    width,
    height,
    shifts,
    [in_x.buf(), in_y.buf(), in_b.buf()],
    [lf_x, lf_y, lf_b],
    tracker,
  )
}

///|
fn dequant_hf_varblock_grouped(
  out : FixedArray[@grid.SubGrid[Float]],
  coeff_in : FixedArray[@grid.SubGrid[Int32]],
  group_idx : Int32,
  image_header : @image.ImageHeader,
  frame_header : @frame.FrameHeader,
  lf_global : @frame.LfGlobal,
  lf_groups : Map[Int32, @frame.LfGroup],
  hf_global : @frame.HfGlobal,
) -> Unit {
  let shifts_cbycr = FixedArray::makei(3, idx => {
    @modular.ChannelShift::from_jpeg_upsampling(
      frame_header.jpeg_upsampling,
      idx,
    )
  })
  let oim = image_header.metadata.opsin_inverse_matrix
  let quantizer = lf_global.vardct.unwrap().quantizer
  let dequant_matrices = hf_global.dequant_matrices
  let qm_scale : FixedArray[Float] = [
    powi_f32(0.8, frame_header.x_qm_scale - 2),
    1.0,
    powi_f32(0.8, frame_header.b_qm_scale - 2),
  ]
  let quant_bias_numerator = oim.quant_bias_numerator
  let group_dim = frame_header.group_dim()
  let groups_per_row = frame_header.groups_per_row()
  let group_x = group_idx % groups_per_row
  let group_y = group_idx / groups_per_row
  let lf_group_idx = frame_header.lf_group_idx_from_group_idx(group_idx)
  guard lf_groups.get(lf_group_idx) is Some(lf_group) else { return }
  let left_in_lf = group_x % 8 * (group_dim / 8)
  let top_in_lf = group_y % 8 * (group_dim / 8)
  guard lf_group.hf_meta is Some(hf_meta) else { return }
  let block_info = hf_meta.block_info
  let lf_width = min_int(block_info.width() - left_in_lf, group_dim / 8)
  let lf_height = min_int(block_info.height() - top_in_lf, group_dim / 8)
  let block_info = block_info
    .as_subgrid()
    .subgrid(left_in_lf, top_in_lf, lf_width, lf_height)
  for channel in 0..<3 {
    let coeff = out[channel]
    let coeff_q = coeff_in[channel]
    let quant_bias = oim.quant_bias[channel]
    let shift = shifts_cbycr[channel]
    for_each_varblocks(block_info, shift, fn(info) {
      let (shifted_bx, shifted_by, dct_select, hf_mul) = info
      let (bw, bh) = dct_select.dct_select_size()
      let left = shifted_bx * 8
      let top = shifted_by * 8
      let width = bw * 8
      let height = bh * 8
      let need_transpose = dct_select.need_transpose()
      let mul = (65536.0 : Float) /
        (Float::from_int(quantizer.global_scale) * Float::from_int(hf_mul)) *
        qm_scale[channel]
      let matrix = if need_transpose {
        dequant_matrices.get_transposed(channel, dct_select)
      } else {
        dequant_matrices.get(channel, dct_select)
      }
      let c = coeff.subgrid(left, top, width, height)
      let q = coeff_q.subgrid(left, top, width, height)
      for y in 0..<height {
        let row = c.row_offset(y)
        let qrow = q.row_offset(y)
        let mrow = y * width
        for x in 0..<width {
          let mut v = Float::from_int(q.buf[qrow + x])
          if v.abs() <= 1.0 {
            v = v * quant_bias
          } else {
            v = v - quant_bias_numerator / v
          }
          v = v * matrix[mrow + x]
          v = v * mul
          c.buf[row + x] = v
        }
      }
    })
  }
}

///|
/// `f32::powi`.
fn powi_f32(base : Float, exp : Int32) -> Float {
  // Rust's powi is implemented with repeated multiplication (llvm.powi).
  let mut result : Float = 1.0
  let mut b = base
  let mut e = if exp < 0 { -exp } else { exp }
  while e > 0 {
    if e % 2 == 1 {
      result = result * b
    }
    b = b * b
    e = e / 2
  }
  if exp < 0 {
    (1.0 : Float) / result
  } else {
    result
  }
}

///|
fn chroma_from_luma_lf(
  coeff_xyb : FixedArray[@grid.Grid[Float]],
  lf_chan_corr : @vardct.LfChannelCorrelation,
) -> Unit {
  let x_factor = lf_chan_corr.x_factor_lf - 128
  let b_factor = lf_chan_corr.b_factor_lf - 128
  let colour_factor = Float::from_int(lf_chan_corr.colour_factor)
  let kx = lf_chan_corr.base_correlation_x +
    Float::from_int(x_factor) / colour_factor
  let kb = lf_chan_corr.base_correlation_b +
    Float::from_int(b_factor) / colour_factor
  let x = coeff_xyb[0].buf()
  let y = coeff_xyb[1].buf()
  let b = coeff_xyb[2].buf()
  let n = min_int(
    coeff_xyb[0].width() * coeff_xyb[0].height(),
    min_int(
      coeff_xyb[1].width() * coeff_xyb[1].height(),
      coeff_xyb[2].width() * coeff_xyb[2].height(),
    ),
  )
  for i in 0..<n {
    let yv = y[i]
    x[i] = x[i] + kx * yv
    b[i] = b[i] + kb * yv
  }
}

///|
fn chroma_from_luma_hf_grouped(
  coeff_xyb : FixedArray[@grid.SubGrid[Float]],
  x_from_y : @grid.SubGrid[Int32],
  b_from_y : @grid.SubGrid[Int32],
  lf_chan_corr : @vardct.LfChannelCorrelation,
) -> Unit {
  let coeff_x = coeff_xyb[0]
  let coeff_y = coeff_xyb[1]
  let coeff_b = coeff_xyb[2]
  let gw = coeff_x.width
  let gh = coeff_x.height
  let colour_factor = Float::from_int(lf_chan_corr.colour_factor)
  for y in 0..<gh {
    let xfy_row = x_from_y.row_offset(y / 64)
    let bfy_row = b_from_y.row_offset(y / 64)
    let rx = coeff_x.row_offset(y)
    let ry = coeff_y.row_offset(y)
    let rb = coeff_b.row_offset(y)
    let n = min_int(x_from_y.width, b_from_y.width)
    for x64 in 0..<n {
      let kx = lf_chan_corr.base_correlation_x +
        Float::from_int(x_from_y.buf[xfy_row + x64]) / colour_factor
      let kb = lf_chan_corr.base_correlation_b +
        Float::from_int(b_from_y.buf[bfy_row + x64]) / colour_factor
      let lim = min_int(gw - x64 * 64, 64)
      for dx in 0..<lim {
        let x = x64 * 64 + dx
        let cy = coeff_y.buf[ry + x]
        coeff_x.buf[rx + x] = coeff_x.buf[rx + x] + kx * cy
        coeff_b.buf[rb + x] = coeff_b.buf[rb + x] + kb * cy
      }
    }
  }
}

///|
fn transform_with_lf_grouped(
  lf : ImageWithRegion,
  coeff_out : FixedArray[@grid.SubGrid[Float]],
  group_idx : Int32,
  frame_header : @frame.FrameHeader,
  lf_groups : Map[Int32, @frame.LfGroup],
) -> Unit {
  let lf_regions = lf.regions_and_shifts()
  let lf_grids = lf.as_color_floats()
  let shifts_cbycr = FixedArray::makei(3, idx => {
    @modular.ChannelShift::from_jpeg_upsampling(
      frame_header.jpeg_upsampling,
      idx,
    )
  })
  let group_dim = frame_header.group_dim()
  let groups_per_row = frame_header.groups_per_row()
  let (group_width, group_height) = frame_header.group_size_for(group_idx)
  let group_x = group_idx % groups_per_row
  let group_y = group_idx / groups_per_row
  let lf_base_left = group_x * group_dim / 8
  let lf_base_top = group_y * group_dim / 8
  let lf_views = FixedArray::makei(3, c => {
    let (lf_region, shift) = lf_regions[c]
    let lf_base_left = lf_base_left - lf_region.left
    let lf_base_top = lf_base_top - lf_region.top
    guard lf_base_left >= 0 && lf_base_top >= 0 else {
      abort("transform_with_lf_grouped: LF region does not cover group")
    }
    let lf_width = min_int(
      lf_region.width - lf_base_left,
      (group_width + 7) / 8,
    )
    let lf_height = min_int(
      lf_region.height - lf_base_top,
      (group_height + 7) / 8,
    )
    let lf_base_left = lf_base_left >> shift.hshift()
    let lf_base_top = lf_base_top >> shift.vshift()
    let (lf_width, lf_height) = shift.shift_size((lf_width, lf_height))
    lf_grids[c]
    .as_subgrid()
    .subgrid(lf_base_left, lf_base_top, lf_width, lf_height)
  })
  let lf_group_idx = frame_header.lf_group_idx_from_group_idx(group_idx)
  guard lf_groups.get(lf_group_idx) is Some(lf_group) else { return }
  let left_in_lf = group_x % 8 * (group_dim / 8)
  let top_in_lf = group_y % 8 * (group_dim / 8)
  guard lf_group.hf_meta is Some(hf_meta) else {
    for c in 0..<3 {
      let coeff = coeff_out[c]
      let lfv = lf_views[c]
      for y in 0..<coeff.height {
        let row = coeff.row_offset(y)
        let lf_row = lfv.row_offset(y / 8)
        for x in 0..<coeff.width {
          coeff.buf[row + x] = lfv.buf[lf_row + x / 8]
        }
      }
    }
    return
  }
  let block_info = {
    let lf_region = lf_regions[0].0
    let lf_base_left = lf_base_left - lf_region.left
    let lf_base_top = lf_base_top - lf_region.top
    guard lf_base_left >= 0 && lf_base_top >= 0 else {
      abort("transform_with_lf_grouped: LF region does not cover group")
    }
    let lf_width = min_int(
      lf_region.width - lf_base_left,
      (group_width + 7) / 8,
    )
    let lf_height = min_int(
      lf_region.height - lf_base_top,
      (group_height + 7) / 8,
    )
    hf_meta.block_info
    .as_subgrid()
    .subgrid(left_in_lf, top_in_lf, lf_width, lf_height)
  }
  @vardct.transform_varblocks(
    lf_views,
    coeff_out,
    FixedArray::makei(3, c => shifts_cbycr[c].hshift()),
    FixedArray::makei(3, c => shifts_cbycr[c].vshift()),
    block_info,
  )
}

///|
/// Calls `f((shifted_bx, shifted_by, dct_select, hf_mul))` for each varblock
/// of the channel with `shift`.
fn for_each_varblocks(
  block_info : @grid.SubGrid[@vardct.BlockInfo],
  shift : @modular.ChannelShift,
  f : ((Int32, Int32, @vardct.TransformType, Int32)) -> Unit,
) -> Unit {
  let w8 = block_info.width
  let h8 = block_info.height
  let vshift = shift.vshift()
  let hshift = shift.hshift()
  for by in 0..<h8 {
    for bx in 0..<w8 {
      guard block_info.get(bx, by) is Data(dct_select~, hf_mul~) else {
        continue
      }
      let shifted_bx = bx >> hshift
      let shifted_by = by >> vshift
      if hshift != 0 || vshift != 0 {
        if shifted_bx << hshift != bx || shifted_by << vshift != by {
          continue
        }
        if !(block_info.get(shifted_bx, shifted_by) is Data(..)) {
          continue
        }
      }
      f((shifted_bx, shifted_by, dct_select, hf_mul))
    }
  }
}
