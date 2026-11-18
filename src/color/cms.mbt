// Port of jxl-color `cms.rs`.

///|
/// Color management system that handles ICCv4 profiles.
///
/// Implementations report failures by raising `@bitstream.JxlError`
/// (preferably `Color("CmsFailure: <details>")`).
pub(open) trait ColorManagementSystem {
  /// Prepares color transformation between two ICC profiles.
  fn prepare_transform(
    Self,
    from_icc : Bytes,
    to_icc : Bytes,
    intent : RenderingIntent,
  ) -> &PreparedTransform raise @bitstream.JxlError

  /// Returns whether the CMS supports linear transfer function.
  ///
  /// This method will return `false` if it doesn't support (or it lacks precision to handle)
  /// linear transfer function. Defaults to `true`.
  fn supports_linear_tf(Self) -> Bool = _
}

///|
impl ColorManagementSystem with fn supports_linear_tf(_self) {
  true
}

///|
/// Prepared transformation created by [`ColorManagementSystem`].
///
/// Prepared transformations may be cached by the decoder.
pub(open) trait PreparedTransform {
  /// The number of expected input channels.
  fn num_input_channels(Self) -> Int32

  /// The number of expected output channels.
  fn num_output_channels(Self) -> Int32

  /// Performs prepared color transformation in place.
  ///
  /// `channels` are planar sample buffers; the samples `start..start + len`
  /// of each buffer are transformed. There are at least
  /// `max(num_input_channels, num_output_channels)` buffers; the first
  /// `num_input_channels` hold the input and the first `num_output_channels`
  /// receive the output.
  fn transform(
    Self,
    channels : Array[FixedArray[Float]],
    start : Int32,
    len : Int32,
  ) -> Unit raise @bitstream.JxlError
}

///|
/// "Null" color management system that fails on every operation.
#derive(Debug)
pub(all) struct NullCms {}

///|
pub impl ColorManagementSystem for NullCms with fn prepare_transform(
  _self,
  _from_icc,
  _to_icc,
  _intent,
) {
  raise @bitstream.Color("CmsNotAvailable")
}
