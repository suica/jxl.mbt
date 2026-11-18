// ICC profile parsing (header, tag directory and the tag types needed for
// colour transforms), following Little CMS 2.19 (as vendored by lcms2-sys 4.0.7) `cmsio0.c` / `cmstypes.c`.

///|
priv struct TagEntry {
  sig : UInt32
  offset : Int32
  size : Int32
}

///|
/// A parsed ICC profile (v2 or v4).
pub struct Profile {
  priv data : Bytes
  /// Encoded (validated) version, e.g. `0x04300000`.
  version : UInt32
  device_class : UInt32
  color_space : UInt32
  pcs : UInt32
  /// Rendering intent from the header (0..3, possibly other values).
  rendering_intent : UInt32
  priv tags : Array[TagEntry]
}

///|
priv struct Reader {
  data : Bytes
  mut pos : Int32
}

///|
fn Reader::need(self : Reader, n : Int32) -> Unit raise @bitstream.JxlError {
  if self.pos < 0 || n < 0 || self.pos + n > self.data.length() {
    raise cms_error("IccParseFailure: unexpected end of profile")
  }
}

///|
fn Reader::u8(self : Reader) -> Int32 raise @bitstream.JxlError {
  self.need(1)
  let v = self.data[self.pos].to_int()
  self.pos += 1
  v
}

///|
fn Reader::u16(self : Reader) -> Int32 raise @bitstream.JxlError {
  self.need(2)
  let v = (self.data[self.pos].to_int() << 8) | self.data[self.pos + 1].to_int()
  self.pos += 2
  v
}

///|
fn Reader::u32(self : Reader) -> UInt32 raise @bitstream.JxlError {
  self.need(4)
  let d = self.data
  let p = self.pos
  let v = (d[p].to_uint() << 24) |
    (d[p + 1].to_uint() << 16) |
    (d[p + 2].to_uint() << 8) |
    d[p + 3].to_uint()
  self.pos += 4
  v
}

///|
/// `_cmsRead15Fixed16Number`
fn Reader::s15f16(self : Reader) -> Double raise @bitstream.JxlError {
  let v = self.u32().reinterpret_as_int()
  v.to_double() / 65536.0
}

///|
/// `_cmsReadAlignment`
fn Reader::align(self : Reader) -> Unit raise @bitstream.JxlError {
  let next = (self.pos + 3) & -4
  self.need(next - self.pos)
  self.pos = next
}

///|
/// `_validatedVersion`
fn validated_version(v : UInt32) -> UInt32 {
  let mut b0 = (v >> 24) & 0xFF
  let b1 = (v >> 16) & 0xFF
  if b0 > 0x09 {
    b0 = 0x09
  }
  let mut t1 = b1 & 0xF0
  let mut t2 = b1 & 0x0F
  if t1 > 0x90 {
    t1 = 0x90
  }
  if t2 > 0x09 {
    t2 = 0x09
  }
  (b0 << 24) | ((t1 | t2) << 16)
}

///|
fn valid_device_class(cl : UInt32) -> Bool {
  if cl == 0 {
    return true
  }
  cl == SIG_INPUT_CLASS ||
  cl == SIG_DISPLAY_CLASS ||
  cl == SIG_OUTPUT_CLASS ||
  cl == SIG_LINK_CLASS ||
  cl == SIG_ABSTRACT_CLASS ||
  cl == SIG_COLORSPACE_CLASS ||
  cl == SIG_NAMED_COLOR_CLASS ||
  cl == 0x63656E63 || // 'cenc'
  cl == 0x6D696420 || // 'mid '
  cl == 0x6D6C6E6B || // 'mlnk'
  cl == 0x6D766973 // 'mvis'
}

