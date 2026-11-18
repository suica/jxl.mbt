// Port of jxl-color/src/icc/parse.rs.

///|
priv struct IccProfileInfo {
  color_space : Bytes
  rendering_intent : RenderingIntent
  chad : FixedArray[Int32]
  wtpt : FixedArray[Int32]
  trc_k : KnownIccTrc?
  trc_rgb : FixedArray[KnownIccTrc]?
  xyz_rgb : FixedArray[FixedArray[Int32]]?
}

///|
fn IccProfileInfo::is_rgb(self : IccProfileInfo) -> Bool {
  self.color_space == b"RGB "
}

///|
fn IccProfileInfo::is_cmyk(self : IccProfileInfo) -> Bool {
  self.color_space == b"CMYK"
}

///|
fn IccProfileInfo::is_grayscale(self : IccProfileInfo) -> Bool {
  self.color_space == b"GRAY"
}

///|
fn IccProfileInfo::rendering_intent(self : IccProfileInfo) -> RenderingIntent {
  self.rendering_intent
}

///|
fn IccProfileInfo::trc_color(self : IccProfileInfo) -> TransferFunction? {
  guard self.trc_rgb is Some(trc) else { return None }
  let r = trc[0]
  let g = trc[1]
  let b = trc[2]
  if r == g && g == b {
    Some(r.to_transfer_function())
  } else {
    None
  }
}

///|
fn IccProfileInfo::trc_gray(self : IccProfileInfo) -> TransferFunction? {
  self.trc_k.map(KnownIccTrc::to_transfer_function)
}

///|
fn IccProfileInfo::chad_f32(self : IccProfileInfo) -> FixedArray[Float] {
  self.chad.map(x => Float::from_int(x) / (65536.0 : Float))
}

///|
fn IccProfileInfo::chad_inv(self : IccProfileInfo) -> FixedArray[Float] {
  let chad_mat = self.chad_f32()
  matinv(chad_mat)
}

///|
/// Rust `(f * 1e6 + 0.5) as i32`.
fn to_customxy_component(f : Float) -> Int32 {
  (f * 1.0e6 + 0.5).to_int()
}

///|
fn IccProfileInfo::primaries(self : IccProfileInfo) -> Primaries? {
  let primaries_to_enum : Array[(FixedArray[FixedArray[Float]], Primaries)] = [
    (primaries_srgb, Srgb),
    (primaries_p3, P3),
    (primaries_bt2100, Bt2100),
  ]
  guard self.xyz_rgb is Some(xyz_rgb) else { return None }
  let xyz_rgb_mat = FixedArray::makei(9, idx => {
    let v = xyz_rgb[idx % 3][idx / 3]
    Float::from_int(v) / (65536.0 : Float)
  })
  let chad_inv = self.chad_inv()
  let a = matmul3(chad_inv, xyz_rgb_mat)
  let xyz_sum : FixedArray[Float] = [
    a[0] + a[3] + a[6],
    a[1] + a[4] + a[7],
    a[2] + a[5] + a[8],
  ]
  let primaries : FixedArray[FixedArray[Float]] = [
    [a[0] / xyz_sum[0], a[3] / xyz_sum[0]],
    [a[1] / xyz_sum[1], a[4] / xyz_sum[1]],
    [a[2] / xyz_sum[2], a[5] / xyz_sum[2]],
  ]
  for entry in primaries_to_enum {
    let (known_primaries, ret) = entry
    let mut matched = true
    for y in 0..<3 {
      for x in 0..<2 {
        let diff = (primaries[y][x] - known_primaries[y][x]).abs()
        if diff >= 1.0e-4 {
          matched = false
        }
      }
    }
    if matched {
      return Some(ret)
    }
  }
  Some(
    Custom(
      red={
        x: to_customxy_component(primaries[0][0]),
        y: to_customxy_component(primaries[0][1]),
      },
      green={
        x: to_customxy_component(primaries[1][0]),
        y: to_customxy_component(primaries[1][1]),
      },
      blue={
        x: to_customxy_component(primaries[2][0]),
        y: to_customxy_component(primaries[2][1]),
      },
    ),
  )
}

///|
fn IccProfileInfo::media_white(self : IccProfileInfo) -> FixedArray[Float] {
  self.wtpt.map(v => Float::from_int(v) / (65536.0 : Float))
}

