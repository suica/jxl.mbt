// Port of jxl-color/src/icc/synthesize.rs.

///|
fn append_tag_with_data(
  tags_out : Array[IccTag],
  data_out : Array[Byte],
  tag : Bytes,
  data : ArrayView[Byte],
) -> Unit {
  append_multiple_tags_with_data(tags_out, data_out, [tag], data)
}

///|
fn append_multiple_tags_with_data(
  tags_out : Array[IccTag],
  data_out : Array[Byte],
  tags : Array[Bytes],
  data : ArrayView[Byte],
) -> Unit {
  let data_offset = data_out.length()
  let len = data.length()
  for tag in tags {
    tags_out.push({ tag, data_offset, len, })
  }
  data_out.push_iter(data.iter())
  // Align to 4 bytes
  let aligned = (data_out.length() + 3) & -4
  while data_out.length() < aligned {
    data_out.push(0)
  }
}

///|
fn push_be32(out : Array[Byte], v : Int32) -> Unit {
  out.push((v >> 24).to_byte())
  out.push((v >> 16).to_byte())
  out.push((v >> 8).to_byte())
  out.push(v.to_byte())
}

///|
fn push_be16(out : Array[Byte], v : Int32) -> Unit {
  out.push((v >> 8).to_byte())
  out.push(v.to_byte())
}

///|
fn create_mluc(locale : Bytes, strings : Array[String]) -> Array[Byte] {
  let out : Array[Byte] = [b'm', b'l', b'u', b'c', 0, 0, 0, 0]
  let data : Array[Int32] = []
  push_be32(out, strings.length())
  out.push_iter([b'\x00', b'\x00', b'\x00', b'\x0c'].iter())
  for s in strings {
    let offset = data.length()
    // UTF-16 code units
    for i in 0..<s.length() {
      data.push(s.code_unit_at(i).to_int())
    }
    out.push_iter(locale.iter())
    push_be32(out, (data.length() - offset) * 2)
    push_be32(out, 0x10 + strings.length() * 12 + offset * 2)
  }
  for c in data {
    push_be16(out, c)
  }
  out
}

///|
fn create_xyz(xyz : FixedArray[Int32]) -> Array[Byte] {
  let out : Array[Byte] = [b'X', b'Y', b'Z', b' ', 0, 0, 0, 0]
  push_be32(out, xyz[0])
  push_be32(out, xyz[1])
  push_be32(out, xyz[2])
  out
}

///|
fn create_curv_lut(lut : Array[Int32]) -> Array[Byte] {
  let len = lut.length()
  guard len >= 2 else { abort("assertion failed: len >= 2") }
  let trc : Array[Byte] = [b'c', b'u', b'r', b'v', 0, 0, 0, 0]
  push_be32(trc, len)
  for v in lut {
    push_be16(trc, v)
  }
  trc
}

///|
fn create_para(ty : Int32, params : Array[Int32]) -> Array[Byte] {
  let out : Array[Byte] = [b'p', b'a', b'r', b'a', 0, 0, 0, 0]
  push_be16(out, ty)
  out.push(0)
  out.push(0)
  for p in params {
    push_be32(out, p)
  }
  out
}

///|
/// Rust `{:?}` formatting of `Customxy`.
fn customxy_debug(xy : Customxy) -> String {
  "Customxy { x: \{xy.x}, y: \{xy.y} }"
}

///|
/// Rust `{:?}` formatting of the colour encoding enums, used in the `desc` tag.
fn colour_space_debug(v : ColourSpace) -> String {
  match v {
    Rgb => "Rgb"
    Grey => "Grey"
    Xyb => "Xyb"
    Unknown => "Unknown"
  }
}

///|
fn rendering_intent_debug(v : RenderingIntent) -> String {
  match v {
    Perceptual => "Perceptual"
    Relative => "Relative"
    Saturation => "Saturation"
    Absolute => "Absolute"
  }
}

///|
fn white_point_debug(v : WhitePoint) -> String {
  match v {
    D65 => "D65"
    Custom(xy) => "Custom(\{customxy_debug(xy)})"
    E => "E"
    Dci => "Dci"
  }
}

