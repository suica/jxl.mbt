///|
/// Index value meaning "no frame" (`usize::MAX` upstream).
const NO_FRAME : Int32 = -1

///|
/// Frame with its index in the image (jxl-render `IndexedFrame`).
///
/// Upstream derefs to `Frame`; MoonBit has no `Deref`, so every public
/// `Frame` method is forwarded with the same signature, and `frame()` gives
/// the `Frame` itself.
pub struct IndexedFrame {
  priv f : @frame.Frame
  priv idx : Int32
}

///|
fn IndexedFrame::new(frame : @frame.Frame, index : Int32) -> IndexedFrame {
  { f: frame, idx: index, }
}

///|
/// Returns the frame index.
pub fn IndexedFrame::index(self : IndexedFrame) -> Int32 {
  self.idx
}

///|
/// Returns the underlying frame (upstream `Deref`).
pub fn IndexedFrame::frame(self : IndexedFrame) -> @frame.Frame {
  self.f
}

///|
pub fn IndexedFrame::header(self : IndexedFrame) -> @frame.FrameHeader {
  self.f.header()
}

///|
pub fn IndexedFrame::image_header(self : IndexedFrame) -> @image.ImageHeader {
  self.f.image_header()
}

///|
pub fn IndexedFrame::alloc_tracker(self : IndexedFrame) -> @grid.AllocTracker? {
  self.f.alloc_tracker()
}

///|
pub fn IndexedFrame::is_loading_done(self : IndexedFrame) -> Bool {
  self.f.is_loading_done()
}

///|
pub fn IndexedFrame::feed_bytes(
  self : IndexedFrame,
  buf : BytesView,
) -> BytesView raise @bitstream.JxlError {
  self.f.feed_bytes(buf)
}

///|
pub fn IndexedFrame::pass_shifts(
  self : IndexedFrame,
) -> @sorted_map.SortedMap[Int32, (Int32, Int32)] {
  self.f.pass_shifts()
}

///|
pub fn IndexedFrame::toc(self : IndexedFrame) -> @frame.Toc {
  self.f.toc()
}

///|
pub fn IndexedFrame::data(
  self : IndexedFrame,
  group : @frame.TocGroupKind,
) -> BytesView? {
  self.f.data(group)
}

///|
pub fn IndexedFrame::current_loading_group(
  self : IndexedFrame,
) -> @frame.TocGroup? {
  self.f.current_loading_group()
}

///|
pub fn IndexedFrame::adjust_region(
  self : IndexedFrame,
  region : (Int32, Int32, Int32, Int32),
) -> (Int32, Int32, Int32, Int32) {
  self.f.adjust_region(region)
}

///|
pub fn IndexedFrame::try_parse_lf_global(
  self : IndexedFrame,
) -> Result[@frame.LfGlobal, @bitstream.JxlError]? {
  self.f.try_parse_lf_global()
}

///|
pub fn IndexedFrame::try_parse_lf_group(
  self : IndexedFrame,
  lf_global_vardct : @frame.LfGlobalVarDct?,
  global_ma_config : @modular.MaConfig?,
  mlf_group : @modular.TransformedModularSubimage?,
  lf_group_idx : Int32,
) -> Result[@frame.LfGroup, @bitstream.JxlError]? {
  self.f.try_parse_lf_group(
    lf_global_vardct, global_ma_config, mlf_group, lf_group_idx,
  )
}

///|
pub fn IndexedFrame::try_parse_hf_global(
  self : IndexedFrame,
  cached_lf_global : @frame.LfGlobal?,
) -> Result[@frame.HfGlobal, @bitstream.JxlError]? {
  self.f.try_parse_hf_global(cached_lf_global)
}

///|
pub fn IndexedFrame::pass_group_bitstream(
  self : IndexedFrame,
  pass_idx : Int32,
  group_idx : Int32,
) -> Result[@frame.PassGroupBitstream, @bitstream.JxlError]? {
  self.f.pass_group_bitstream(pass_idx, group_idx)
}

///|
/// `Option<Result<T>>` → `T? raise` (`?` on the inner result).
fn[T] unwrap_opt_result(
  r : Result[T, @bitstream.JxlError]?,
) -> T? raise @bitstream.JxlError {
  match r {
    None => None
    Some(Ok(v)) => Some(v)
    Some(Err(e)) => raise e
  }
}

