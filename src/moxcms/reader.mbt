// Port of moxcms 0.9.0 `reader.rs` and `helpers.rs` (`read_matrix_3d`,
// `read_vector_3d`).
//
// Offsets are `usize` upstream; they are kept in `Int64` here so that sums of
// two u32 values cannot overflow, as on the 64-bit upstream target.

///|
fn be_u32(b : Bytes, off : Int32) -> UInt32 {
  (b[off].to_uint() << 24) |
  (b[off + 1].to_uint() << 16) |
  (b[off + 2].to_uint() << 8) |
  b[off + 3].to_uint()
}

///|
fn be_i32(b : Bytes, off : Int32) -> Int32 {
  be_u32(b, off).reinterpret_as_int()
}

///|
fn be_u16(b : Bytes, off : Int32) -> Int32 {
  (b[off].to_int() << 8) | b[off + 1].to_int()
}

///|
fn s15_fixed16_number_to_float(a : Int32) -> Float {
  Float::from_int(a) / 65536.0
}

///|
fn s15_fixed16_number_to_double(a : Int32) -> Double {
  a.to_double() / 65536.0
}

///|
fn uint16_number_to_float(a : UInt32) -> Float {
  Float::from_uint(a) / 65535.0
}

///|
fn uint16_number_to_float_fast(a : Int32) -> Float {
  Float::from_int(a) * ((1.0 : Float) / (65535.0 : Float))
}

///|
fn uint8_number_to_float_fast(a : Int32) -> Float {
  Float::from_int(a) * ((1.0 : Float) / (255.0 : Float))
}

///|
fn len64(b : Bytes) -> Int64 {
  b.length().to_int64()
}

///|
/// `String::from_utf16_lossy` of big-endian UTF-16 code units in
/// `b[start..start + len]` (a trailing odd byte is dropped, as `as_chunks`).
fn utf16be_lossy(b : Bytes, start : Int32, len : Int32) -> String {
  let units = len / 2
  let sb = StringBuilder()
  let mut i = 0
  while i < units {
    let u = be_u16(b, start + i * 2)
    if u >= 0xD800 && u <= 0xDBFF && i + 1 < units {
      let u2 = be_u16(b, start + (i + 1) * 2)
      if u2 >= 0xDC00 && u2 <= 0xDFFF {
        let cp = 0x10000 + ((u - 0xD800) << 10) + (u2 - 0xDC00)
        sb.write_char(Int32::unsafe_to_char(cp))
        i += 2
        continue
      }
    }
    if u >= 0xD800 && u <= 0xDFFF {
      sb.write_char('\u{FFFD}')
    } else {
      sb.write_char(Int32::unsafe_to_char(u))
    }
    i += 1
  }
  sb.to_string()
}

///|
/// `String::from_utf8_lossy` of `b[start..start + len]`.
fn utf8_lossy(b : Bytes, start : Int32, len : Int32) -> String {
  let sb = StringBuilder()
  let end = start + len
  let mut i = start
  while i < end {
    let c = b[i].to_int()
    if c < 0x80 {
      sb.write_char(Int32::unsafe_to_char(c))
      i += 1
      continue
    }
    let (need, min, init) = if c >= 0xC2 && c <= 0xDF {
      (1, 0x80, c & 0x1F)
    } else if c >= 0xE0 && c <= 0xEF {
      (2, 0x800, c & 0x0F)
    } else if c >= 0xF0 && c <= 0xF4 {
      (3, 0x10000, c & 0x07)
    } else {
      (0, 0, 0)
    }
    if need == 0 {
      sb.write_char('\u{FFFD}')
      i += 1
      continue
    }
    let mut cp = init
    let mut j = 1
    let mut ok = true
    while j <= need {
      if i + j >= end {
        ok = false
        break
      }
      let cc = b[i + j].to_int()
      if (cc & 0xC0) != 0x80 {
        ok = false
        break
      }
      cp = (cp << 6) | (cc & 0x3F)
      j += 1
    }
    if ok && cp >= min && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF) {
      sb.write_char(Int32::unsafe_to_char(cp))
      i += need + 1
    } else {
      sb.write_char('\u{FFFD}')
      i += if j > 1 { j } else { 1 }
    }
  }
  sb.to_string()
}

