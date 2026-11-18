///|
priv enum BlendMode {
  Replace
  Add
  Mul(Bool)
  Blend(BlendAlpha)
  MulAdd(BlendAlpha)
  MixAlpha(clamp~ : Bool, swapped~ : Bool)
  Skip
}

///|
priv struct BlendAlpha {
  base : @grid.SubGrid[Float]?
  new : @grid.SubGrid[Float]?
  clamp : Bool
  swapped : Bool
  premultiplied : Bool
}

///|
priv struct BlendParams {
  mode : BlendMode
  mut base_topleft : (Int, Int)
  mut new_topleft : (Int, Int)
  mut width : Int
  mut height : Int
}

///|
fn BlendParams::from_blending_info(
  channel_idx : Int,
  color_channels : Int,
  blending_info : @frame.BlendingInfo,
  base_alpha : @grid.SubGrid[Float]?,
  new_alpha : @grid.SubGrid[Float]?,
  premultiplied : Bool?,
) -> BlendParams {
  let is_alpha = channel_idx == blending_info.alpha_channel + color_channels
  let mode : BlendMode = match blending_info.mode {
    Replace => Replace
    Add => Add
    Blend =>
      if is_alpha {
        MixAlpha(clamp=blending_info.clamp, swapped=false)
      } else {
        Blend({
          base: base_alpha,
          new: new_alpha,
          clamp: blending_info.clamp,
          swapped: false,
          premultiplied: premultiplied.unwrap_or(false),
        })
      }
    MulAdd =>
      if is_alpha {
        Skip
      } else {
        MulAdd({
          base: base_alpha,
          new: new_alpha,
          clamp: blending_info.clamp,
          swapped: false,
          premultiplied: premultiplied.unwrap_or(false),
        })
      }
    Mul => Mul(blending_info.clamp)
  }
  { mode, base_topleft: (0, 0), new_topleft: (0, 0), width: 0, height: 0 }
}

///|
fn BlendParams::from_patch_blending_info(
  channel_idx : Int,
  color_channels : Int,
  blending_info : @frame.BlendingModeInformation,
  base_alpha : @grid.SubGrid[Float]?,
  new_alpha : @grid.SubGrid[Float]?,
  premultiplied : Bool?,
) -> BlendParams? {
  let is_alpha = channel_idx == blending_info.alpha_channel + color_channels
  let mode : BlendMode = match blending_info.mode {
    @frame.PatchBlendMode::None => return None
    @frame.PatchBlendMode::Replace => Replace
    @frame.PatchBlendMode::Add => Add
    @frame.PatchBlendMode::Mul => Mul(blending_info.clamp)
    @frame.PatchBlendMode::BlendAbove | @frame.PatchBlendMode::BlendBelow => {
      let swapped = blending_info.mode is @frame.PatchBlendMode::BlendBelow
      if is_alpha {
        MixAlpha(clamp=blending_info.clamp, swapped~)
      } else {
        Blend({
          base: base_alpha,
          new: new_alpha,
          clamp: blending_info.clamp,
          swapped,
          premultiplied: premultiplied.unwrap_or(false),
        })
      }
    }
    @frame.PatchBlendMode::MulAddAbove | @frame.PatchBlendMode::MulAddBelow => {
      let swapped = blending_info.mode is @frame.PatchBlendMode::MulAddBelow
      if is_alpha {
        if swapped {
          Replace
        } else {
          Skip
        }
      } else {
        MulAdd({
          base: base_alpha,
          new: new_alpha,
          clamp: blending_info.clamp,
          swapped,
          premultiplied: premultiplied.unwrap_or(false),
        })
      }
    }
  }
  Some({ mode, base_topleft: (0, 0), new_topleft: (0, 0), width: 0, height: 0 })
}