///|
struct FrameDependence {
  lf : Int32
  ref_slots : FixedArray[Int32]
}

///|
/// LF frame and reference frames a frame depends on.
priv struct ReferenceFrames {
  lf : Reference?
  refs : FixedArray[Reference?]
}

///|
priv struct Reference {
  frame : IndexedFrame
  image : FrameRenderHandle
}

///|
/// Render context that tracks loaded and rendered frames.
#warnings("-unused_field")
pub struct RenderContext {
  priv image_header : @image.ImageHeader
  priv pool : @threadpool.JxlThreadPool
  priv tracker : @grid.AllocTracker?
  priv frames : Array[IndexedFrame]
  priv renders_wide : Array[FrameRenderHandle]
  priv renders_narrow : Array[FrameRenderHandle]
  priv keyframes : Array[Int32]
  priv mut keyframe_in_progress : Int32?
  priv refcounts : Array[Int32]
  priv frame_deps : Array[FrameDependence]
  priv lf_frame : FixedArray[Int32]
  priv reference : FixedArray[Int32]
  priv mut loading_frame : IndexedFrame?
  priv mut loading_render_cache_wide : RenderCache?
  priv mut loading_render_cache_narrow : RenderCache?
  priv mut loading_region : Region?
  priv mut requested_image_region : Region
  priv embedded_icc : Bytes
  priv mut requested_color_encoding : @color.ColorEncodingWithProfile
  priv mut cms : &@color.ColorManagementSystem
  priv mut cached_transform : @color.ColorTransform?
  priv force_wide_buffers : Bool
}

///|
pub fn RenderContext::builder() -> RenderContextBuilder {
  RenderContextBuilder::default()
}

///|
pub struct RenderContextBuilder {
  priv mut embedded_icc : Bytes
  priv mut pool : @threadpool.JxlThreadPool?
  priv mut tracker : @grid.AllocTracker?
  priv mut force_wide_buffers : Bool
}

///|
pub fn RenderContextBuilder::default() -> RenderContextBuilder {
  { embedded_icc: b"", pool: None, tracker: None, force_wide_buffers: false, }
}

///|
pub fn RenderContextBuilder::embedded_icc(
  self : RenderContextBuilder,
  icc : Bytes,
) -> RenderContextBuilder {
  self.embedded_icc = icc
  self
}

///|
pub fn RenderContextBuilder::pool(
  self : RenderContextBuilder,
  pool : @threadpool.JxlThreadPool,
) -> RenderContextBuilder {
  self.pool = Some(pool)
  self
}

///|
pub fn RenderContextBuilder::alloc_tracker(
  self : RenderContextBuilder,
  tracker : @grid.AllocTracker,
) -> RenderContextBuilder {
  self.tracker = Some(tracker)
  self
}

///|
pub fn RenderContextBuilder::force_wide_buffers(
  self : RenderContextBuilder,
  force_wide_buffers : Bool,
) -> RenderContextBuilder {
  self.force_wide_buffers = force_wide_buffers
  self
}

