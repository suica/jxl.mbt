// Port of jxl-color/src/icc.rs: functions related to ICC profiles.
//
// - `read_icc` and `decode_icc` can be used to read embedded ICC profile from the bitstream.
// - `colour_encoding_to_icc` can be used to create an ICC profile to embed into the decoded
//   image file, or to be used by the color management system for various purposes.

///|
/// `#[non_exhaustive]` upstream: readable outside, not constructible.
pub struct IccHeader {
  color_space : Bytes
  rendering_intent : RenderingIntent
}

///|
priv struct IccTag {
  tag : Bytes
  data_offset : Int32
  len : Int32
}