///|
fn source_and_alpha_from_blending_info(
  blending_info : @frame.BlendingInfo,
  has_extra : Bool,
) -> (Int, Int?) {
  let source = blending_info.source
  let alpha = if (blending_info.mode is Blend || blending_info.mode is MulAdd) &&
    has_extra {
    Some(blending_info.alpha_channel)
  } else {
    None
  }
  (source, alpha)
}

///|
/// Blends `new_grid` of `new_frame` onto its reference frames, producing the
/// composited image covering `output_frame_region` (in frame coordinates).
fn blend(
  image_header : @image.ImageHeader,
  reference_grids : FixedArray[Reference?],
  new_frame : IndexedFrame,
  new_grid : ImageWithRegion,
  output_frame_region : Region,
) -> ImageWithRegion raise @bitstream.JxlError {
  let header = new_frame.header()
  let tracker = new_frame.alloc_tracker()
  let full_frame_region = Region::with_size(header.width, header.height)
  let output_image_region = output_frame_region.translate(header.x0, header.y0)
  let used_refs = FixedArray::make(4, false)
  used_refs[header.blending_info.source] = true
  for bi in header.ec_blending_info {
    used_refs[bi.source] = true
  }
  let ref_list : Array[Reference] = []
  for ref_idx in 0..<4 {
    if !used_refs[ref_idx] {
      continue
    }
    if reference_grids[ref_idx] is Some(grid) {
      ref_list.push(grid)
    }
  }
  ref_list.sort_by_key(grid => grid.frame.idx)
  for grid in ref_list {
    ignore(grid.image.run_with_image().blend(Some(output_image_region)))
  }
  let color_channels = new_grid.color_channels()
  let output_grid = ImageWithRegion::new(color_channels, tracker)
  output_grid.set_ct_done(new_grid.ct_done())
  let has_extra = !header.ec_blending_info.is_empty()
  let num_channels = color_channels + header.ec_blending_info.length()
  for idx in 0..<num_channels {
    let blending_info = if idx < color_channels {
      header.blending_info
    } else {
      header.ec_blending_info[idx - color_channels]
    }
    let bit_depth = if idx >= color_channels {
      image_header.metadata.ec_info[idx - color_channels].bit_depth
    } else {
      image_header.metadata.bit_depth
    }
    let (ref_idx, alpha_idx) = source_and_alpha_from_blending_info(
      blending_info, has_extra,
    )
    let ref_grid = reference_grids[ref_idx]
    let original_frame_region = new_grid.regions_and_shifts()[idx].0.intersection(
      full_frame_region,
    )
    let clipped_original_frame_region = original_frame_region.intersection(
      output_frame_region,
    )
    let (target_grid, target_region, target_subgrid, base_alpha, clone_empty) : (
      ImageBuffer,
      Region,
      @grid.SubGrid[Float],
      @grid.SubGrid[Float]?,
      Bool,
    ) = match ref_grid {
      Some(grid) => {
        // Upstream allows taking the reference buffer instead of cloning it
        // (`can_overwrite`), but `try_take_blended` can never succeed there
        // since another strong reference is alive; the clone path is taken.
        let base_grid_render = grid.image.run_with_image()
        let base_grid = base_grid_render.blend(Some(output_image_region))
        guard base_grid.color_channels() == color_channels else {
          abort("blend: color channel count mismatch")
        }
        if base_grid.regions_and_shifts()[idx].0.is_empty() {
          let g = @grid.Grid::with_alloc_tracker(
            output_frame_region.width,
            output_frame_region.height,
            (0.0 : Float),
            tracker,
          )
          (F32(g), output_frame_region, g.as_subgrid(), None, true)
        } else {
          let base_frame_header = grid.frame.header()
          let base_frame_region = output_image_region.translate(
            -base_frame_header.x0,
            -base_frame_header.y0,
          )
          let cloned = base_grid.buffer()[idx].try_clone()
          let target_region = base_grid.regions_and_shifts()[idx].0.translate(
            base_frame_header.x0 - header.x0,
            base_frame_header.y0 - header.y0,
          )
          let tg = cloned.convert_to_float_modular(bit_depth)
          let grid_region = base_grid.regions_and_shifts()[idx].0
          let region = base_frame_region.translate(
            -grid_region.left,
            -grid_region.top,
          )
          let target_subgrid = tg
            .as_subgrid()
            .subgrid(region.left, region.top, region.width, region.height)
          let mut base_alpha = None
          if alpha_idx is Some(alpha_idx) && alpha_idx + color_channels != idx {
            let alpha_bit_depth = image_header.metadata.ec_info[alpha_idx].bit_depth
            let base_alpha_grid = base_grid.buffer()[alpha_idx + color_channels]
              .try_clone()
              .convert_to_float_modular(alpha_bit_depth)
            let grid_region = base_grid.regions_and_shifts()[alpha_idx +
              color_channels].0
            let region = base_frame_region.translate(
              -grid_region.left,
              -grid_region.top,
            )
            base_alpha = Some(
              base_alpha_grid
              .as_subgrid()
              .subgrid(region.left, region.top, region.width, region.height),
            )
          }
          (F32(tg), target_region, target_subgrid, base_alpha, false)
        }
      }
      None => {
        let g = @grid.Grid::with_alloc_tracker(
          output_frame_region.width,
          output_frame_region.height,
          (0.0 : Float),
          tracker,
        )
        (F32(g), output_frame_region, g.as_subgrid(), None, true)
      }
    }
    if alpha_idx is Some(aidx) {
      let bit_depth = image_header.metadata.ec_info[aidx].bit_depth
      ignore(
        new_grid.convert_channel_to_float_modular(aidx + color_channels, bit_depth),
      )
    }
    ignore(new_grid.convert_channel_to_float_modular(idx, bit_depth))
    let new_alpha = match alpha_idx {
      Some(aidx) =>
        Some(new_grid.buffer()[aidx + color_channels].float().as_subgrid())
      None => None
    }
    let premultiplied = match alpha_idx {
      Some(aidx) => image_header.metadata.ec_info[aidx].alpha_associated()
      None => None
    }
    let blend_params = BlendParams::from_blending_info(
      idx,
      color_channels,
      blending_info,
      if clone_empty {
        None
      } else {
        base_alpha
      },
      new_alpha,
      premultiplied,
    )
    blend_params.base_topleft = (
      abs_diff(clipped_original_frame_region.left, output_frame_region.left),
      abs_diff(clipped_original_frame_region.top, output_frame_region.top),
    )
    blend_params.new_topleft = (
      abs_diff(clipped_original_frame_region.left, original_frame_region.left),
      abs_diff(clipped_original_frame_region.top, original_frame_region.top),
    )
    blend_params.width = clipped_original_frame_region.width
    blend_params.height = clipped_original_frame_region.height
    let new_g = new_grid.buffer()[idx].float()
    blend_single(target_subgrid, new_g.as_subgrid(), blend_params)
    output_grid.append_channel(target_grid, target_region)
  }
  if header.can_reference() {
    let ref_idx = header.save_as_reference
    if reference_grids[ref_idx] is Some(grid) &&
      !grid.frame.header().is_keyframe() {
      ignore(grid.image.reset())
    }
  }
  output_grid.set_blend_done(true)
  output_grid
}