///|
pub fn RenderContextBuilder::build(
  self : RenderContextBuilder,
  image_header : @image.ImageHeader,
) -> RenderContext raise @bitstream.JxlError {
  let requested_color_encoding = match image_header.metadata.colour_encoding {
    Enum(encoding) => @color.ColorEncodingWithProfile::new(encoding)
    IccProfile(color_space) => {
      let header_is_gray = color_space is Grey
      let parsed_icc = try
        @color.ColorEncodingWithProfile::with_icc(self.embedded_icc)
      catch {
        _ => None // Malformed embedded ICC profile
      } noraise {
        parsed_icc => {
          let icc_is_gray = parsed_icc.is_grayscale()
          if header_is_gray != icc_is_gray {
            raise @bitstream.ValidationFailed(
              "Color channel mismatch between header and ICC profile",
            )
          }
          let is_supported_icc = parsed_icc.icc_profile().length() == 0
          let allow_parsed_icc = !image_header.metadata.xyb_encoded ||
            is_supported_icc
          if allow_parsed_icc {
            Some(parsed_icc)
          } else {
            None
          }
        }
      }
      match parsed_icc {
        Some(profile) => profile
        None =>
          if header_is_gray {
            @color.ColorEncodingWithProfile::new(
              @color.EnumColourEncoding::gray_srgb(
                @color.RenderingIntent::Relative,
              ),
            )
          } else {
            @color.ColorEncodingWithProfile::new(
              @color.EnumColourEncoding::srgb(@color.RenderingIntent::Relative),
            )
          }
      }
    }
  }
  let full_image_region = Region::with_size(
    image_header.width_with_orientation(),
    image_header.height_with_orientation(),
  )
  {
    image_header,
    tracker: self.tracker,
    pool: match self.pool {
      Some(pool) => pool
      None => @threadpool.JxlThreadPool::none()
    },
    frames: [],
    renders_wide: [],
    renders_narrow: [],
    keyframes: [],
    keyframe_in_progress: None,
    refcounts: [],
    frame_deps: [],
    lf_frame: FixedArray::make(4, NO_FRAME),
    reference: FixedArray::make(4, NO_FRAME),
    loading_frame: None,
    loading_render_cache_wide: None,
    loading_render_cache_narrow: None,
    loading_region: None,
    requested_image_region: full_image_region,
    embedded_icc: self.embedded_icc,
    requested_color_encoding,
    cms: (@color.NullCms::{ } : &@color.ColorManagementSystem),
    cached_transform: None,
    force_wide_buffers: self.force_wide_buffers,
  }
}

///|
pub fn RenderContext::alloc_tracker(
  self : RenderContext,
) -> @grid.AllocTracker? {
  self.tracker
}

///|
pub fn RenderContext::set_cms(
  self : RenderContext,
  cms : &@color.ColorManagementSystem,
) -> Unit {
  self.cached_transform = None
  self.cms = cms
}

///|
pub fn RenderContext::suggested_hdr_tf(
  self : RenderContext,
) -> @color.TransferFunction? {
  let tf = match self.image_header.metadata.colour_encoding {
    Enum(e) => e.tf
    IccProfile(_) => {
      let icc = self.embedded_icc().unwrap()
      match @color.icc_tf(icc) {
        Some(tf) => tf
        None => return None
      }
    }
  }
  match tf {
    Pq | Hlg => Some(tf)
    _ => None
  }
}

///|
pub fn RenderContext::request_color_encoding(
  self : RenderContext,
  encoding : @color.ColorEncodingWithProfile,
) -> Unit {
  self.cached_transform = None
  self.requested_color_encoding = encoding
}

///|
pub fn RenderContext::requested_color_encoding(
  self : RenderContext,
) -> @color.ColorEncodingWithProfile {
  self.requested_color_encoding
}

///|
pub fn RenderContext::request_image_region(
  self : RenderContext,
  image_region : Region,
) -> Unit {
  self.requested_image_region = image_region
  self.reset_cache()
}

///|
pub fn RenderContext::image_region(self : RenderContext) -> Region {
  self.requested_image_region
}

///|
/// Returns the image width.
pub fn RenderContext::width(self : RenderContext) -> Int32 {
  self.image_header.size.width
}

///|
/// Returns the image height.
pub fn RenderContext::height(self : RenderContext) -> Int32 {
  self.image_header.size.height
}

///|
pub fn RenderContext::embedded_icc(self : RenderContext) -> Bytes? {
  if self.embedded_icc.length() == 0 {
    None
  } else {
    Some(self.embedded_icc)
  }
}

///|
/// Returns the number of loaded keyframes in the context.
pub fn RenderContext::loaded_keyframes(self : RenderContext) -> Int32 {
  self.keyframes.length()
}

///|
/// Returns the number of loaded frames in the context, including frames that
/// are not shown directly.
pub fn RenderContext::loaded_frames(self : RenderContext) -> Int32 {
  self.frames.length()
}

///|
fn RenderContext::narrow_modular(self : RenderContext) -> Bool {
  !self.force_wide_buffers && self.image_header.metadata.modular_16bit_buffers
}

///|
/// `renders_narrow` (`S = i16`) or `renders_wide` (`S = i32`), as selected by
/// `narrow_modular()`.
fn RenderContext::renders(self : RenderContext) -> Array[FrameRenderHandle] {
  if self.narrow_modular() {
    self.renders_narrow
  } else {
    self.renders_wide
  }
}