///|
fn trim_end_nul(s : String) -> String {
  let mut end = s.length()
  while end > 0 && s[end - 1] == 0 {
    end -= 1
  }
  s.clamped_view(start=0, end~).to_owned()
}

///|
fn read_matrix_3d(
  arr : Bytes,
  start : Int32,
  len : Int32,
) -> Matrix3d raise CmsError {
  if len < 36 {
    raise InvalidProfile
  }
  let m = Matrix3d::zero()
  for i in 0..<3 {
    for j in 0..<3 {
      m.v[i][j] = s15_fixed16_number_to_double(
        be_i32(arr, start + (i * 3 + j) * 4),
      )
    }
  }
  m
}

///|
fn read_vector_3d(
  arr : Bytes,
  start : Int32,
  len : Int32,
) -> Vector3d raise CmsError {
  if len < 12 {
    raise InvalidProfile
  }
  {
    v: [
      s15_fixed16_number_to_double(be_i32(arr, start)),
      s15_fixed16_number_to_double(be_i32(arr, start + 4)),
      s15_fixed16_number_to_double(be_i32(arr, start + 8)),
    ],
  }
}

///|
fn read_desc_unicode(
  tag : Bytes,
  tag_start : Int32,
  tag_len : Int32,
  unicode_offset : Int32,
) -> (UInt32, String)? {
  if tag_len.to_int64() < unicode_offset.to_int64() + 8 {
    return None
  }
  let h = tag_start + unicode_offset
  let language_code = be_u32(tag, h)
  let unicode_length = be_u32(tag, h + 4).to_uint64().reinterpret_as_int64()
  if unicode_length == 0 {
    return Some((language_code, ""))
  }
  let byte_length = unicode_length * 2
  let str_start = unicode_offset.to_int64() + 8
  if tag_len.to_int64() < str_start + byte_length {
    return None
  }
  let s = utf16be_lossy(
    tag,
    tag_start + str_start.to_int(),
    byte_length.to_int(),
  )
  Some((language_code, trim_end_nul(s)))
}

