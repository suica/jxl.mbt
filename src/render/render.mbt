///|
/// Renders a frame: decode (Modular or VarDCT) → restoration filters →
/// features (patches, splines, noise) → upsampling.
fn render_frame(
  frame : IndexedFrame,
  reference_frames : ReferenceFrames,
  cache : RenderCache,
  image_region : Region,
  pool : @threadpool.JxlThreadPool,
  frame_visibility : (Int32, Int32),
) -> ImageWithRegion raise @bitstream.JxlError {
  let frame_region = image_region_to_frame(frame, image_region, false)
  let image_header = frame.image_header()
  let frame_header = frame.header()
  let frame_region = pad_lf_region(frame_header, frame_region)
  let upsampled_full_frame_region = Region::with_size(
    frame_header.sample_width(1),
    frame_header.sample_height(1),
  )
  let upsampling_valid_region = pad_upsampling(
    image_header, frame_header, frame_region,
  ).intersection(upsampled_full_frame_region)
  let full_frame_region = Region::with_size(
    frame_header.color_sample_width(),
    frame_header.color_sample_height(),
  )
  let color_padded_region = pad_color_region(
    image_header, frame_header, frame_region,
  ).intersection(full_frame_region)
  let fb = match frame_header.encoding {
    Modular => render_modular(frame, cache, color_padded_region, pool)
    VarDct =>
      render_vardct(
        frame,
        reference_frames.lf,
        cache,
        color_padded_region,
        pool,
      ) catch {
        e =>
          match reference_frames.lf {
            Some(lf) if is_incomplete_frame(e) || e.unexpected_eof() => {
              let render = lf.image.run_with_image()
              let render = render.blend(None)
              let render = render.upsample_lf(1)
              render.fill_opaque_alpha(image_header.metadata.ec_info)
              render
            }
            _ => raise e
          }
      }
  }
  if frame_header.do_ycbcr {
    fb.upsample_jpeg(color_padded_region, image_header.metadata.bit_depth)
  }
  let color_channels = fb.color_channels()
  let mut scratch_buffer : FixedArray[@grid.Grid[Float]]? = None
  if frame_header.restoration_filter.gab is Enabled(weights) {
    if fb.color_channels() < 3 {
      fb.clone_gray()
    }
    fb.convert_modular_color(image_header.metadata.bit_depth)
    let tracker = fb.alloc_tracker()
    let width = color_padded_region.width
    let height = color_padded_region.height
    let fb_scratch : FixedArray[@grid.Grid[Float]] = [
      @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
      @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
      @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
    ]
    apply_gabor_like(fb, color_padded_region, fb_scratch, weights)
    scratch_buffer = Some(fb_scratch)
  }
  if frame_header.restoration_filter.epf is Enabled(epf_params) {
    if fb.color_channels() < 3 {
      fb.clone_gray()
    }
    fb.convert_modular_color(image_header.metadata.bit_depth)
    let fb_scratch = match scratch_buffer {
      Some(buffer) => buffer
      None => {
        let tracker = fb.alloc_tracker()
        let width = color_padded_region.width
        let height = color_padded_region.height
        let s : FixedArray[@grid.Grid[Float]] = [
          @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
          @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
          @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
        ]
        s
      }
    }
    apply_epf(
      fb,
      fb_scratch,
      color_padded_region,
      cache.lf_groups,
      frame_header,
      epf_params,
    )
  }
  // Truncate cloned gray channels.
  fb.remove_color_channels(color_channels)
  fb.prepare_color_upsampling(frame_header)
  render_features(
    frame,
    fb,
    upsampling_valid_region,
    reference_frames.refs,
    cache,
    frame_visibility.0,
    frame_visibility.1,
  )
  fb.upsample_nonseparable(
    image_header, frame_header, upsampling_valid_region, false,
  )
  if !frame_header.save_before_ct && !frame_header.is_last {
    convert_color_for_record(image_header, frame_header.do_ycbcr, fb)
  }
  fb
}

///|
fn render_features(
  frame : IndexedFrame,
  grid : ImageWithRegion,
  upsampling_valid_region : Region,
  reference_grids : FixedArray[Reference?],
  cache : RenderCache,
  visible_frames_num : Int32,
  invisible_frames_num : Int32,
) -> Unit raise @bitstream.JxlError {
  let image_header = frame.image_header()
  let frame_header = frame.header()
  guard cache.lf_global is Some(lf_global) else {
    // LfGlobal not available, skipping feature rendering
    return
  }
  let base_correlations_xb = match lf_global.vardct {
    Some(x) =>
      Some(
        (x.lf_chan_corr.base_correlation_x, x.lf_chan_corr.base_correlation_b),
      )
    None => None
  }
  if lf_global.patches is Some(patches) {
    grid.upsample_nonseparable(
      image_header, frame_header, upsampling_valid_region, true,
    )
    for patch_ref in patches.patches {
      guard reference_grids[patch_ref.ref_idx] is Some(ref_grid) else {
        raise invalid_reference(patch_ref.ref_idx)
      }
      let ref_header = ref_grid.frame.header()
      let oriented_image_region = Region::with_size(
        ref_header.width,
        ref_header.height,
      ).translate(ref_header.x0, ref_header.y0)
      let ref_grid_image = ref_grid.image.run_with_image()
      let ref_grid_image = ref_grid_image.blend(Some(oriented_image_region))
      patch(image_header, grid, ref_grid_image, patch_ref)
    }
  }
  if lf_global.splines is Some(splines) {
    if grid.color_channels() == 3 {
      grid.convert_modular_color(image_header.metadata.bit_depth)
      render_spline(frame_header, grid, splines, base_correlations_xb)
    } else {
      // Cannot render splines on grayscale buffer; skipping
      ()
    }
  }
  if lf_global.noise is Some(noise) {
    if grid.color_channels() == 3 {
      grid.convert_modular_color(image_header.metadata.bit_depth)
      render_noise(
        frame.header(),
        visible_frames_num,
        invisible_frames_num,
        base_correlations_xb,
        grid,
        noise,
      )
    } else {
      // Cannot render noise on grayscale buffer; skipping
      ()
    }
  }
}