///|
fn RenderContext::reference_frames(
  self : RenderContext,
  lf : Int32,
  ref_slots : FixedArray[Int32],
) -> ReferenceFrames {
  {
    lf: if lf != NO_FRAME {
      Some({ frame: self.frames[lf], image: self.renders()[lf], })
    } else {
      None
    },
    refs: FixedArray::makei(4, i => {
      let r = ref_slots[i]
      if r != NO_FRAME {
        Some({ frame: self.frames[r], image: self.renders()[r], })
      } else {
        None
      }
    }),
  }
}

///|
fn RenderContext::preserve_current_frame(self : RenderContext) -> Unit {
  guard self.loading_frame is Some(frame) else { return }
  self.loading_frame = None
  let header = frame.header()
  let idx = self.frames.length()
  self.refcounts.push(0)
  let lf = if header.flags.use_lf_frame() {
    let lf = self.lf_frame[header.lf_level]
    self.refcounts[lf] += 1
    lf
  } else {
    NO_FRAME
  }
  for ref_idx in self.reference {
    if ref_idx != NO_FRAME {
      self.refcounts[ref_idx] += 1
    }
  }
  let deps : FrameDependence = { lf, ref_slots: self.reference.copy(), }
  if header.can_reference() {
    let ref_idx = header.save_as_reference
    self.reference[ref_idx] = idx
  }
  if header.lf_level != 0 {
    let lf_idx = header.lf_level - 1
    self.lf_frame[lf_idx] = idx
  }
  if header.is_keyframe() {
    self.refcounts[idx] += 1
    self.keyframes.push(idx)
    self.keyframe_in_progress = None
  } else if header.frame_type.is_normal_frame() {
    self.keyframe_in_progress = Some(idx)
  }
  let image_region = self.requested_image_region
  let reference_frames = self.reference_frames(deps.lf, deps.ref_slots)
  let refs = reference_frames.refs
  let render_op = self.render_op(frame, reference_frames)
  let narrow = self.narrow_modular()
  let loading_cache = if narrow {
    self.loading_render_cache_narrow
  } else {
    self.loading_render_cache_wide
  }
  let handle = match loading_cache {
    Some(cache) => {
      if narrow {
        self.loading_render_cache_narrow = None
      } else {
        self.loading_render_cache_wide = None
      }
      FrameRenderHandle::from_cache(frame, image_region, cache, render_op, refs)
    }
    None => FrameRenderHandle::new(frame, image_region, render_op, refs)
  }
  self.renders().push(handle)
  self.frames.push(frame)
  self.frame_deps.push(deps)
}

///|
fn RenderContext::loading_frame_(self : RenderContext) -> IndexedFrame? {
  let search_from = match self.keyframe_in_progress {
    Some(x) => x
    None =>
      match self.keyframes.last() {
        Some(x) => x + 1
        None => 0
      }
  }
  if self.loading_frame is Some(f) &&
    f.header().frame_type.is_progressive_frame() {
    return Some(f)
  }
  let mut i = self.frames.length() - 1
  while i >= search_from {
    let f = self.frames[i]
    if f.header().frame_type.is_progressive_frame() {
      return Some(f)
    }
    i -= 1
  }
  None
}

///|
/// Loads a frame header from `bitstream` and starts loading the frame.
///
/// On error the bitstream position is unchanged.
pub fn RenderContext::load_frame_header(
  self : RenderContext,
  bitstream : @bitstream.Bitstream,
) -> IndexedFrame raise @bitstream.JxlError {
  if self.loading_frame is Some(_) && !self.try_finalize_current_frame() {
    abort("another frame is still loading")
  }
  // Parse from a copy so that `bitstream` is untouched on error.
  let bs = bitstream.clone()
  let frame = @frame.Frame::parse(bs, self.image_header, tracker=self.tracker)
  bitstream.skip_bits(bs.num_read_bits() - bitstream.num_read_bits())
  let header = frame.header()
  // Check if LF frame exists
  if header.flags.use_lf_frame() && self.lf_frame[header.lf_level] == NO_FRAME {
    raise uninitialized_lf_frame(header.lf_level)
  }
  let f = IndexedFrame::new(frame, self.frames.length())
  self.loading_frame = Some(f)
  f
}

///|
pub fn RenderContext::current_loading_frame(
  self : RenderContext,
) -> IndexedFrame? {
  ignore(self.try_finalize_current_frame())
  self.loading_frame
}