///|
fn IccProfileInfo::white_point(self : IccProfileInfo) -> WhitePoint {
  let wp_to_enum : Array[(FixedArray[Float], WhitePoint)] = [
    (illuminant_d65, D65),
    (illuminant_dci, Dci),
    (illuminant_e, E),
  ]
  let chad_inv = self.chad_inv()
  let ill_xyz = matmul3vec(chad_inv, self.media_white())
  let xyz_sum = ill_xyz[0] + ill_xyz[1] + ill_xyz[2]
  let illuminant : FixedArray[Float] = [
    ill_xyz[0] / xyz_sum,
    ill_xyz[1] / xyz_sum,
  ]
  for entry in wp_to_enum {
    let (known_wp, ret) = entry
    let mut matched = true
    for x in 0..<2 {
      let diff = (illuminant[x] - known_wp[x]).abs()
      if diff >= 1.0e-4 {
        matched = false
      }
    }
    if matched {
      return ret
    }
  }
  Custom({
    x: to_customxy_component(illuminant[0]),
    y: to_customxy_component(illuminant[1]),
  })
}

///|
#derive(Eq)
priv enum KnownIccTrc {
  ParametricGamma(UInt32)
  Linear
  Srgb
  Bt709
  Pq
  Hlg
}

///|
fn KnownIccTrc::to_transfer_function(self : KnownIccTrc) -> TransferFunction {
  match self {
    ParametricGamma(g) => {
      let g = g.to_uint64()
      let g_1e7 = (g * 10000000 + 32768) / 65536
      Gamma(g=g_1e7.to_uint().reinterpret_as_int(), inverted=false)
    }
    Linear => Linear
    Srgb => Srgb
    Bt709 => Bt709
    Pq => Pq
    Hlg => Hlg
  }
}

///|
fn KnownIccTrc::from_gamma(g_s15fixed16 : Int32) -> KnownIccTrc? {
  if g_s15fixed16 <= 65535 {
    None
  } else if g_s15fixed16 == 65536 {
    Some(Linear)
  } else {
    Some(ParametricGamma(g_s15fixed16.reinterpret_as_uint()))
  }
}

///|
priv struct IccProfile {
  header : IccHeader
  tags : Array[RawTag]
}

///|
fn IccProfile::color_space(self : IccProfile) -> ColourSpace {
  let color_space = self.header.color_space
  if color_space == b"RGB " || color_space == b"CMYK" {
    Rgb
  } else if color_space == b"GRAY" {
    Grey
  } else {
    Unknown
  }
}

///|
fn IccProfile::is_cmyk(self : IccProfile) -> Bool {
  self.header.color_space == b"CMYK"
}

///|
priv struct RawTag {
  tag : Bytes
  data : BytesView
}

///|
fn read_be32_u(b : BytesView, i : Int32) -> UInt32 {
  (b[i].to_uint() << 24) |
  (b[i + 1].to_uint() << 16) |
  (b[i + 2].to_uint() << 8) |
  b[i + 3].to_uint()
}

///|
fn read_be32_i(b : BytesView, i : Int32) -> Int32 {
  read_be32_u(b, i).reinterpret_as_int()
}

///|
fn parse_icc_raw(profile : Bytes) -> IccProfile raise @bitstream.JxlError {
  let p = profile[:]
  if profile.length() < 128 {
    raise icc_parse_failure("profile is too short")
  }
  let size = read_be32_u(p, 0).to_uint64()
  if profile.length().to_uint64() != size {
    raise icc_parse_failure("profile size mismatch")
  }
  let color_space = profile[0x10:0x14].to_owned()
  let rendering_intent : RenderingIntent = match profile[0x43] {
    0 => Perceptual
    1 => Relative
    2 => Saturation
    3 => Absolute
    _ => raise icc_parse_failure("invalid rendering intent")
  }
  let header = { color_space, rendering_intent, }
  if size < 0x84 {
    return { header, tags: [], }
  }
  // Upstream computes these in `u32`; overflow wraps (release build semantics), and a
  // wrapped check that passes then makes the slice index panic, as reproduced here.
  let size = size.to_uint()
  let tag_count = read_be32_u(p, 0x80)
  if size < 0x84U + 12U * tag_count {
    raise icc_parse_failure("unexpected end of profile while reading tag list")
  }
  // `&profile[0x84..][..12 * tag_count as usize]` (no wrap in usize)
  if 12UL * tag_count.to_uint64() > (profile.length() - 0x84).to_uint64() {
    abort("range end index out of range for slice")
  }
  let tags = []
  for i in 0..<tag_count.reinterpret_as_int() {
    let base = 0x84 + 12 * i
    let tag = profile[base:base + 4].to_owned()
    let offset = read_be32_u(p, base + 4)
    let tag_size = read_be32_u(p, base + 8)
    let tag_end = offset + tag_size
    if size < tag_end {
      raise icc_parse_failure(
        "unexpected end of profile while reading tag data",
      )
    }
    // `&profile[offset as usize..tag_end as usize]`
    if offset > tag_end {
      abort("slice index starts at \{offset} but ends at \{tag_end}")
    }
    tags.push({
      tag,
      data: profile[offset.reinterpret_as_int():tag_end.reinterpret_as_int()],
    })
  }
  { header, tags, }
}

