// `TransformExecutor<f32>` (`transform.rs`).

///|
/// A prepared `f32` transform (`TransformF32Executor`).
///
/// `transform(src, src_len, dst, dst_len)` transforms the interleaved samples
/// `src[0..src_len]` into `dst[0..dst_len]` (upstream passes slices).
pub(all) struct TransformF32Executor {
  priv exec : (FixedArray[Float], Int32, FixedArray[Float], Int32) -> Unit raise CmsError
}

///|
pub fn TransformF32Executor::transform(
  self : TransformF32Executor,
  src : FixedArray[Float],
  src_len : Int32,
  dst : FixedArray[Float],
  dst_len : Int32,
) -> Unit raise CmsError {
  (self.exec)(src, src_len, dst, dst_len)
}

///|
/// The lane checks every executor starts with.
fn check_lanes(
  src_len : Int32,
  src_channels : Int32,
  dst_len : Int32,
  dst_channels : Int32,
) -> Unit raise CmsError {
  if src_len / src_channels != dst_len / dst_channels {
    raise LaneSizeMismatch
  }
  if src_len % src_channels != 0 {
    raise LaneMultipleOfChannels
  }
  if dst_len % dst_channels != 0 {
    raise LaneMultipleOfChannels
  }
}

///|
/// `chunks_exact(src_channels).zip(chunks_exact_mut(dst_channels))` count.
fn pixel_count(
  src_len : Int32,
  src_channels : Int32,
  dst_len : Int32,
  dst_channels : Int32,
) -> Int32 {
  (src_len / src_channels).min(dst_len / dst_channels)
}