///|
pub fn RenderContext::finalize_current_frame(self : RenderContext) -> Unit {
  if !self.try_finalize_current_frame() {
    abort("frame is not fully loaded")
  }
}

///|
fn RenderContext::try_finalize_current_frame(self : RenderContext) -> Bool {
  if self.loading_frame is Some(loading_frame) &&
    loading_frame.is_loading_done() {
    self.preserve_current_frame()
    return true
  }
  false
}

///|
/// Returns the frame with the keyframe index, or `None` if the keyframe does
/// not exist.
pub fn RenderContext::keyframe(
  self : RenderContext,
  keyframe_idx : Int32,
) -> IndexedFrame? {
  if keyframe_idx == self.keyframes.length() {
    self.loading_frame_()
  } else if keyframe_idx >= 0 && keyframe_idx < self.keyframes.length() {
    Some(self.frames[self.keyframes[keyframe_idx]])
  } else {
    None
  }
}

///|
pub fn RenderContext::frame(
  self : RenderContext,
  frame_idx : Int32,
) -> IndexedFrame? {
  if self.frames.length() == frame_idx {
    self.loading_frame
  } else if frame_idx >= 0 && frame_idx < self.frames.length() {
    Some(self.frames[frame_idx])
  } else {
    None
  }
}

///|
/// `RenderContext::do_render::<S>`; `narrow` selects `S = i16`.
fn do_render(
  frame : IndexedFrame,
  reference_frames : ReferenceFrames,
  state : FrameRender,
  image_region : Region,
  prev_frame_visibility : (Int32, Int32),
  pool : @threadpool.JxlThreadPool,
  narrow : Bool,
) -> FrameRender {
  if reference_frames.lf is Some(lf) {
    // Spawn LF frame renderer
    let lf_handle = lf.image
    pool.spawn(() => lf_handle.run(image_region))
  }
  for grid in reference_frames.refs {
    if grid is Some(grid) {
      // Spawn reference frame renderer
      let ref_handle = grid.image
      pool.spawn(() => ref_handle.run(image_region))
    }
  }
  let cache = match state {
    InProgress(cache) => cache
    _ => RenderCache::new(frame, narrow)
  }
  try
    render_frame(
      frame, reference_frames, cache, image_region, pool, prev_frame_visibility,
    )
  catch {
    e =>
      if e.unexpected_eof() || is_incomplete_frame(e) {
        if frame.is_loading_done() {
          Failed(e)
        } else {
          InProgress(cache)
        }
      } else {
        Failed(e)
      }
  } noraise {
    grid => Done(grid)
  }
}

///|
fn RenderContext::render_op(
  self : RenderContext,
  frame : IndexedFrame,
  reference_frames : ReferenceFrames,
) -> RenderOp {
  let prev_frame_visibility = self.get_previous_frames_visibility(frame)
  let pool = self.pool
  let narrow = self.narrow_modular()
  fn(state, image_region) {
    do_render(
      frame, reference_frames, state, image_region, prev_frame_visibility, pool,
      narrow,
    )
  }
}

///|
fn RenderContext::get_previous_frames_visibility(
  self : RenderContext,
  frame : IndexedFrame,
) -> (Int32, Int32) {
  let frame_idx = frame.index()
  let (is_keyframe, keyframe_idx) = match
    self.keyframes.binary_search(frame_idx) {
    Ok(val) => (true, val)
    // Handle partial rendering. If val != self.keyframes.len(), is_keyframe()
    // should be false, since if not the index should exist in self.keyframes.
    Err(val) => (frame.header().is_keyframe(), val)
  }
  let visible_frames_num = keyframe_idx + (if is_keyframe { 1 } else { 0 })
  let invisible_frames_num = if is_keyframe {
    0
  } else if keyframe_idx == 0 {
    1 + frame_idx
  } else {
    let last_visible_frame = self.keyframes[keyframe_idx - 1]
    frame_idx - last_visible_frame
  }
  (visible_frames_num, invisible_frames_num)
}

///|
fn RenderContext::spawn_renderer(self : RenderContext, index : Int32) -> Unit {
  if !self.pool.is_multithreaded() {
    // Frame rendering will run immediately, this is not we want.
    return
  }
  let image_region = self.requested_image_region
  let render_handle = self.renders()[index]
  self.pool.spawn(() => render_handle.run(image_region))
}