///|
fn parse_trc_tag(data : BytesView) -> KnownIccTrc? raise @bitstream.JxlError {
  let len = data.length()
  if data[0:4] == b"para" {
    if len < 12 {
      return None
    }
    let curve_type = (data[8].to_int() << 8) | data[9].to_int()
    let parameters = (len - 12) / 4
    match curve_type {
      0 => {
        if parameters != 1 {
          raise icc_parse_failure("invalid parametricCurveType")
        }
        let gamma = read_be32_i(data, 12)
        KnownIccTrc::from_gamma(gamma)
      }
      3 => {
        if parameters != 5 {
          raise icc_parse_failure("invalid parametricCurveType")
        }
        let params = FixedArray::makei(5, idx => read_be32_i(data, 12 + 4 * idx))
        let bt709 : FixedArray[Int32] = [
          (65536 * 20 + 4) / 9,
          (65536 * 1000 + 549) / 1099,
          (65536 * 99 + 549) / 1099,
          (65536 * 10 + 22) / 45,
          (65536 * 81 + 500) / 1000,
        ]
        let srgb : FixedArray[Int32] = [
          (65536 * 24 + 5) / 10,
          (65536 * 1000 + 527) / 1055,
          (65536 * 55 + 527) / 1055,
          (65536 * 100 + 646) / 1292,
          (65536 * 4045 + 50000) / 100000,
        ]
        if params == bt709 {
          Some(Bt709)
        } else if params == srgb {
          Some(Srgb)
        } else if params[1] == 65536 &&
          params[2] == 0 &&
          params[3] == 65536 &&
          params[4] == 0 {
          KnownIccTrc::from_gamma(params[0])
        } else {
          None
        }
      }
      _ => None
    }
  } else if len == 12 && data == b"curv\x00\x00\x00\x00\x00\x00\x00\x00" {
    Some(Linear)
  } else if len == 14 && data[0:12] == b"curv\x00\x00\x00\x00\x00\x00\x00\x01" {
    Some(
      ParametricGamma((data[12].to_uint() << 16) | (data[13].to_uint() << 8)),
    )
  } else {
    None
  }
}

///|
fn read_xyz_tag(data : BytesView) -> FixedArray[Int32] {
  [read_be32_i(data, 8), read_be32_i(data, 12), read_be32_i(data, 16)]
}

///|
fn is_unsupported_tag(tag : Bytes) -> Bool {
  let t0 = tag[0]
  let t1 = tag[1]
  let t2 = tag[2]
  let t3 = tag[3]
  if (t0 == b'A' || t0 == b'D') &&
    t1 == b'2' &&
    t2 == b'B' &&
    t3 >= b'0' &&
    t3 <= b'3' {
    return true
  }
  if t0 == b'B' &&
    t1 == b'2' &&
    (t2 == b'A' || t2 == b'D') &&
    t3 >= b'0' &&
    t3 <= b'3' {
    return true
  }
  if t0 == b'p' && t1 == b'r' && t2 == b'e' && t3 >= b'0' && t3 <= b'2' {
    return true
  }
  tag == b"chrm" ||
  tag == b"clro" ||
  tag == b"clrt" ||
  tag == b"clot" ||
  tag == b"ciis" ||
  tag == b"lumi" ||
  tag == b"meas" ||
  tag == b"ncl2" ||
  tag == b"resp" ||
  tag == b"view"
}