///|
/// Renders a patch onto `base_grid`.
pub fn patch(
  image_header : @image.ImageHeader,
  base_grid : ImageWithRegion,
  patch_ref_grid : ImageWithRegion,
  patch_ref : @frame.PatchRef,
) -> Unit raise @bitstream.JxlError {
  let color_channels = base_grid.color_channels()
  guard patch_ref_grid.color_channels() == color_channels else {
    abort("patch: color channel count mismatch")
  }
  for target in patch_ref.patch_targets {
    let num_channels = color_channels + target.blending.length() - 1
    for idx in 0..<num_channels {
      let blending_info = if idx < color_channels {
        target.blending[0]
      } else {
        target.blending[idx - color_channels + 1]
      }
      let base_grid_region = base_grid.regions_and_shifts()[idx].0
      let ref_grid_region = patch_ref_grid.regions_and_shifts()[idx].0
      let target_patch_region = base_grid_region.intersection({
        left: target.x,
        top: target.y,
        width: patch_ref.width,
        height: patch_ref.height,
      })
      let width = target_patch_region.width
      let height = target_patch_region.height
      let left = target_patch_region.left - target.x
      let top = target_patch_region.top - target.y
      let ref_patch_region = ref_grid_region.intersection({
        left: patch_ref.x0 + left,
        top: patch_ref.y0 + top,
        width,
        height,
      })
      let width = ref_patch_region.width
      let height = ref_patch_region.height
      let patch_left = abs_diff(ref_patch_region.left, ref_grid_region.left)
      let patch_top = abs_diff(ref_patch_region.top, ref_grid_region.top)
      let base_left = abs_diff(target_patch_region.left, base_grid_region.left)
      let base_top = abs_diff(target_patch_region.top, base_grid_region.top)
      let bit_depth = if idx >= color_channels {
        image_header.metadata.ec_info[idx - color_channels].bit_depth
      } else {
        image_header.metadata.bit_depth
      }
      let alpha_idx = match blending_info.mode {
        @frame.PatchBlendMode::BlendAbove
        | @frame.PatchBlendMode::BlendBelow
        | @frame.PatchBlendMode::MulAddAbove
        | @frame.PatchBlendMode::MulAddBelow => Some(blending_info.alpha_channel)
        _ => None
      }
      let mut base_alpha = None
      let mut new_alpha = None
      let mut premultiplied = None
      if alpha_idx is Some(alpha_idx) && alpha_idx + color_channels != idx {
        let alpha_bit_depth = image_header.metadata.ec_info[alpha_idx].bit_depth
        let alpha = base_grid.convert_channel_to_float_modular(
          alpha_idx + color_channels,
          alpha_bit_depth,
        )
        base_alpha = Some(alpha.as_subgrid())
        new_alpha = Some(
          patch_ref_grid.buffer()[alpha_idx + color_channels]
          .float()
          .as_subgrid(),
        )
        premultiplied = image_header.metadata.ec_info[alpha_idx].alpha_associated()
      }
      let base = base_grid
        .convert_channel_to_float_modular(idx, bit_depth)
        .as_subgrid()
      guard BlendParams::from_patch_blending_info(
          idx, color_channels, blending_info, base_alpha, new_alpha, premultiplied,
        )
        is Some(blend_params) else {
        continue
      }
      blend_params.base_topleft = (base_left, base_top)
      blend_params.new_topleft = (patch_left, patch_top)
      blend_params.width = width
      blend_params.height = height
      blend_single(
        base,
        patch_ref_grid.buffer()[idx].float().as_subgrid(),
        blend_params,
      )
    }
  }
}