///|
/// Parses an ICC profile (`cmsOpenProfileFromMem` / `_cmsReadHeader`).
pub fn Profile::parse(data : Bytes) -> Profile raise @bitstream.JxlError {
  if data.length() < 132 {
    raise cms_error("IccParseFailure: profile is too short")
  }
  let r : Reader = { data, pos: 0, }
  let header_size0 = r.u32().reinterpret_as_int()
  r.pos = 0x0C
  let device_class = r.u32()
  let color_space = r.u32()
  let pcs = r.u32()
  r.pos = 0x24
  if r.u32() != SIG_MAGIC_NUMBER {
    raise cms_error("IccParseFailure: not an ICC profile, invalid signature")
  }
  r.pos = 0x08
  let version = validated_version(r.u32())
  if version > 0x5000000 {
    raise cms_error("IccParseFailure: unsupported profile version")
  }
  if !valid_device_class(device_class) {
    raise cms_error("IccParseFailure: unsupported device class")
  }
  r.pos = 0x40
  let rendering_intent = r.u32()
  // Make sure HeaderSize is lower than profile size
  let header_size = if header_size0 < 0 || header_size0 >= data.length() {
    data.length()
  } else {
    header_size0
  }
  r.pos = 128
  let tag_count = r.u32()
  if tag_count > 100U {
    raise cms_error("IccParseFailure: too many tags")
  }
  let tags : Array[TagEntry] = []
  for _ in 0..<tag_count.reinterpret_as_int() {
    let sig = r.u32()
    let offset = r.u32()
    let size = r.u32()
    // Perform some sanity check. Offset + size should fall inside file.
    if size == 0 || offset == 0 {
      continue
    }
    let end = offset.to_uint64() + size.to_uint64()
    if end > header_size.to_uint64() {
      continue
    }
    tags.push({
      sig,
      offset: offset.reinterpret_as_int(),
      size: size.reinterpret_as_int(),
    })
  }
  for i in 0..<tags.length() {
    for j in 0..<tags.length() {
      if i != j && tags[i].sig == tags[j].sig {
        raise cms_error("IccParseFailure: duplicate tag found")
      }
    }
  }
  { data, version, device_class, color_space, pcs, rendering_intent, tags, }
}

///|
/// The raw profile bytes.
pub fn Profile::bytes(self : Profile) -> Bytes {
  self.data
}

///|
/// `cmsIsTag`
fn Profile::is_tag(self : Profile, sig : UInt32) -> Bool {
  for t in self.tags {
    if t.sig == sig {
      return true
    }
  }
  false
}

///|
fn Profile::find_tag(self : Profile, sig : UInt32) -> TagEntry? {
  for t in self.tags {
    if t.sig == sig {
      return Some(t)
    }
  }
  None
}

///|
/// Returns a reader positioned after the tag base (type + reserved) and the
/// tag's type signature.
fn Profile::open_tag(
  self : Profile,
  sig : UInt32,
) -> (Reader, UInt32, TagEntry)? raise @bitstream.JxlError {
  guard self.find_tag(sig) is Some(entry) else { return None }
  if entry.size < 8 {
    raise cms_error("IccParseFailure: tag too small")
  }
  let r : Reader = { data: self.data, pos: entry.offset, }
  let ty = r.u32()
  r.u32() |> ignore
  Some((r, ty, entry))
}

///|
/// Number of channels of a colour space (`cmsChannelsOfColorSpace`).
fn channels_of_color_space(cs : UInt32) -> Int32 {
  match cs {
    0x4D434831 | 0x31434C52 => 1 // MCH1, 1CLR
    0x47524159 => 1 // GRAY
    0x4D434832 | 0x32434C52 => 2 // MCH2, 2CLR
    0x58595A20
    // XYZ
    | 0x4C616220
    // Lab
    | 0x4C757620
    // Luv
    | 0x59436272
    // YCbr
    | 0x59787920
    // Yxy
    | 0x52474220
    // RGB
    | 0x48535620
    // HSV
    | 0x484C5320
    // HLS
    | 0x434D5920
    // CMY
    | 0x4D434833
    // MCH3
    | 0x33434C52 => 3 // 3CLR
    0x4C754B20 | 0x434D594B | 0x4D434834 | 0x34434C52 => 4 // LuvK, CMYK, MCH4, 4CLR
    0x4D434835 | 0x35434C52 => 5
    0x4D434836 | 0x36434C52 => 6
    0x4D434837 | 0x37434C52 => 7
    0x4D434838 | 0x38434C52 => 8
    0x4D434839 | 0x39434C52 => 9
    0x4D434841 | 0x41434C52 => 10
    0x4D434842 | 0x42434C52 => 11
    0x4D434843 | 0x43434C52 => 12
    0x4D434844 | 0x44434C52 => 13
    0x4D434845 | 0x45434C52 => 14
    0x4D434846 | 0x46434C52 => 15
    _ => -1
  }
}

