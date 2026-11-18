// NumPy `.npy` reader (port of `read_numpy` in jxl-oxide-tests
// conformance/mod.rs, extended to parse the header).

///|
/// A float32 array loaded from an `.npy` file. `data` is in C order.
pub(all) struct Npy {
  shape : Array[Int32]
  data : FixedArray[Float]
}

///|
/// Parses an `.npy` file holding little-endian float32 data (`<f4`), C order.
/// Supports format versions 1.0 (u16 header length) and 2.0/3.0 (u32).
pub fn read_npy(buf : Bytes) -> Npy raise Failure {
  let magic = b"\x93NUMPY"
  if buf.length() < 10 {
    fail("npy: file too short")
  }
  for i in 0..<6 {
    if buf[i] != magic[i] {
      fail("npy: bad magic")
    }
  }
  let major = buf[6].to_int()
  let (header_len, header_start) = if major == 1 {
    (buf[8].to_int() | (buf[9].to_int() << 8), 10)
  } else if major == 2 || major == 3 {
    if buf.length() < 12 {
      fail("npy: file too short")
    }
    (read_u32_le(buf, 8), 12)
  } else {
    fail("npy: unsupported version \{major}")
  }
  let data_start = header_start + header_len
  if data_start > buf.length() {
    fail("npy: truncated header")
  }
  let header = StringBuilder()
  for i in header_start..<data_start {
    header.write_char(buf[i].to_int().unsafe_to_char())
  }
  let header = header.to_string()
  let descr = npy_dict_value(header, "descr")
  if !descr.contains("<f4") {
    fail("npy: unsupported dtype \{descr}")
  }
  let fortran = npy_dict_value(header, "fortran_order")
  if fortran.contains("True") {
    fail("npy: fortran order not supported")
  }
  let shape = parse_shape(npy_dict_value(header, "shape"))
  let mut count = 1
  for d in shape {
    count = count * d
  }
  if data_start + count * 4 > buf.length() {
    fail("npy: truncated data (want \{count} floats)")
  }
  let data = FixedArray::make(count, (0.0 : Float))
  for i in 0..<count {
    data[i] = Float::reinterpret_from_uint(
      read_u32_le(buf, data_start + i * 4).reinterpret_as_uint(),
    )
  }
  { shape, data, }
}

///|
/// Number of elements in one sub-array along the first axis
/// (e.g. one frame of a `(frames, height, width, channels)` array).
pub fn Npy::frame_len(self : Npy) -> Int32 {
  let mut n = 1
  for i in 1..<self.shape.length() {
    n = n * self.shape[i]
  }
  n
}

///|
/// Upstream-compatible split: chunks the data into `frames` equal parts.
pub fn Npy::frames(self : Npy, frames : Int32) -> Array[FixedArray[Float]] {
  let chunk = self.data.length() / frames
  let out = []
  for f in 0..<frames {
    let a = FixedArray::make(chunk, (0.0 : Float))
    for i in 0..<chunk {
      a[i] = self.data[f * chunk + i]
    }
    out.push(a)
  }
  out
}

///|
/// Serialises float32 data as an `.npy` (v1.0) file, used to dump renders
/// for debugging (port of `write_npy` in jxl-oxide-tests crop/mod.rs).
pub fn write_npy_bytes(shape : Array[Int32], data : FixedArray[Float]) -> Bytes {
  let dims = shape.map(fn(d) { d.to_string() })
  let shape_str = if dims.length() == 1 {
    "(" + dims[0] + ",)"
  } else {
    "(" + dims.join(", ") + ")"
  }
  let header = "{'descr': '<f4', 'fortran_order': False, 'shape': \{shape_str}, }\n"
  let buf = Buffer()
  buf.write_bytes(b"\x93NUMPY\x01\x00")
  let hl = header.length()
  buf.write_byte(hl.to_byte())
  buf.write_byte((hl >> 8).to_byte())
  for i in 0..<hl {
    buf.write_byte(header.code_unit_at(i).to_int().to_byte())
  }
  for f in data {
    let u = f.reinterpret_as_uint()
    buf.write_byte(u.to_byte())
    buf.write_byte((u >> 8).to_byte())
    buf.write_byte((u >> 16).to_byte())
    buf.write_byte((u >> 24).to_byte())
  }
  buf.to_bytes()
}

///|
pub fn read_u32_le(buf : Bytes, pos : Int32) -> Int32 {
  buf[pos].to_int() |
  (buf[pos + 1].to_int() << 8) |
  (buf[pos + 2].to_int() << 16) |
  (buf[pos + 3].to_int() << 24)
}

///|
/// Returns the raw text of the value for `'key':` in the header dict.
fn npy_dict_value(header : String, key : String) -> String raise Failure {
  let pat = "'" + key + "'"
  guard header.find(pat) is Some(start) else {
    fail("npy: key \{key} missing in header")
  }
  let rest = header.clamped_view(start=start + pat.length())
  guard rest.find(":") is Some(colon) else { fail("npy: malformed header") }
  let rest = rest.clamped_view(start=colon + 1)
  // value ends at the first ',' outside parentheses, or at '}'
  let mut depth = 0
  let sb = StringBuilder()
  for c in rest {
    if c == '(' {
      depth += 1
    } else if c == ')' {
      depth -= 1
    } else if (c == ',' && depth == 0) || c == '}' {
      break
    }
    sb.write_char(c)
  }
  sb.to_string().trim().to_owned()
}

///|
fn parse_shape(s : String) -> Array[Int32] raise Failure {
  let s = s.trim().to_owned()
  guard s.has_prefix("(") && s.has_suffix(")") else {
    fail("npy: bad shape \{s}")
  }
  let inner = s.clamped_view(start=1, end=s.length() - 1)
  let out = []
  for part in inner.split(",") {
    let p = part.trim()
    if p.length() == 0 {
      continue
    }
    out.push(@string.parse_int(p) catch { _ => fail("npy: bad shape \{s}") })
  }
  out
}
