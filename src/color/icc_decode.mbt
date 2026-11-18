// Port of jxl-color/src/icc/decode.rs (`decode_icc` part; `read_icc` lives in
// icc_read.mbt since it needs the entropy decoder).

///|
/// `std::io::Cursor` over a byte slice.
priv struct Cursor {
  data : BytesView
  mut pos : Int32
}

///|
fn Cursor::new(data : BytesView) -> Cursor {
  { data, pos: 0, }
}

///|
/// `read_exact` of one byte.
fn Cursor::read_byte(self : Cursor) -> Byte? {
  if self.pos >= self.data.length() {
    None
  } else {
    let b = self.data[self.pos]
    self.pos += 1
    Some(b)
  }
}

///|
fn varint(stream : Cursor) -> UInt64 raise @bitstream.JxlError {
  let mut value = 0UL
  let mut shift = 0
  while shift < 63 {
    guard stream.read_byte() is Some(b) else {
      raise invalid_icc_stream("stream is too short")
    }
    value = value | ((b & 0x7f).to_uint64() << shift)
    if (b & 0x80) == 0 {
      break
    }
    shift += 7
  }
  value
}

///|
fn predict_header(
  idx : Int32,
  output_size : UInt32,
  header : BytesView,
) -> Byte {
  match idx {
    0..<=3 => (output_size >> (8 * (3 - idx))).to_byte()
    8 => 4
    12..<=23 => b"mntrRGB XYZ "[idx - 12]
    36..<=39 => b"acsp"[idx - 36]
    // APPL
    41 | 42 if header[40] == b'A' => b'P'
    43 if header[40] == b'A' => b'L'
    // MSFT
    41 if header[40] == b'M' => b'S'
    42 if header[40] == b'M' => b'F'
    43 if header[40] == b'M' => b'T'
    // SGI_
    42 if header[40] == b'S' && header[41] == b'G' => b'I'
    43 if header[40] == b'S' && header[41] == b'G' => b' '
    // SUNW
    42 if header[40] == b'S' && header[41] == b'U' => b'N'
    43 if header[40] == b'S' && header[41] == b'U' => b'W'
    70 => 246
    71 => 214
    73 => 1
    78 => 211
    79 => 45
    80..<=83 => header[4 + idx - 80]
    _ => 0
  }
}

///|
fn shuffle2(bytes : BytesView) -> Array[Byte] {
  let len = bytes.length()
  let out = Array::new(capacity=len)
  let height = len / 2
  let odd = len % 2
  for idx in 0..<height {
    out.push(bytes[idx])
    out.push(bytes[idx + height + odd])
  }
  if odd != 0 {
    out.push(bytes[height])
  }
  out
}

///|
fn shuffle4(bytes : BytesView) -> Array[Byte] {
  let len = bytes.length()
  let out = Array::new(capacity=len)
  let step = len / 4
  let wide_count = len % 4
  for idx in 0..<step {
    let mut base = idx
    for _ in 0..<wide_count {
      out.push(bytes[base])
      base += step + 1
    }
    for _ in wide_count..<4 {
      out.push(bytes[base])
      base += step
    }
  }
  for idx in 1..<=wide_count {
    out.push(bytes[(step + 1) * idx - 1])
  }
  out
}

///|
fn push_be32_u(out : Array[Byte], v : UInt32) -> Unit {
  out.push((v >> 24).to_byte())
  out.push((v >> 16).to_byte())
  out.push((v >> 8).to_byte())
  out.push(v.to_byte())
}

///|
let common_tags : FixedArray[Bytes] = [
  b"rTRC", b"rXYZ", b"cprt", b"wtpt", b"bkpt", b"rXYZ", b"gXYZ", b"bXYZ", b"kXYZ",
  b"rTRC", b"gTRC", b"bTRC", b"kTRC", b"chad", b"desc", b"chrm", b"dmnd", b"dmdd",
  b"lumi",
]