///|
fn detect_profile_info(
  profile : Bytes,
) -> IccProfileInfo raise @bitstream.JxlError {
  let profile = parse_icc_raw(profile)
  let color_space = profile.header.color_space
  let rendering_intent = profile.header.rendering_intent
  let mut wtpt : FixedArray[Int32] = [0xf6d6, 0x10000, 0xd32d] // D50
  let mut chad : FixedArray[Int32]? = None
  let trcs : FixedArray[KnownIccTrc?] = [None, None, None, None]
  let xyzs : FixedArray[FixedArray[Int32]?] = [None, None, None]
  let mut cicp : Bytes? = None
  for raw_tag in profile.tags {
    let data = raw_tag.data
    let tag = raw_tag.tag
    if data.length() < 4 {
      continue
    }
    if tag[1:4] == b"TRC" {
      let index = match tag[0] {
        b'r' => 0
        b'g' => 1
        b'b' => 2
        b'k' => 3
        _ => continue
      }
      match parse_trc_tag(data) {
        Some(tf) => trcs[index] = Some(tf)
        None => continue
      }
    } else if tag[1:4] == b"XYZ" && tag[0] is (b'r' | b'g' | b'b') {
      let index = match tag[0] {
        b'r' => 0
        b'g' => 1
        _ => 2
      }
      if data[0:4] != b"XYZ " || data.length() < 20 {
        raise icc_parse_failure("invalid colorant tag")
      }
      let xyz = read_xyz_tag(data)
      validate_xyz(xyz)
      xyzs[index] = Some(xyz)
    } else if tag == b"chad" {
      if data[0:4] != b"sf32" || data.length() < 44 {
        raise icc_parse_failure("invalid chad tag")
      }
      let mat = FixedArray::makei(9, idx => read_be32_i(data, 8 + 4 * idx))
      validate_chad(mat)
      chad = Some(mat)
    } else if tag == b"wtpt" {
      if data[0:4] != b"XYZ " || data.length() < 20 {
        raise icc_parse_failure("invalid wtpt tag")
      }
      wtpt = read_xyz_tag(data)
      validate_xyz(wtpt)
    } else if is_unsupported_tag(tag) {
      raise @bitstream.Color("UnsupportedIccProfile")
    } else if tag == b"cicp" {
      // Note: upstream takes the first 4 bytes of the tag data (the `cicp` type signature).
      cicp = Some(data[0:4].to_owned())
    }
  }
  let override_trc : KnownIccTrc? = match cicp {
    Some(c) if c[1] == 16 => Some(Pq)
    Some(c) if c[1] == 18 => Some(Hlg)
    _ => None
  }
  let trc_rgb = match (trcs[0], trcs[1], trcs[2]) {
    (Some(r), Some(g), Some(b)) =>
      match override_trc {
        Some(trc) => Some(FixedArray::make(3, trc))
        None => Some([r, g, b])
      }
    _ => None
  }
  let trc_k = trcs[3].map(k => override_trc.unwrap_or(k))
  let xyz_rgb : FixedArray[FixedArray[Int32]]? = match
    (xyzs[0], xyzs[1], xyzs[2]) {
    (Some(r), Some(g), Some(b)) => Some([r, g, b])
    _ => None
  }
  {
    color_space,
    rendering_intent,
    chad: chad.unwrap_or([65536, 0, 0, 0, 65536, 0, 0, 0, 65536]),
    wtpt,
    trc_k,
    trc_rgb,
    xyz_rgb,
  }
}

///|
fn validate_xyz(
  xyz_s15fixed16 : FixedArray[Int32],
) -> Unit raise @bitstream.JxlError {
  let flt = xyz_s15fixed16.map(v => Float::from_int(v) / (65536.0 : Float))
  let sum = flt[0] + flt[1] + flt[2]
  for v in flt {
    if !(v / sum).is_finite() {
      raise icc_parse_failure("invalid XYZType")
    }
  }
}

///|
fn validate_chad(
  chad_s15fixed16 : FixedArray[Int32],
) -> Unit raise @bitstream.JxlError {
  let mat_float = chad_s15fixed16.map(v => {
    Float::from_int(v) / (65536.0 : Float)
  })
  let chad_inv = matinv(mat_float)
  for v in chad_inv {
    if !v.is_finite() {
      raise icc_parse_failure("invalid chad tag")
    }
  }
}

///|
fn parse_icc(profile : Bytes) -> EnumColourEncoding raise @bitstream.JxlError {
  let info = detect_profile_info(profile)
  let rendering_intent = info.rendering_intent()
  if info.is_cmyk() {
    raise @bitstream.Color("UnsupportedIccProfile")
  } else if info.is_grayscale() {
    guard info.trc_gray() is Some(tf) else {
      raise @bitstream.Color("UnsupportedIccProfile")
    }
    let wp = info.white_point()
    {
      colour_space: Grey,
      white_point: wp,
      primaries: Srgb,
      tf,
      rendering_intent,
    }
  } else if info.is_rgb() {
    guard (info.trc_color(), info.primaries()) is (Some(tf), Some(primaries)) else {
      raise @bitstream.Color("UnsupportedIccProfile")
    }
    let wp = info.white_point()
    { colour_space: Rgb, white_point: wp, primaries, tf, rendering_intent, }
  } else {
    raise @bitstream.Color("UnsupportedIccProfile")
  }
}

///|
pub fn icc_tf(profile : Bytes) -> TransferFunction? {
  let enc = parse_icc(profile) catch { _ => return None }
  Some(enc.tf)
}