///|
fn RenderContext::render_by_index(
  self : RenderContext,
  index : Int32,
) -> ImageWithRegion raise @bitstream.JxlError {
  self.renders()[index].run_with_image().blend(None)
}

///|
/// Renders the first keyframe.
///
/// The keyframe should be loaded in prior to rendering, with one of the
/// loading methods.
pub fn RenderContext::render(
  self : RenderContext,
) -> ImageWithRegion raise @bitstream.JxlError {
  self.render_keyframe(0)
}

///|
/// Renders the keyframe.
///
/// The keyframe should be loaded in prior to rendering, with one of the
/// loading methods.
pub fn RenderContext::render_keyframe(
  self : RenderContext,
  keyframe_idx : Int32,
) -> ImageWithRegion raise @bitstream.JxlError {
  guard keyframe_idx >= 0 && keyframe_idx < self.keyframes.length() else {
    raise incomplete_frame()
  }
  let idx = self.keyframes[keyframe_idx]
  let grid = self.render_by_index(idx)
  let frame = self.frames[idx]
  self.postprocess_keyframe(frame, grid)
}

///|
/// Renders the keyframe currently being loaded, or the last keyframe in
/// progress.
pub fn RenderContext::render_loading_keyframe(
  self : RenderContext,
) -> (IndexedFrame, ImageWithRegion) raise @bitstream.JxlError {
  let mut current_frame_grid = None
  if self.loading_frame_() is Some(_) {
    try self.render_loading_frame() catch {
      e => if !is_incomplete_frame(e) { raise e }
    } noraise {
      grid => current_frame_grid = Some(grid)
    }
  }
  let (frame, grid) = match current_frame_grid {
    Some(grid) => (self.loading_frame_().unwrap(), grid)
    None =>
      match self.keyframe_in_progress {
        Some(idx) => {
          let grid = self.render_by_index(idx)
          (self.frames[idx], grid)
        }
        None => raise incomplete_frame()
      }
  }
  let grid = self.postprocess_keyframe(frame, grid)
  (frame, grid)
}

///|
pub fn RenderContext::reset_cache(self : RenderContext) -> Unit {
  let image_region = self.requested_image_region
  self.loading_region = None
  self.loading_render_cache_wide = None
  self.loading_render_cache_narrow = None
  for idx, frame in self.frames {
    if frame.header().frame_type is ReferenceOnly {
      continue
    }
    let deps = self.frame_deps[idx]
    let reference_frames = self.reference_frames(deps.lf, deps.ref_slots)
    let refs = reference_frames.refs
    let render_op = self.render_op(frame, reference_frames)
    self.renders()[idx] = FrameRenderHandle::new(
      frame, image_region, render_op, refs,
    )
  }
}

///|
fn RenderContext::render_loading_frame(
  self : RenderContext,
) -> ImageWithRegion raise @bitstream.JxlError {
  let frame = self.loading_frame_().unwrap()
  if !frame.header().frame_type.is_progressive_frame() {
    raise incomplete_frame()
  }
  let image_region = self.requested_image_region
  let frame_region = image_region_to_frame(frame, image_region, false)
  self.loading_region = Some(frame_region)
  let header = frame.header()
  let narrow = self.narrow_modular()
  // Only `None` counts as failure (`try_parse_lf_global::<S>().is_none()`);
  // a parse error is left to the renderer.
  let lf_global_failed = parse_lf_global(frame, narrow) is None
  if lf_global_failed {
    raise incomplete_frame()
  }
  let lf_frame_idx = self.lf_frame[header.lf_level]
  if header.flags.use_lf_frame() {
    self.spawn_renderer(lf_frame_idx)
  }
  for idx in self.reference {
    if idx != NO_FRAME {
      self.spawn_renderer(idx)
    }
  }
  let loading_cache = if narrow {
    self.loading_render_cache_narrow
  } else {
    self.loading_render_cache_wide
  }
  let state = match loading_cache {
    Some(cache) => {
      if narrow {
        self.loading_render_cache_narrow = None
      } else {
        self.loading_render_cache_wide = None
      }
      InProgress(cache)
    }
    None => Empty
  }
  let reference_frames = self.reference_frames(lf_frame_idx, self.reference)
  let prev_frame_visibility = self.get_previous_frames_visibility(frame)
  let state = do_render(
    frame,
    reference_frames,
    state,
    image_region,
    prev_frame_visibility,
    self.pool,
    narrow,
  )
  let image = match state {
    InProgress(cache) => {
      if narrow {
        self.loading_render_cache_narrow = Some(cache)
      } else {
        self.loading_render_cache_wide = Some(cache)
      }
      raise incomplete_frame()
    }
    Failed(e) => raise e
    Done(image) => {
      let skip_composition = composite_preprocess(frame, image)
      if !skip_composition {
        let oriented_image_region = apply_orientation_to_image_region(
          self.image_header,
          image_region,
        )
        composite(frame, image, reference_frames.refs, oriented_image_region)
      } else {
        image
      }
    }
    _ => abort("todo")
  }
  if frame.header().lf_level > 0 {
    let render = image.upsample_lf(frame.header().lf_level)
    render.fill_opaque_alpha(self.image_header.metadata.ec_info)
    render
  } else {
    image
  }
}