///|
let common_data : FixedArray[Bytes] = [
  b"XYZ ", b"desc", b"text", b"mluc", b"para", b"curv", b"sf32", b"gbd ",
]

///|
/// Decodes the given ICC profile stream.
pub fn decode_icc(stream : Bytes) -> Bytes raise @bitstream.JxlError {
  let tmp_cursor = Cursor::new(stream[:])
  let output_size = varint(tmp_cursor)
  let commands_size = varint(tmp_cursor)
  let stream_offset = tmp_cursor.pos.to_uint64()
  // Rust: `stream_offset + commands_size > stream.len()` (no overflow for sane sizes)
  if commands_size > stream.length().to_uint64() ||
    stream_offset + commands_size > stream.length().to_uint64() {
    raise invalid_icc_stream("invalid commands_size")
  }
  if output_size > 1UL << 28 {
    raise @bitstream.ProfileConformance("ICC output_size too large")
  }
  let stream_offset = stream_offset.to_int()
  let commands_size = commands_size.to_int()
  let commands = stream[stream_offset:stream_offset + commands_size]
  let data = stream[stream_offset + commands_size:]
  let header_size = (if output_size < 128UL { output_size } else { 128UL }).to_int()
  if data.length() < header_size {
    raise invalid_icc_stream("invalid output_size")
  }
  let header_data = data[:header_size]
  let mut data = data[header_size:]
  let commands_stream = Cursor::new(commands)
  let out : Array[Byte] = Array::new(capacity=output_size.to_int())

  // Header
  for idx in 0..<header_data.length() {
    let e = header_data[idx]
    let p = predict_header(idx, output_size.to_uint(), header_data)
    out.push((p.to_int() + e.to_int()).to_byte())
  }
  if output_size <= 128UL {
    return Bytes::from_array(out)
  }

  // Tag
  let v = varint(commands_stream)
  if v != 0UL {
    let num_tags = v - 1
    if (output_size - 128) / 12 < num_tags {
      raise invalid_icc_stream("num_tags too large")
    }
    let num_tags = num_tags.to_uint()
    push_be32_u(out, num_tags)
    let mut prev_tagstart : UInt32 = num_tags * 12 + 128
    let mut prev_tagsize : UInt32 = 0
    while true {
      guard commands_stream.read_byte() is Some(command) else {
        return Bytes::from_array(out)
      }
      let tagcode = command & 63
      let tag : BytesView = match tagcode {
        0 => break
        1 => {
          if data.length() < 4 {
            raise invalid_icc_stream("unexpected end of data stream")
          }
          let tag = data[:4]
          data = data[4:]
          tag
        }
        2..<=20 => common_tags[(tagcode - 2).to_int()][:]
        _ => raise invalid_icc_stream("invalid tagcode")
      }
      let tagstart = if (command & 64) == 0 {
        prev_tagstart + prev_tagsize
      } else {
        varint(commands_stream).to_uint()
      }
      let tagsize = if (command & 128) != 0 {
        varint(commands_stream).to_uint()
      } else if tag == b"rXYZ" ||
        tag == b"gXYZ" ||
        tag == b"bXYZ" ||
        tag == b"kXYZ" ||
        tag == b"wtpt" ||
        tag == b"bkpt" ||
        tag == b"lumi" {
        20
      } else {
        prev_tagsize
      }
      if tagstart.to_uint64() + tagsize.to_uint64() > output_size {
        raise invalid_icc_stream("ICC profile size mismatch")
      }
      prev_tagstart = tagstart
      prev_tagsize = tagsize
      out.push_iter(tag.iter())
      push_be32_u(out, tagstart)
      push_be32_u(out, tagsize)
      if tagcode == 2 {
        out.push_iter(b"gTRC".iter())
        push_be32_u(out, tagstart)
        push_be32_u(out, tagsize)
        out.push_iter(b"bTRC".iter())
        push_be32_u(out, tagstart)
        push_be32_u(out, tagsize)
      } else if tagcode == 3 {
        out.push_iter(b"gXYZ".iter())
        push_be32_u(out, tagstart + tagsize)
        push_be32_u(out, tagsize)
        out.push_iter(b"bXYZ".iter())
        push_be32_u(out, tagstart + tagsize * 2)
        push_be32_u(out, tagsize)
      }
    }
  }

  // Main
  while commands_stream.read_byte() is Some(command) {
    match command {
      1 => {
        let num = varint_usize(commands_stream)
        if num > data.length().to_uint64() {
          raise invalid_icc_stream("stream is too short")
        }
        let num = num.to_int()
        out.push_iter(data[:num].iter())
        data = data[num:]
      }
      2 | 3 => {
        let num = varint_usize(commands_stream)
        if num > data.length().to_uint64() {
          raise invalid_icc_stream("stream is too short")
        }
        let num = num.to_int()
        let bytes = data[:num]
        data = data[num:]
        let bytes = if command == 2 { shuffle2(bytes) } else { shuffle4(bytes) }
        out.push_iter(bytes.iter())
      }
      4 => {
        guard commands_stream.read_byte() is Some(flags) else {
          raise invalid_icc_stream("stream is too short")
        }
        let width = (flags & 3).to_int() + 1
        let order = ((flags >> 2) & 3).to_int()
        if width == 3 || order == 3 {
          raise invalid_icc_stream("width == 3 || order == 3")
        }
        let stride = if (flags & 16) == 0 {
          width.to_uint64()
        } else {
          let stride = varint_usize(commands_stream)
          if stride < width.to_uint64() {
            raise invalid_icc_stream("stride < width")
          }
          stride
        }
        // Rust: `stride.saturating_mul(4) >= out.len()`
        if stride >= 1UL << 60 || stride * 4 >= out.length().to_uint64() {
          raise invalid_icc_stream("stride * 4 >= out.len()")
        }
        let stride = stride.to_int()
        let num = varint_usize(commands_stream)
        if data.length().to_uint64() < num {
          raise invalid_icc_stream("stream is too short")
        }
        let num = num.to_int()
        let raw = data[:num]
        data = data[num:]
        let bytes : ArrayView[Byte] = match width {
          1 => raw.iter().collect()[:]
          2 => shuffle2(raw)[:]
          4 => shuffle4(raw)[:]
          _ => abort("unreachable")
        }
        let mut i = 0
        while i < num {
          let prev : FixedArray[UInt32] = [0, 0, 0]
          for j in 0..<=order {
            let offset = out.length() - stride * (j + 1)
            let mut v : UInt32 = 0
            for k in 0..<width {
              v = (v << 8) | out[offset + k].to_uint()
            }
            prev[j] = v
          }
          let p : UInt32 = match order {
            0 => prev[0]
            1 => 2U * prev[0] - prev[1]
            2 => 3U * (prev[0] - prev[1]) + prev[2]
            _ => abort("unreachable")
          }
          let n = if width < num - i { width } else { num - i }
          for j in 0..<n {
            let val = bytes[i + j].to_uint() + (p >> (8 * (width - 1 - j)))
            out.push(val.to_byte())
          }
          i += width
        }
      }
      10 => {
        if data.length() < 12 {
          raise invalid_icc_stream("stream is too short")
        }
        out.push_iter(b"XYZ \x00\x00\x00\x00".iter())
        out.push_iter(data[:12].iter())
        data = data[12:]
      }
      16..<=23 => {
        out.push_iter(common_data[command.to_int() - 16].iter())
        out.push_iter(b"\x00\x00\x00\x00".iter())
      }
      _ => raise invalid_icc_stream("invalid command")
    }
  }
  if out.length().to_uint64() != output_size {
    raise invalid_icc_stream("decoded ICC profile size mismatch")
  }
  Bytes::from_array(out)
}

///|
/// `varint(..) as usize`.
fn varint_usize(stream : Cursor) -> UInt64 raise @bitstream.JxlError {
  varint(stream)
}
