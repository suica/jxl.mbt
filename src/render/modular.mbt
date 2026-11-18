///|
/// `frame.try_parse_lf_global::<S>()`; `narrow` selects `S = i16`.
///
/// The frame package decodes Modular samples as `Int` for both; the narrow
/// selection is kept here so that the call sites match upstream.
fn parse_lf_global(
  frame : IndexedFrame,
  narrow : Bool,
) -> Result[@frame.LfGlobal, @bitstream.JxlError]? {
  ignore(narrow)
  frame.try_parse_lf_global()
}

///|
priv struct PassGroupJob {
  pass_idx : Int32
  group_idx : Int32
  modular : @modular.TransformedModularSubimage
}

///|
/// Renders a Modular frame into an image with integer (or, for XYB images,
/// dequantized float) channels.
fn render_modular(
  frame : IndexedFrame,
  cache : RenderCache,
  region : Region,
  pool : @threadpool.JxlThreadPool,
) -> ImageWithRegion raise @bitstream.JxlError {
  let image_header = frame.image_header()
  let frame_header = frame.header()
  let tracker = frame.alloc_tracker()
  let xyb_encoded = image_header.metadata.xyb_encoded
  let lf_global = match cache.lf_global {
    Some(x) => x
    None => {
      guard unwrap_opt_result(parse_lf_global(frame, cache.narrow))
        is Some(lf_global) else {
        raise incomplete_frame()
      }
      cache.lf_global = Some(lf_global)
      lf_global
    }
  }
  let gmodular = lf_global.gmodular.try_clone()
  let modular_region = compute_modular_region(
    frame_header, gmodular, region, false,
  )
  let modular_image = gmodular.modular.image_mut().unwrap()
  let groups = modular_image.prepare_groups(frame.pass_shifts())
  let lf_group_image = groups.lf_groups
  let pass_group_image = groups.pass_groups
  // Decode
  let result : Ref[@bitstream.JxlError?] = Ref(None)
  pool.scope(scope => {
    let lf_groups = cache.lf_groups
    scope.spawn(_ => {
      ignore(
        load_lf_groups(
          frame,
          lf_global,
          lf_groups,
          lf_group_image,
          modular_region.downsample(3),
          pool,
        ),
      ) catch {
        e => result.val = Some(e)
      }
    })
    let group_dim = frame_header.group_dim()
    let groups_per_row = frame_header.groups_per_row()
    let jobs : Array[PassGroupJob] = []
    for pass_idx, pass_image in pass_group_image {
      for group_idx, modular in pass_image {
        let group_x = group_idx % groups_per_row
        let group_y = group_idx / groups_per_row
        let group_region : Region = {
          left: group_x * group_dim,
          top: group_y * group_dim,
          width: group_dim,
          height: group_dim,
        }
        if group_region.intersection(modular_region).is_empty() {
          continue
        }
        jobs.push({ pass_idx, group_idx, modular, })
      }
    }
    pool.for_each_vec(jobs, job => {
      let { pass_idx, group_idx, modular, } = job
      let bitstream = match frame.pass_group_bitstream(pass_idx, group_idx) {
        Some(Ok(bitstream)) => bitstream
        Some(Err(e)) => {
          result.val = Some(e)
          return
        }
        None => return
      }
      let allow_partial = bitstream.partial
      let global_ma_config = gmodular.ma_config
      @frame.decode_pass_group_modular(
        bitstream.bitstream,
        frame_header,
        global_ma_config,
        pass_idx,
        group_idx,
        modular,
        allow_partial,
        tracker,
      ) catch {
        e => if !allow_partial { result.val = Some(e) }
      }
    })
  })
  if result.val is Some(e) {
    raise e
  }
  // Inverse Modular transform
  let subimage = modular_image.prepare_subimage() catch {
    e => abort("prepare_subimage: \{@debug.to_string(e)}")
  }
  ignore(subimage.finish())
  let fb = ImageWithRegion::new(frame_header.encoded_color_channels(), tracker)
  fb.extend_from_gmodular(gmodular, narrow=cache.narrow)
  if xyb_encoded {
    // Dequant XYB
    fb.convert_modular_xyb(lf_global.lf_dequant)
  }
  fb
}

///|
fn compute_modular_region(
  frame_header : @frame.FrameHeader,
  gmodular : @frame.GlobalModular,
  region : Region,
  is_lf : Bool,
) -> Region {
  if gmodular.modular.has_palette() || gmodular.modular.has_squeeze() {
    let mut width = frame_header.color_sample_width()
    let mut height = frame_header.color_sample_height()
    if is_lf {
      width = (width + 7) / 8
      height = (height + 7) / 8
    }
    let width = max_int(width, region.width + region.left)
    let height = max_int(height, region.height + region.top)
    Region::with_size(width, height)
  } else {
    region
  }
}