///|
const ONE : Float = 1.0

///|
fn clamp01(v : Float) -> Float {
  if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
fn blend_single(
  base : @grid.SubGrid[Float],
  new_grid : @grid.SubGrid[Float],
  blend_params : BlendParams,
) -> Unit {
  let (base_x, base_y) = blend_params.base_topleft
  let (new_x, new_y) = blend_params.new_topleft
  let width = blend_params.width
  let height = blend_params.height
  let bbuf = base.buf
  let nbuf = new_grid.buf
  match blend_params.mode {
    Replace | Blend({ new: None, .. }) =>
      for dy in 0..<height {
        let brow = base.row_offset(base_y + dy) + base_x
        let nrow = new_grid.row_offset(new_y + dy) + new_x
        for dx in 0..<width {
          bbuf[brow + dx] = nbuf[nrow + dx]
        }
      }
    Add | MulAdd({ new: None, .. }) =>
      for dy in 0..<height {
        let brow = base.row_offset(base_y + dy) + base_x
        let nrow = new_grid.row_offset(new_y + dy) + new_x
        for dx in 0..<width {
          bbuf[brow + dx] = bbuf[brow + dx] + nbuf[nrow + dx]
        }
      }
    Mul(clamp) =>
      for dy in 0..<height {
        let brow = base.row_offset(base_y + dy) + base_x
        let nrow = new_grid.row_offset(new_y + dy) + new_x
        for dx in 0..<width {
          let mut new_sample = nbuf[nrow + dx]
          if clamp {
            new_sample = clamp01(new_sample)
          }
          bbuf[brow + dx] = bbuf[brow + dx] * new_sample
        }
      }
    Blend(
      {
        base: base_alpha,
        new: Some(new_alpha),
        clamp,
        swapped,
        premultiplied,
      }
    ) =>
      for dy in 0..<height {
        let base_buf_y = base_y + dy
        let brow = base.row_offset(base_buf_y) + base_x
        let nrow = new_grid.row_offset(new_y + dy) + new_x
        let narow = new_alpha.row_offset(new_y + dy) + new_x
        for dx in 0..<width {
          let base_alpha_sample : Float = match base_alpha {
            Some(a) => a.buf[a.row_offset(base_buf_y) + base_x + dx]
            None => 0.0
          }
          let (base_sample, new_sample, ba, na0) = if swapped {
            (
              nbuf[nrow + dx],
              bbuf[brow + dx],
              new_alpha.buf[narow + dx],
              base_alpha_sample,
            )
          } else {
            (
              bbuf[brow + dx],
              nbuf[nrow + dx],
              base_alpha_sample,
              new_alpha.buf[narow + dx],
            )
          }
          let mut na = na0
          if clamp {
            na = clamp01(na)
          }
          bbuf[brow + dx] = if premultiplied {
            new_sample + base_sample * (ONE - na)
          } else {
            let base_alpha_rev = ONE - ba
            let new_alpha_rev = ONE - na
            let mixed_alpha = ONE - new_alpha_rev * base_alpha_rev
            let mixed_alpha_recip : Float = if mixed_alpha > 0.0 {
              ONE / mixed_alpha
            } else {
              0.0
            }
            (na * new_sample + ba * base_sample * new_alpha_rev) *
            mixed_alpha_recip
          }
        }
      }
    MulAdd({ base: base_alpha, new: Some(new_alpha), clamp, swapped, .. }) =>
      for dy in 0..<height {
        let base_buf_y = base_y + dy
        let brow = base.row_offset(base_buf_y) + base_x
        let nrow = new_grid.row_offset(new_y + dy) + new_x
        let narow = new_alpha.row_offset(new_y + dy) + new_x
        for dx in 0..<width {
          let (base_sample, new_sample, na0) : (Float, Float, Float) = if swapped {
            (
              nbuf[nrow + dx],
              bbuf[brow + dx],
              match base_alpha {
                Some(a) => a.buf[a.row_offset(base_buf_y) + base_x + dx]
                None => 0.0
              },
            )
          } else {
            (bbuf[brow + dx], nbuf[nrow + dx], new_alpha.buf[narow + dx])
          }
          let mut na = na0
          if clamp {
            na = clamp01(na)
          }
          bbuf[brow + dx] = base_sample + na * new_sample
        }
      }
    MixAlpha(clamp~, swapped~) =>
      for dy in 0..<height {
        let brow = base.row_offset(base_y + dy) + base_x
        let nrow = new_grid.row_offset(new_y + dy) + new_x
        for dx in 0..<width {
          let mut b = bbuf[brow + dx]
          let mut n = nbuf[nrow + dx]
          if swapped {
            let t = b
            b = n
            n = t
          }
          if clamp {
            n = clamp01(n)
          }
          bbuf[brow + dx] = b + n * (ONE - b)
        }
      }
    Skip => ()
  }
}
