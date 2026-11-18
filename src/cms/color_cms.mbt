// Integration with `@color.ColorManagementSystem`, mirroring jxl-oxide's
// `moxcms.rs` / `lcms2.rs` (float pipelines, channel count only formats).

///|
/// The pure MoonBit CMS. Implements `@color.ColorManagementSystem`.
#derive(Debug)
pub(all) struct MoonCms {}

///|
fn intent_from_image(intent : @image.RenderingIntent) -> RenderingIntent {
  match intent {
    @image.RenderingIntent::Perceptual => Perceptual
    @image.RenderingIntent::Relative => Relative
    @image.RenderingIntent::Saturation => Saturation
    @image.RenderingIntent::Absolute => Absolute
  }
}

///|
pub impl @color.ColorManagementSystem for MoonCms with fn prepare_transform(
  _self,
  from_icc,
  to_icc,
  intent,
) {
  let t = Transform::from_icc(from_icc, to_icc, intent_from_image(intent)) catch {
    @bitstream.JxlError::Color(msg) =>
      raise @bitstream.JxlError::Color("CmsFailure: \{msg}")
    e => raise e
  }
  t as &@color.PreparedTransform
}

///|
pub impl @color.PreparedTransform for Transform with fn num_input_channels(self) {
  self.num_input_channels
}

///|
pub impl @color.PreparedTransform for Transform with fn num_output_channels(
  self,
) {
  self.num_output_channels
}

///|
pub impl @color.PreparedTransform for Transform with fn transform(
  self,
  channels,
  start,
  len,
) {
  self.transform_planar_range(channels, start, len)
}