///|
fn read_viewing_conditions(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> ViewingConditions? raise CmsError {
  if tag_size < 36 {
    return None
  }
  if len64(slice) < entry + 36 {
    raise InvalidProfile
  }
  let e = entry.to_int()
  let tag_type = TagTypeDefinition::from(be_u32(slice, e))
  if tag_type != DefViewingConditions {
    return None
  }
  let illuminant = Xyz::{
    x: s15_fixed16_number_to_float(be_i32(slice, e + 8)),
    y: s15_fixed16_number_to_float(be_i32(slice, e + 12)),
    z: s15_fixed16_number_to_float(be_i32(slice, e + 16)),
  }
  let surround = Xyz::{
    x: s15_fixed16_number_to_float(be_i32(slice, e + 20)),
    y: s15_fixed16_number_to_float(be_i32(slice, e + 24)),
    z: s15_fixed16_number_to_float(be_i32(slice, e + 28)),
  }
  let observer = StandardObserver::from(be_u32(slice, e + 32))
  Some({ illuminant, surround, observer, })
}

///|
fn read_string_tag(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> ProfileText? raise CmsError {
  let tag_size = if tag_size == 0 { TAG_SIZE.to_int64() } else { tag_size }
  if tag_size < 4 {
    return None
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let ts = entry.to_int()
  let tlen = tag_size.to_int()
  if tlen < 8 {
    return None
  }
  let tag_type = TagTypeDefinition::from(be_u32(slice, ts))
  if tag_type == Text {
    let s = trim_end_nul(utf8_lossy(slice, ts + 8, tlen - 8))
    return Some(PlainString(s))
  } else if tag_type == MultiLocalizedUnicode {
    if tlen < 28 {
      raise InvalidProfile
    }
    let records_count = be_u32(slice, ts + 8).to_uint64()
    let primary_language_code = utf8_lossy(slice, ts + 16, 2)
    let primary_country_code = utf8_lossy(slice, ts + 18, 2)
    let first_string_record_length = be_u32(slice, ts + 20)
      .to_uint64()
      .reinterpret_as_int64()
    let first_record_offset = be_u32(slice, ts + 24)
      .to_uint64()
      .reinterpret_as_int64()
    if tlen.to_int64() < first_record_offset + first_string_record_length {
      return None
    }
    let string_record = utf16be_lossy(
      slice,
      ts + first_record_offset.to_int(),
      first_string_record_length.to_int(),
    )
    let records = [
      LocalizableString::{
        language: primary_language_code,
        country: primary_country_code,
        value: string_record,
      },
    ]
    let mut record = 1UL
    while record < records_count {
      let localizable_header_offset = if record == 1UL {
        28L
      } else {
        28L + 12L * (record - 1UL).reinterpret_as_int64()
      }
      if tlen.to_int64() < localizable_header_offset + 12 {
        raise InvalidProfile
      }
      let c = ts + localizable_header_offset.to_int()
      let language_code = utf8_lossy(slice, c, 2)
      let country_code = utf8_lossy(slice, c + 2, 2)
      let record_length = be_u32(slice, c + 4)
        .to_uint64()
        .reinterpret_as_int64()
      let string_offset = be_u32(slice, c + 8)
        .to_uint64()
        .reinterpret_as_int64()
      if tlen.to_int64() < string_offset + record_length {
        return None
      }
      let value = utf16be_lossy(
        slice,
        ts + string_offset.to_int(),
        record_length.to_int(),
      )
      records.push({ country: country_code, language: language_code, value, })
      record += 1UL
    }
    return Some(Localizable(records))
  } else if tag_type == Description {
    if tlen < 12 {
      raise InvalidProfile
    }
    let ascii_length = be_u32(slice, ts + 8).to_uint64().reinterpret_as_int64()
    let ascii_end = 12L + ascii_length
    if tlen.to_int64() < ascii_end {
      raise InvalidProfile
    }
    let ascii_string = trim_end_nul(
      utf8_lossy(slice, ts + 12, ascii_length.to_int()),
    )
    let (unicode_code, unicode_string) = match
      read_desc_unicode(slice, ts, tlen, ascii_end.to_int()) {
      Some(v) => v
      None => (0U, "")
    }
    return Some(
      Description({
        ascii_string,
        unicode_language_code: unicode_code,
        unicode_string,
        mac_string: "",
        script_code_code: -1,
      }),
    )
  }
  None
}

///|
fn read_lut_table_f32(
  table : Bytes,
  start : Int32,
  len : Int32,
  lut_type : LutType,
) -> LutStore {
  if lut_type == Lut16 {
    let n = len / 2
    let out = FixedArray::make(n, 0)
    for i in 0..<n {
      out[i] = be_u16(table, start + i * 2)
    }
    Store16(out)
  } else if lut_type == Lut8 {
    let out = FixedArray::make(len, 0)
    for i in 0..<len {
      out[i] = table[start + i].to_int()
    }
    Store8(out)
  } else {
    abort(
      "This should never happen, report to https://github.com/awxkee/moxcms",
    )
  }
}

///|
fn read_nested_tone_curves(
  slice : Bytes,
  tag_start : Int32,
  tag_len : Int32,
  offset : Int32,
  length : Int32,
  options : ParsingOptions,
) -> Array[ToneReprCurve] raise CmsError {
  let mut curve_offset = offset.to_int64()
  let curves = []
  for _ in 0..<length {
    if tag_len.to_int64() < curve_offset + 12 {
      raise InvalidProfile
    }
    let read_size = Ref(0)
    let new_curve = read_trc_tag(
      slice, tag_start, tag_len, curve_offset, 0L, read_size, options,
    )
    match new_curve {
      None => raise InvalidProfile
      Some(curve) => curves.push(curve)
    }
    curve_offset += read_size.val.to_int64()
    if curve_offset % 4 != 0 {
      curve_offset += 4L - curve_offset % 4
    }
  }
  curves
}

///|
fn read_lut_abm_type(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
  to_pcs : Bool,
  options : ParsingOptions,
) -> LutWarehouse? raise CmsError {
  if tag_size < 48 {
    return None
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let ts = entry.to_int()
  let tlen = tag_size.to_int()
  let tag_type_definition = TagTypeDefinition::from(be_u32(slice, ts))
  if tag_type_definition != MabLut && tag_type_definition != MbaLut {
    return None
  }
  let in_channels = slice[ts + 8].to_int()
  let out_channels = slice[ts + 9].to_int()
  if in_channels > 4 && out_channels > 4 {
    return None
  }
  let a_curve_offset = be_u32(slice, ts + 28).to_uint64().reinterpret_as_int64()
  let clut_offset = be_u32(slice, ts + 24).to_uint64().reinterpret_as_int64()
  let m_curve_offset = be_u32(slice, ts + 20).to_uint64().reinterpret_as_int64()
  let matrix_offset = be_u32(slice, ts + 16).to_uint64().reinterpret_as_int64()
  let b_curve_offset = be_u32(slice, ts + 12).to_uint64().reinterpret_as_int64()
  let (transform, bias) = if matrix_offset != 0 {
    let matrix_end = matrix_offset + 48
    if tlen.to_int64() < matrix_end {
      raise InvalidProfile
    }
    let m = ts + matrix_offset.to_int()
    let bias = read_vector_3d(slice, m + 36, 12)
    let transform = read_matrix_3d(slice, m, 48)
    (transform, bias)
  } else {
    (Matrix3d::identity(), Vector3d::{ v: [0.0, 0.0, 0.0], })
  }
  let grid_points = FixedArray::make(16, 0)
  let clut_table : LutStore? = if clut_offset != 0 {
    if clut_offset + 20 > tlen.to_int64() {
      raise InvalidProfile
    }
    let c = ts + clut_offset.to_int()
    for i in 0..<16 {
      grid_points[i] = slice[c + i].to_int()
    }
    let mut clut_size = 1U
    for i in 0..<in_channels.min(16) {
      clut_size = safe_mul_u32(clut_size, grid_points[i].reinterpret_as_uint())
    }
    clut_size = safe_mul_u32(clut_size, out_channels.reinterpret_as_uint())
    if clut_size == 0 {
      raise IncorrectlyFormedLut("Clut size was zero when it shouldn't")
    }
    if clut_size > 10_000_000 {
      raise IncorrectlyFormedLut(
        "Clut size exceeded 10_000_000 points what is too big",
      )
    }
    let mut grid_stride = 1L
    let mut last_index = 0L
    let mut k = in_channels.min(16) - 1
    while k >= 0 {
      let dim = grid_points[k].to_int64()
      if dim < 2 {
        raise IncorrectlyFormedLut("One of grid dimensions is less than 2")
      }
      // Products stay far below usize::MAX: at most 255^16 would overflow,
      // but clut_size (checked above) bounds the product of the dimensions.
      last_index = (dim - 1) * grid_stride + last_index
      grid_stride = grid_stride * dim
      k -= 1
    }
    last_index = last_index * out_channels.to_int64()
    if last_index >= clut_size.to_uint64().reinterpret_as_int64() {
      raise IncorrectlyFormedLut(
        "Clut size should be at least \{last_index}, but it was \{last_index}",
      )
    }
    let clut_offset20 = clut_offset + 20
    let entry_size = slice[c + 16].to_int()
    if entry_size != 1 && entry_size != 2 {
      raise InvalidProfile
    }
    let clut_end = clut_offset20 +
      safe_mul_u32(clut_size, entry_size.reinterpret_as_uint())
      .to_uint64()
      .reinterpret_as_int64()
    if tlen.to_int64() < clut_end {
      raise InvalidProfile
    }
    Some(
      read_lut_table_f32(
        slice,
        ts + clut_offset20.to_int(),
        (clut_end - clut_offset20).to_int(),
        if entry_size == 1 {
          Lut8
        } else {
          Lut16
        },
      ),
    )
  } else {
    None
  }
  let a_curves = if a_curve_offset == 0 {
    []
  } else {
    read_nested_tone_curves(
      slice,
      ts,
      tlen,
      a_curve_offset.to_int(),
      if to_pcs {
        in_channels
      } else {
        out_channels
      },
      options,
    )
  }
  let m_curves = if m_curve_offset == 0 {
    []
  } else {
    read_nested_tone_curves(
      slice,
      ts,
      tlen,
      m_curve_offset.to_int(),
      if to_pcs {
        out_channels
      } else {
        in_channels
      },
      options,
    )
  }
  let b_curves = if b_curve_offset == 0 {
    []
  } else {
    read_nested_tone_curves(
      slice,
      ts,
      tlen,
      b_curve_offset.to_int(),
      if to_pcs {
        out_channels
      } else {
        in_channels
      },
      options,
    )
  }
  Some(
    Multidimensional({
      num_input_channels: in_channels,
      num_output_channels: out_channels,
      matrix: transform,
      clut: clut_table,
      a_curves,
      b_curves,
      m_curves,
      grid_points,
      bias,
    }),
  )
}

///|
fn read_lut_a_to_b_type(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
  parsing_options : ParsingOptions,
) -> LutWarehouse? raise CmsError {
  if tag_size < 48 {
    return None
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let ts = entry.to_int()
  let tlen = tag_size.to_int()
  let lut_type = LutType::try_from(be_u32(slice, ts))
  guard lut_type == Lut8 || lut_type == Lut16 else {
    abort(
      "assertion failed: lut_type == LutType::Lut8 || lut_type == LutType::Lut16",
    )
  }
  if lut_type == Lut16 && tlen < 52 {
    raise InvalidProfile
  }
  let num_input_table_entries = if lut_type == Lut8 {
    256
  } else {
    be_u16(slice, ts + 48)
  }
  let num_output_table_entries = if lut_type == Lut8 {
    256
  } else {
    be_u16(slice, ts + 50)
  }
  if !(num_input_table_entries >= 2 && num_input_table_entries <= 4096) ||
    !(num_output_table_entries >= 2 && num_output_table_entries <= 4096) {
    raise InvalidProfile
  }
  let input_offset = if lut_type == Lut8 { 48 } else { 52 }
  let entry_size = if lut_type == Lut8 { 1 } else { 2 }
  let in_chan = slice[ts + 8].to_int()
  let out_chan = slice[ts + 9].to_int()
  let is_pcs = in_chan == 3 || out_chan == 3
  if !is_pcs ||
    !(in_chan >= 1 && in_chan <= 4) ||
    !(out_chan >= 1 && out_chan <= 4) {
    raise InvalidProfile
  }
  let grid_points = slice[ts + 10].to_int()
  if grid_points < 2 {
    raise InvalidProfile
  }
  let clut_size = safe_powi_u32(
      grid_points.reinterpret_as_uint(),
      in_chan.reinterpret_as_uint(),
    )
    .to_uint64()
    .reinterpret_as_int64()
  if !(clut_size >= 1 &&
    clut_size <= parsing_options.max_allowed_clut_size.to_int64()) {
    raise InvalidProfile
  }
  let transform = read_matrix_3d(slice, ts + 12, 36)
  // `u16::safe_mul`: at most 4096 * 4, never overflows.
  let lut_input_size = num_input_table_entries * in_chan
  let linearization_table_end = lut_input_size * entry_size + input_offset
  if tlen < linearization_table_end {
    raise InvalidProfile
  }
  let linearization_table = read_lut_table_f32(
    slice,
    ts + input_offset,
    linearization_table_end - input_offset,
    lut_type,
  )
  let clut_offset = linearization_table_end
  let clut_data_size = clut_size * out_chan.to_int64() * entry_size.to_int64()
  if tlen.to_int64() < clut_offset.to_int64() + clut_data_size {
    raise InvalidProfile
  }
  let clut_table = read_lut_table_f32(
    slice,
    ts + clut_offset,
    clut_data_size.to_int(),
    lut_type,
  )
  let output_offset = clut_offset + clut_data_size.to_int()
  let output_size = num_output_table_entries * out_chan
  let shaped_output = output_offset + output_size * entry_size
  if tlen < shaped_output {
    raise InvalidProfile
  }
  let gamma_table = read_lut_table_f32(
    slice,
    ts + output_offset,
    shaped_output - output_offset,
    lut_type,
  )
  Some(
    Lut({
      num_input_table_entries,
      num_output_table_entries,
      num_input_channels: in_chan,
      num_output_channels: out_chan,
      num_clut_grid_points: grid_points,
      matrix: transform,
      input_table: linearization_table,
      clut_table,
      output_table: gamma_table,
      lut_type,
    }),
  )
}

///|
fn read_lut_type(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> LutType raise CmsError {
  let tag_size = if tag_size == 0 { TAG_SIZE.to_int64() } else { tag_size }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  if tag_size < 48 {
    raise InvalidProfile
  }
  LutType::try_from(be_u32(slice, entry.to_int()))
}

///|
fn read_lut_tag(
  slice : Bytes,
  tag_entry : Int64,
  tag_size : Int64,
  parsing_options : ParsingOptions,
) -> LutWarehouse? raise CmsError {
  let lut_type = read_lut_type(slice, tag_entry, tag_size)
  if lut_type == Lut8 || lut_type == Lut16 {
    read_lut_a_to_b_type(slice, tag_entry, tag_size, parsing_options)
  } else if lut_type == LutMba || lut_type == LutMab {
    read_lut_abm_type(
      slice,
      tag_entry,
      tag_size,
      lut_type == LutMab,
      parsing_options,
    )
  } else {
    None
  }
}

///|
fn read_trc_tag_s(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
  options : ParsingOptions,
) -> ToneReprCurve? raise CmsError {
  let empty = Ref(0)
  read_trc_tag(slice, 0, slice.length(), entry, tag_size, empty, options)
}

///|
/// `read_trc_tag(slice, entry, tag_size, read_size, options)` where `slice`
/// is `bytes[base..base + base_len]`.
fn read_trc_tag(
  bytes : Bytes,
  base : Int32,
  base_len : Int32,
  entry : Int64,
  tag_size : Int64,
  read_size : Ref[Int32],
  options : ParsingOptions,
) -> ToneReprCurve? raise CmsError {
  let slice_len = base_len.to_int64()
  if slice_len < entry + 4 {
    return None
  }
  let curve_type = TagTypeDefinition::from(be_u32(bytes, base + entry.to_int()))
  if tag_size != 0 && tag_size < TAG_SIZE.to_int64() {
    return None
  }
  let last_tag_offset = if tag_size != 0 { tag_size + entry } else { slice_len }
  if last_tag_offset > slice_len {
    raise MalformedTrcCurve("Data exhausted")
  }
  let ts = base + entry.to_int()
  let tlen = (last_tag_offset - entry).to_int()
  if tlen < TAG_SIZE {
    raise MalformedTrcCurve("Data exhausted")
  }
  if curve_type == LutToneCurve {
    let entry_count = be_u32(bytes, ts + 8).to_uint64().reinterpret_as_int64()
    if entry_count == 0 {
      return Some(Lut(FixedArray::make(0, 0)))
    }
    if entry_count > options.max_allowed_trc_size.to_int64() {
      raise CurveLutIsTooLarge
    }
    let curve_end = entry_count * 2 + 12
    if tlen.to_int64() < curve_end {
      raise MalformedTrcCurve("Curve end ends to early")
    }
    let n = entry_count.to_int()
    let curve_values = FixedArray::make(n, 0)
    for i in 0..<n {
      curve_values[i] = be_u16(bytes, ts + 12 + i * 2)
    }
    read_size.val = curve_end.to_int()
    Some(Lut(curve_values))
  } else if curve_type == ParametricToneCurve {
    let entry_count = be_u16(bytes, ts + 8)
    if entry_count > 4 {
      raise MalformedTrcCurve("Parametric curve has unknown entries count")
    }
    let count_to_length : FixedArray[Int32] = [1, 3, 4, 5, 7]
    let n = count_to_length[entry_count]
    if tlen < 12 + n * 4 {
      raise MalformedTrcCurve(
        "Parametric curve has unknown entries count exhaust data too early",
      )
    }
    let params = FixedArray::make(n, (0.0 : Float))
    for i in 0..<n {
      params[i] = s15_fixed16_number_to_float(be_i32(bytes, ts + 12 + i * 4))
    }
    if entry_count == 1 || entry_count == 2 {
      let a = params[1]
      if a == 0.0 {
        raise ParametricCurveZeroDivision
      }
    }
    read_size.val = 12 + n * 4
    Some(Parametric(params))
  } else {
    raise MalformedTrcCurve("Unknown parametric curve tag")
  }
}

///|
fn read_chad_tag(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> Matrix3d? raise CmsError {
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  if len64(slice) - entry < 8 {
    raise InvalidProfile
  }
  if tag_size < 8 {
    return None
  }
  if (tag_size - 8) / 4 != 9 {
    return None
  }
  let e = entry.to_int()
  let c_type = TagTypeDefinition::from(be_u32(slice, e))
  if c_type != S15Fixed16Array {
    raise InvalidProfile
  }
  if slice.length() < 9 * 4 + 8 {
    raise InvalidProfile
  }
  let tlen = (last_tag_offset - (entry + 8)).to_int()
  // `size_of::<Matrix3f>()` is 36.
  if tlen != 36 {
    raise InvalidProfile
  }
  Some(read_matrix_3d(slice, e + 8, tlen))
}

///|
fn read_tech_tag(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> TechnologySignatures? raise CmsError {
  if tag_size < TAG_SIZE.to_int64() {
    raise InvalidProfile
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let e = entry.to_int()
  let def = TagTypeDefinition::from(be_u32(slice, e))
  if def == Signature {
    return Some({ signature: be_u32(slice, e + 8), })
  }
  None
}

///|
fn read_date_time_tag(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> ColorDateTime? raise CmsError {
  if tag_size < 20 {
    return None
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let e = entry.to_int()
  let def = TagTypeDefinition::from(be_u32(slice, e))
  if def == DateTime {
    // Upstream reads `slice[8..20]` (the profile header bytes, not the tag).
    return Some(ColorDateTime::new_from_slice(slice, 8, 12))
  }
  None
}

///|
fn read_meas_tag(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> Measurement? raise CmsError {
  if tag_size < TAG_SIZE.to_int64() {
    return None
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let e = entry.to_int()
  let def = TagTypeDefinition::from(be_u32(slice, e))
  if def != Measurement {
    return None
  }
  if 36L + entry > len64(slice) {
    raise InvalidProfile
  }
  let observer = StandardObserver::from(be_u32(slice, e + 8))
  let xyz = Xyz::{
    x: s15_fixed16_number_to_float(be_i32(slice, e + 12)),
    y: s15_fixed16_number_to_float(be_i32(slice, e + 16)),
    z: s15_fixed16_number_to_float(be_i32(slice, e + 20)),
  }
  let g = be_u32(slice, e + 24)
  let geometry : MeasurementGeometry = if g == 1 {
    D45to45
  } else if g == 2 {
    D0to0
  } else {
    Unknown
  }
  let flare = uint16_number_to_float(be_u32(slice, e + 28))
  let illuminant = StandardIlluminant::from(be_u32(slice, e + 32))
  Some({ flare, illuminant, geometry, observer, backing: xyz, })
}

///|
fn read_xyz_tag(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> Xyzd raise CmsError {
  if tag_size < TAG_SIZE.to_int64() {
    return Xyzd::default()
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let e = entry.to_int()
  let def = TagTypeDefinition::from(be_u32(slice, e))
  if def != Xyz {
    return Xyzd::default()
  }
  if tag_size < 20 {
    raise InvalidProfile
  }
  {
    x: s15_fixed16_number_to_double(be_i32(slice, e + 8)),
    y: s15_fixed16_number_to_double(be_i32(slice, e + 12)),
    z: s15_fixed16_number_to_double(be_i32(slice, e + 16)),
  }
}

///|
fn read_cicp_tag(
  slice : Bytes,
  entry : Int64,
  tag_size : Int64,
) -> CicpProfile? raise CmsError {
  if tag_size < TAG_SIZE.to_int64() {
    return None
  }
  let last_tag_offset = tag_size + entry
  if last_tag_offset > len64(slice) {
    raise InvalidProfile
  }
  let e = entry.to_int()
  let def = TagTypeDefinition::from(be_u32(slice, e))
  if def != Cicp {
    return None
  }
  let primaries = CicpColorPrimaries::try_from(slice[e + 8].to_int())
  let transfer_characteristics = TransferCharacteristics::try_from(
    slice[e + 9].to_int(),
  )
  let matrix_coefficients = MatrixCoefficients::try_from(slice[e + 10].to_int())
  let full_range = slice[e + 11].to_int() == 1
  Some({
    color_primaries: primaries,
    transfer_characteristics,
    matrix_coefficients,
    full_range,
  })
}
