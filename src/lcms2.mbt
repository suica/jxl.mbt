// Port of jxl-oxide/src/lcms2.rs: Little CMS 2 integration for ICC profile
// handling, on `@cms` (the MoonBit port of Little CMS 2's float pipeline).

///|
/// Little CMS 2 integration for ICC profile handling.
#derive(Debug)
pub(all) struct Lcms2 {}

///|
priv struct Lcms2PreparedTransform {
  transform : @cms.Transform
  from_channels : Int32
  to_channels : Int32
}

///|
fn lcms2_intent(intent : @image.RenderingIntent) -> @cms.RenderingIntent {
  match intent {
    Perceptual => Perceptual
    Relative => Relative
    Saturation => Saturation
    Absolute => Absolute
  }
}

///|
pub impl @color.ColorManagementSystem for Lcms2 with fn prepare_transform(
  _self,
  from_icc,
  to_icc,
  intent,
) {
  let from_profile = @cms.Profile::parse(from_icc)
  let from_channels = from_profile.num_channels()
  let to_profile = @cms.Profile::parse(to_icc)
  let to_channels = to_profile.num_channels()
  // TYPE float, channels as the profiles' colour spaces, NO_CACHE
  let transform = @cms.Transform::new(
    from_profile,
    to_profile,
    lcms2_intent(intent),
  )
  ({ transform, from_channels, to_channels, } : Lcms2PreparedTransform)
  as &@color.PreparedTransform
}

///|
impl @color.PreparedTransform for Lcms2PreparedTransform with fn num_input_channels(
  self,
) {
  self.from_channels
}

///|
impl @color.PreparedTransform for Lcms2PreparedTransform with fn num_output_channels(
  self,
) {
  self.to_channels
}

///|
impl @color.PreparedTransform for Lcms2PreparedTransform with fn transform(
  self,
  channels,
  start,
  len,
) {
  let { transform, from_channels, to_channels, } = self
  let buf_in = FixedArray::make(1024 * from_channels, (0.0 : Float))
  let buf_out = FixedArray::make(1024 * to_channels, (0.0 : Float))
  let mut idx = 0
  while idx < len {
    let chunk_len = @cmp.minimum(len - idx, 1024)
    for k in 0..<chunk_len {
      for channel_idx in 0..<from_channels {
        buf_in[k * from_channels + channel_idx] = channels[channel_idx][start +
          idx +
          k]
      }
    }
    transform.transform_interleaved(buf_in, buf_out, chunk_len)
    for k in 0..<chunk_len {
      for channel_idx in 0..<to_channels {
        channels[channel_idx][start + idx + k] = buf_out[k * to_channels +
          channel_idx]
      }
    }
    idx += 1024
  }
}