///|
fn RenderContext::cache_color_transform(
  self : RenderContext,
) -> Unit raise @bitstream.JxlError {
  if self.cached_transform is Some(_) {
    return
  }
  let metadata = self.image_header.metadata
  let frame_color_encoding = if metadata.xyb_encoded {
    @color.ColorEncodingWithProfile::new(
      @color.EnumColourEncoding::xyb(@color.RenderingIntent::Perceptual),
    )
  } else {
    match metadata.colour_encoding {
      Enum(encoding) => @color.ColorEncodingWithProfile::new(encoding)
      _ => @color.ColorEncodingWithProfile::with_icc(self.embedded_icc)
    }
  }
  let transform = @color.ColorTransform::builder()
    .set_srgb_icc(!self.cms.supports_linear_tf())
    .from_pq(self.suggested_hdr_tf() is Some(Pq))
    .build(
      frame_color_encoding,
      self.requested_color_encoding,
      metadata.opsin_inverse_matrix,
      metadata.tone_mapping,
      self.cms,
    )
  self.cached_transform = Some(transform)
}

///|
fn RenderContext::postprocess_keyframe(
  self : RenderContext,
  frame : IndexedFrame,
  grid : ImageWithRegion,
) -> ImageWithRegion raise @bitstream.JxlError {
  let frame_header = frame.header()
  let metadata = self.image_header.metadata
  // Transform to requested color encoding
  if grid.ct_done() {
    return grid
  }
  self.cache_color_transform()
  let transform = self.cached_transform.unwrap()
  if transform.is_noop() && !frame_header.do_ycbcr {
    return grid
  }
  let grid = grid.try_clone()
  if frame_header.do_ycbcr {
    grid.convert_modular_color(metadata.bit_depth)
    let cby = grid.as_color_floats_mut()
    @color.ycbcr_to_rgb(cby[0].buf(), cby[1].buf(), cby[2].buf())
  }
  if transform.is_noop() {
    let output_channels = transform.output_channels()
    grid.remove_color_channels(output_channels)
    return grid
  }
  let encoded_color_channels = frame_header.encoded_color_channels()
  if encoded_color_channels < 3 {
    grid.clone_gray()
  }
  grid.convert_modular_color(metadata.bit_depth)
  let channels : Array[FixedArray[Float]] = []
  for i in 0..<3 {
    channels.push(grid.buffer[i].float().buf())
  }
  let mut has_black = false
  let num_ec = grid.buffer.length() - 3
  for i in 0..<min_int(num_ec, metadata.ec_info.length()) {
    let ec_info = metadata.ec_info[i]
    if ec_info.is_black() {
      channels.push(
        grid.convert_channel_to_float_modular(3 + i, ec_info.bit_depth).buf(),
      )
      has_black = true
      break
    }
  }
  if has_black {
    // 0 means full ink; invert samples
    for ch in channels {
      for j in 0..<ch.length() {
        ch[j] = 1.0 - ch[j]
      }
    }
  }
  let output_channels = transform.run_with_threads(channels)
  if output_channels < 3 {
    grid.remove_color_channels(output_channels)
  }
  grid.set_ct_done(true)
  grid
}