///|
/// Number of channels of the profile's data colour space.
/// Unknown colour spaces count as 3 channels (`cmsChannelsOf`).
pub fn Profile::num_channels(self : Profile) -> Int32 {
  let n = channels_of_color_space(self.color_space)
  if n < 0 {
    3
  } else {
    n
  }
}

///|
/// Whether the profile describes a grayscale colour space.
pub fn Profile::is_gray(self : Profile) -> Bool {
  self.color_space == SIG_GRAY_DATA
}

///|
/// Whether the profile describes a CMYK colour space.
pub fn Profile::is_cmyk(self : Profile) -> Bool {
  self.color_space == SIG_CMYK_DATA
}

///|
/// `Type_XYZ_Read` for an `XYZ ` tag.
fn Profile::read_xyz(
  self : Profile,
  sig : UInt32,
) -> (Double, Double, Double)? raise @bitstream.JxlError {
  guard self.open_tag(sig) is Some((r, ty, _)) else { return None }
  if ty != SIG_XYZ_TYPE {
    raise cms_error("IccParseFailure: invalid XYZ tag type")
  }
  let x = r.s15f16()
  let y = r.s15f16()
  let z = r.s15f16()
  Some((x, y, z))
}

///|
/// `Type_Curve_Read`
fn read_curv(r : Reader) -> ToneCurve raise @bitstream.JxlError {
  let count = r.u32()
  if count == 0 {
    // Linear.
    return ToneCurve::parametric(1, [1.0])
  }
  if count == 1 {
    // Specified as the exponent of gamma function (u8Fixed8)
    let g = r.u16()
    let gamma = (g >> 8).to_double() + (g & 0xFF).to_double() / 256.0
    return ToneCurve::parametric(1, [gamma])
  }
  if count > 0x7FFF {
    raise cms_error("IccParseFailure: curve too large")
  }
  let n = count.reinterpret_as_int()
  r.need(2 * n)
  let table = FixedArray::make(n, 0)
  for i in 0..<n {
    table[i] = r.u16()
  }
  ToneCurve::tabulated16(table)
}

///|
/// `Type_ParametricCurve_Read`
fn read_para(r : Reader) -> ToneCurve raise @bitstream.JxlError {
  let params_by_type = [1, 3, 4, 5, 7]
  let ty = r.u16()
  r.u16() |> ignore
  if ty > 4 {
    raise cms_error("IccParseFailure: unknown parametric curve type")
  }
  let n = params_by_type[ty]
  let params = FixedArray::make(10, 0.0)
  for i in 0..<n {
    params[i] = r.s15f16()
  }
  ToneCurve::parametric(ty + 1, params)
}

///|
/// `ReadEmbeddedCurve`
fn read_embedded_curve(r : Reader) -> ToneCurve raise @bitstream.JxlError {
  let ty = r.u32()
  r.u32() |> ignore
  if ty == SIG_CURVE_TYPE {
    read_curv(r)
  } else if ty == SIG_PARAMETRIC_CURVE_TYPE {
    read_para(r)
  } else {
    raise cms_error("IccParseFailure: unknown curve type")
  }
}

///|
/// Reads a TRC tag (`curv` or `para`).
fn Profile::read_trc(
  self : Profile,
  sig : UInt32,
) -> ToneCurve? raise @bitstream.JxlError {
  guard self.open_tag(sig) is Some((r, ty, _)) else { return None }
  if ty == SIG_CURVE_TYPE {
    Some(read_curv(r))
  } else if ty == SIG_PARAMETRIC_CURVE_TYPE {
    Some(read_para(r))
  } else {
    raise cms_error("IccParseFailure: unsupported TRC tag type")
  }
}
