///|
/// Render cache of a frame being rendered (jxl-render `RenderCache`):
/// parsed LfGlobal, HfGlobal and LF groups, kept so that progressive
/// rendering does not reparse them.
///
/// `RenderCache<S>`: `narrow` is `S = i16` (otherwise `S = i32`).
struct RenderCache {
  mut lf_global : @frame.LfGlobal?
  mut hf_global : @frame.HfGlobal?
  lf_groups : Map[Int32, @frame.LfGroup]
  narrow : Bool
}

///|
fn RenderCache::new(frame : IndexedFrame, narrow : Bool) -> RenderCache {
  let frame_header = frame.header()
  let jpeg_upsampling = frame_header.jpeg_upsampling
  let shifts_cbycr = FixedArray::makei(3, idx => {
    @modular.ChannelShift::from_jpeg_upsampling(jpeg_upsampling, idx)
  })
  // Computed and discarded, as upstream.
  let lf_width = (frame_header.color_sample_width() + 7) / 8
  let lf_height = (frame_header.color_sample_height() + 7) / 8
  let whd = FixedArray::make(3, (lf_width, lf_height))
  for i, shift in shifts_cbycr {
    whd[i] = shift.shift_size((lf_width, lf_height))
  }
  ignore(whd)
  { lf_global: None, hf_global: None, lf_groups: {}, narrow, }
}

///|
/// Render state of a frame (jxl-render `FrameRender`).
///
/// Upstream variant names, except `None` → `Empty` and `Err` → `Failed`
/// (to not shadow `Option::None`/`Result::Err`).
priv enum FrameRender {
  Empty
  Rendering
  InProgress(RenderCache)
  Done(ImageWithRegion)
  Blended(ImageWithRegion)
  Failed(@bitstream.JxlError)
  ErrTaken
}

///|
/// `RenderOp<S>`: renders a frame from the given state.
type RenderOp = (FrameRender, Region) -> FrameRender

///|
/// A handle to the render state of a frame (jxl-render `FrameRenderHandle`).
///
/// Upstream protects `render` with a mutex and a condvar for multithreaded
/// rendering; rendering is sequential here.
struct FrameRenderHandle {
  frame : IndexedFrame
  image_region : Region
  mut render : FrameRender
  render_op : RenderOp
  refs : FixedArray[Reference?]
}

///|
fn FrameRenderHandle::new(
  frame : IndexedFrame,
  image_region : Region,
  render_op : RenderOp,
  refs : FixedArray[Reference?],
) -> FrameRenderHandle {
  { frame, image_region, render: Empty, render_op, refs, }
}

///|
fn FrameRenderHandle::from_cache(
  frame : IndexedFrame,
  image_region : Region,
  cache : RenderCache,
  render_op : RenderOp,
  refs : FixedArray[Reference?],
) -> FrameRenderHandle {
  { frame, image_region, render: InProgress(cache), render_op, refs, }
}

///|
/// Renders the frame if not rendered yet, and returns a handle to the
/// rendered image.
fn FrameRenderHandle::run_with_image(
  self : FrameRenderHandle,
) -> RenderedImage raise @bitstream.JxlError {
  match self.start_render() {
    Some(state) => {
      let render_result = (self.render_op)(state, self.image_region)
      match render_result {
        InProgress(_) => {
          self.done_render(render_result)
          raise incomplete_frame()
        }
        Failed(e) => {
          self.done_render(ErrTaken)
          raise e
        }
        _ => ()
      }
      self.done_render(render_result)
    }
    None => self.wait_until_render()
  }
  RenderedImage::new(self)
}

///|
/// Renders the frame if not rendered yet, ignoring errors.
fn FrameRenderHandle::run(
  self : FrameRenderHandle,
  image_region : Region,
) -> Unit {
  if self.start_render_silent() is Some(state) {
    let render_result = (self.render_op)(state, image_region)
    self.done_render(render_result)
  }
}

///|
/// Resets the render state, returning the previous state.
fn FrameRenderHandle::reset(self : FrameRenderHandle) -> FrameRender {
  let r = self.render
  self.render = Empty
  r
}

///|
fn FrameRenderHandle::start_render(
  self : FrameRenderHandle,
) -> FrameRender? raise @bitstream.JxlError {
  let render = self.render
  self.render = Rendering
  match render {
    Empty | InProgress(_) => Some(render)
    Failed(e) => {
      self.render = ErrTaken
      raise e
    }
    ErrTaken => {
      self.render = ErrTaken
      raise failed_reference()
    }
    render => {
      self.render = render
      None
    }
  }
}

///|
fn FrameRenderHandle::start_render_silent(
  self : FrameRenderHandle,
) -> FrameRender? {
  let render = self.render
  self.render = Rendering
  match render {
    Empty | InProgress(_) => Some(render)
    render => {
      self.render = render
      None
    }
  }
}

///|
/// Checks that the frame is rendered (upstream waits on a condvar while
/// another thread renders; rendering is sequential here, so `Rendering`
/// would mean a dependency cycle).
fn FrameRenderHandle::wait_until_render(
  self : FrameRenderHandle,
) -> Unit raise @bitstream.JxlError {
  match self.render {
    Rendering => abort("frame render is reentrant")
    Done(_) | Blended(_) => ()
    Empty | InProgress(_) => {
      self.render = Empty
      raise incomplete_frame()
    }
    Failed(e) => {
      self.render = Empty
      raise e
    }
    ErrTaken => {
      self.render = Empty
      raise failed_reference()
    }
  }
}

///|
fn FrameRenderHandle::done_render(
  self : FrameRenderHandle,
  render : FrameRender,
) -> Unit {
  guard !(render is Rendering) else { abort("done_render with Rendering") }
  self.render = render
}
