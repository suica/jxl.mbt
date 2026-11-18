// Port of jxl-oxide/src/aux_box/exif.rs.

///|
/// Raw Exif metadata.
pub struct RawExif {
  priv tiff_header_offset : UInt32
  priv payload : BytesView
}

///|
fn RawExif::new(box_data : Bytes) -> RawExif raise @bitstream.JxlError {
  if box_data.length() < 4 {
    raise @bitstream.ValidationFailed("Exif box is too short")
  }
  let tiff = box_data[0:4]
  let payload = box_data[4:]
  let tiff_header_offset = (tiff[0].to_uint() << 24) |
    (tiff[1].to_uint() << 16) |
    (tiff[2].to_uint() << 8) |
    tiff[3].to_uint()
  if tiff_header_offset >= payload.length().reinterpret_as_uint() {
    raise @bitstream.ValidationFailed(
      "tiff_header_offset of Exif box is too large",
    )
  }
  { tiff_header_offset, payload, }
}

///|
/// Returns the offset of TIFF header within the payload.
pub fn RawExif::tiff_header_offset(self : RawExif) -> UInt32 {
  self.tiff_header_offset
}

///|
/// Returns the payload.
pub fn RawExif::payload(self : RawExif) -> BytesView {
  self.payload
}