///|
fn primaries_debug(v : Primaries) -> String {
  match v {
    Srgb => "Srgb"
    Custom(red~, green~, blue~) =>
      "Custom { red: \{customxy_debug(red)}, green: \{customxy_debug(green)}, blue: \{customxy_debug(blue)} }"
    Bt2100 => "Bt2100"
    P3 => "P3"
  }
}

///|
fn transfer_function_debug(v : TransferFunction) -> String {
  match v {
    Gamma(g~, inverted~) => "Gamma { g: \{g}, inverted: \{inverted} }"
    Bt709 => "Bt709"
    Unknown => "Unknown"
    Linear => "Linear"
    Srgb => "Srgb"
    Pq => "Pq"
    Dci => "Dci"
    Hlg => "Hlg"
  }
}

///|
/// Rust `(f * 65536.0 + 0.5) as i32`.
fn quantize_s15fixed16(f : Float) -> Int32 {
  (f * 65536.0 + 0.5).to_int()
}

///|
/// Creates an ICCv4 profile from the given `EnumColourEncoding`.
pub fn colour_encoding_to_icc(colour_encoding : EnumColourEncoding) -> Bytes {
  let { colour_space, white_point, primaries, tf, rendering_intent, } = colour_encoding
  if colour_space == Xyb {
    abort("ICC profile for XYB color space is not supported yet")
  }
  let header : Array[Byte] = [
    0, 0, 0, 0, // profile size
     b'j', b'x', b'l', b' ', 4, 0x40, 0, 0, b'm', b'n', b't', b'r',
    // 0x10
     0, 0, 0, 0, // device space
     b'X', b'Y', b'Z', b' ', 7, 0xe7, 0, 4, 0, 22, 0, 0, 0, 0, 0, 0, // datetime
     b'a', b'c', b's', b'p', b'A', b'P', b'P', b'L', 0, 0, 0, 0,
    // 0x30
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 0x40
     0, 0, 0, 0, // rendering intent
     0, 0, 0xf6, 0xd6, 0, 1, 0, 0, 0, 0, 0xd3, 0x2d, // D50 (X=.9642, Y=1., Z=.8249)
    // 0x50
     b'j', b'x', b'l', b' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // MD5
  ]
  while header.length() < 128 {
    header.push(0)
  }
  let cs_sig = match colour_space {
    Rgb => b"RGB "
    Grey => b"GRAY"
    Xyb => b"3CLR"
    Unknown => b"3CLR"
  }
  for i in 0..<4 {
    header[16 + i] = cs_sig[i]
  }
  header[0x43] = rendering_intent.to_raw().to_byte()
  let tags : Array[IccTag] = []
  let data : Array[Byte] = []
  let desc = "\{colour_space_debug(colour_space)}_\{rendering_intent_debug(rendering_intent)}_\{white_point_debug(white_point)}_\{primaries_debug(primaries)}_\{transfer_function_debug(tf)}"
  append_tag_with_data(tags, data, b"desc", create_mluc(b"enUS", [desc]))
  append_tag_with_data(
    tags,
    data,
    b"cprt",
    create_mluc(b"enUS", ["CC0, generated by jxl-oxide"]),
  )
  let mut chad : FixedArray[Float] = [
    1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,
  ]
  let from_illuminant : FixedArray[Float] = match white_point {
    D65 => illuminant_d65
    Custom(xy) => [Float::from_int(xy.x) / 1.0e6, Float::from_int(xy.y) / 1.0e6]
    E => illuminant_e
    Dci => illuminant_dci
  }
  if colour_space == Rgb {
    append_tag_with_data(
      tags,
      data,
      b"wtpt",
      create_xyz([0xf6d6, 0x10000, 0xd32d]),
    )
    chad = adapt_mat(from_illuminant, illuminant_d50)
    let chad_data : Array[Byte] = [b's', b'f', b'3', b'2', 0, 0, 0, 0]
    for f in chad {
      push_be32(chad_data, quantize_s15fixed16(f))
    }
    append_tag_with_data(tags, data, b"chad", chad_data)
  } else {
    let xyz = illuminant_to_xyz(from_illuminant)
    append_tag_with_data(
      tags,
      data,
      b"wtpt",
      create_xyz(xyz.map(quantize_s15fixed16)),
    )
  }
  let trc = match tf {
    Gamma(g~, inverted=false) => {
      let g = g.reinterpret_as_uint().to_uint64()
      let gamma = ((g * 65536 + 5000000) / 10000000)
        .to_uint()
        .reinterpret_as_int()
      create_para(0, [gamma])
    }
    Gamma(g~, inverted=true) => {
      let g = g.reinterpret_as_uint().to_uint64()
      let adj = g / 2
      let gamma = ((65536UL * 10000000UL + adj) / g)
        .to_uint()
        .reinterpret_as_int()
      create_para(0, [gamma])
    }
    Bt709 =>
      create_para(3, [
        (65536 * 20 + 4) / 9,
        (65536 * 1000 + 549) / 1099,
        (65536 * 99 + 549) / 1099,
        (65536 * 10 + 22) / 45,
        (65536 * 81 + 500) / 1000,
      ])
    Unknown => abort("explicit panic")
    Linear => [b'c', b'u', b'r', b'v', 0, 0, 0, 0, 0, 0, 0, 0]
    Srgb =>
      create_para(3, [
        (65536 * 24 + 5) / 10,
        (65536 * 1000 + 527) / 1055,
        (65536 * 55 + 527) / 1055,
        (65536 * 100 + 646) / 1292,
        (65536 * 4045 + 50000) / 100000,
      ])
    Pq => create_curv_lut(pq_table(4096))
    Dci => create_para(0, [(65536 * 26 + 5) / 10])
    Hlg => create_curv_lut(hlg_table(4096))
  }
  let primaries : FixedArray[FixedArray[Float]] = match primaries {
    Srgb => primaries_srgb
    Custom(red~, green~, blue~) =>
      [
        [Float::from_int(red.x) / 1.0e6, Float::from_int(red.y) / 1.0e6],
        [Float::from_int(green.x) / 1.0e6, Float::from_int(green.y) / 1.0e6],
        [Float::from_int(blue.x) / 1.0e6, Float::from_int(blue.y) / 1.0e6],
      ]
    Bt2100 => primaries_bt2100
    P3 => primaries_p3
  }
  if tf is (Pq | Hlg) {
    match colour_encoding.cicp() {
      Some(cicp) => {
        let cicp_tag : Array[Byte] = [b'c', b'i', b'c', b'p', 0, 0, 0, 0]
        for v in cicp {
          cicp_tag.push(v.to_byte())
        }
        append_tag_with_data(tags, data, b"cicp", cicp_tag)
      }
      None => ()
    }
  }
  match colour_space {
    Rgb => {
      append_multiple_tags_with_data(
        tags,
        data,
        [b"rTRC", b"gTRC", b"bTRC"],
        trc,
      )
      let p_xyz = primaries_to_xyz_mat(primaries, from_illuminant)
      let p_pcs = matmul3(chad, p_xyz)
      let p_pcs_q = p_pcs.map(quantize_s15fixed16)
      append_tag_with_data(
        tags,
        data,
        b"rXYZ",
        create_xyz([p_pcs_q[0], p_pcs_q[3], p_pcs_q[6]]),
      )
      append_tag_with_data(
        tags,
        data,
        b"gXYZ",
        create_xyz([p_pcs_q[1], p_pcs_q[4], p_pcs_q[7]]),
      )
      append_tag_with_data(
        tags,
        data,
        b"bXYZ",
        create_xyz([p_pcs_q[2], p_pcs_q[5], p_pcs_q[8]]),
      )
    }
    Grey => append_tag_with_data(tags, data, b"kTRC", trc)
    Xyb => abort("not yet implemented")
    Unknown => abort("Unknown color space, ICC profile not embedded?")
  }
  let data_offset = 128 + 4 + tags.length() * 12
  let out = header
  push_be32(out, tags.length())
  for tag in tags {
    out.push_iter(tag.tag.iter())
    push_be32(out, tag.data_offset + data_offset)
    push_be32(out, tag.len)
  }
  out.push_iter(data.iter())
  let total_len = out.length()
  out[0] = (total_len >> 24).to_byte()
  out[1] = (total_len >> 16).to_byte()
  out[2] = (total_len >> 8).to_byte()
  out[3] = total_len.to_byte()
  Bytes::from_array(out)
}
