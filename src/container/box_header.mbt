///|
/// Type of JPEG XL container box (four-character code).
///
/// Known types are available as static functions (`ContainerBoxType::codestream()`, ...).
#derive(Eq, Hash, Debug)
pub(all) struct ContainerBoxType(Bytes)

///|
pub impl Show for ContainerBoxType with fn output(self, logger) {
  for b in self.0 {
    logger.write_char(b.to_int().unsafe_to_char())
  }
}

///|
/// JPEG XL signature box.
pub fn ContainerBoxType::jxl() -> ContainerBoxType {
  ContainerBoxType(b"JXL ")
}

///|
/// JPEG XL file type box.
pub fn ContainerBoxType::file_type() -> ContainerBoxType {
  ContainerBoxType(b"ftyp")
}

///|
/// JPEG XL level box.
pub fn ContainerBoxType::jxl_level() -> ContainerBoxType {
  ContainerBoxType(b"jxll")
}

///|
/// JUMBF box.
pub fn ContainerBoxType::jumbf() -> ContainerBoxType {
  ContainerBoxType(b"jumb")
}

///|
/// Exif box.
pub fn ContainerBoxType::exif() -> ContainerBoxType {
  ContainerBoxType(b"Exif")
}

///|
/// XML box, mainly for storing XMP metadata.
pub fn ContainerBoxType::xml() -> ContainerBoxType {
  ContainerBoxType(b"xml ")
}

///|
/// Brotli-compressed box.
pub fn ContainerBoxType::brotli_compressed() -> ContainerBoxType {
  ContainerBoxType(b"brob")
}

///|
/// Frame index box.
pub fn ContainerBoxType::frame_index() -> ContainerBoxType {
  ContainerBoxType(b"jxli")
}

///|
/// JPEG XL codestream box.
pub fn ContainerBoxType::codestream() -> ContainerBoxType {
  ContainerBoxType(b"jxlc")
}

///|
/// JPEG XL partial codestream box.
pub fn ContainerBoxType::partial_codestream() -> ContainerBoxType {
  ContainerBoxType(b"jxlp")
}

///|
/// JPEG bistream reconstruction data box.
pub fn ContainerBoxType::jpeg_reconstruction() -> ContainerBoxType {
  ContainerBoxType(b"jbrd")
}

///|
/// HDR gain map box.
pub fn ContainerBoxType::hdr_gain_map() -> ContainerBoxType {
  ContainerBoxType(b"jhgm")
}

///|
/// The four bytes of the box type.
pub fn ContainerBoxType::bytes(self : ContainerBoxType) -> Bytes {
  self.0
}

///|
/// Box header used in JPEG XL containers.
#derive(Debug)
pub(all) struct ContainerBoxHeader {
  ty : ContainerBoxType
  box_size : UInt64?
  is_last : Bool
}

///|
/// Result of parsing container box header.
#derive(Debug)
pub(all) enum HeaderParseResult {
  /// Box header is read successfully.
  Done(header~ : ContainerBoxHeader, header_size~ : Int32)
  /// Parser needs more data to read a header.
  NeedMoreData
}

///|
fn be_u32(buf : BytesView, off : Int32) -> UInt32 {
  (buf[off].to_uint() << 24) |
  (buf[off + 1].to_uint() << 16) |
  (buf[off + 2].to_uint() << 8) |
  buf[off + 3].to_uint()
}

///|
fn be_u64(buf : BytesView, off : Int32) -> UInt64 {
  (be_u32(buf, off).to_uint64() << 32) | be_u32(buf, off + 4).to_uint64()
}

///|
pub fn ContainerBoxHeader::parse(
  buf : BytesView,
) -> HeaderParseResult raise @bitstream.JxlError {
  let (tbox, box_size, header_size) = if buf.length() >= 16 &&
    buf[0] == 0 &&
    buf[1] == 0 &&
    buf[2] == 0 &&
    buf[3] == 1 {
    let xlbox = be_u64(buf, 8)
    let tbox = ContainerBoxType(buf[4:8].to_owned())
    if xlbox < 16UL {
      raise InvalidBox
    }
    (tbox, Some(xlbox - 16UL), 16)
  } else if buf.length() >= 8 {
    let sbox = be_u32(buf, 0)
    let tbox = ContainerBoxType(buf[4:8].to_owned())
    let sbox = if sbox == 0U {
      None
    } else if sbox >= 8U {
      Some((sbox - 8U).to_uint64())
    } else {
      raise InvalidBox
    }
    (tbox, sbox, 8)
  } else {
    return NeedMoreData
  }
  let is_last = box_size is None
  Done(header={ ty: tbox, box_size, is_last, }, header_size~)
}

///|
pub fn ContainerBoxHeader::box_type(
  self : ContainerBoxHeader,
) -> ContainerBoxType {
  self.ty
}

///|
pub fn ContainerBoxHeader::box_size(self : ContainerBoxHeader) -> UInt64? {
  self.box_size
}

///|
pub fn ContainerBoxHeader::is_last(self : ContainerBoxHeader) -> Bool {
  self.is_last
}
