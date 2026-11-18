// What a JPEG XL file's first bytes say of it before it is decoded, in the
// shape of mbui's `image_size`/`is_png` (`pixels/sniff.mbt`): whether the bytes
// are JPEG XL, and the width and height the image is shown at (its SizeHeader,
// sides swapped where ImageMetadata's orientation is 5-8, a quarter turn).

///|
/// Signature of a bare JPEG XL codestream.
let sniff_codestream_sig : Bytes = b"\xff\x0a"

///|
/// Signature of a JPEG XL container (the `JXL ` signature box).
let sniff_container_sig : Bytes = b"\x00\x00\x00\x0cJXL \x0d\x0a\x87\x0a"

///|
/// Whether `b` starts as a JPEG XL file does: a bare codestream (`FF 0A`) or
/// an ISOBMFF container whose first box is the `JXL ` signature box.
pub fn is_jxl(b : Bytes) -> Bool {
  b.has_prefix(sniff_container_sig[:]) || b.has_prefix(sniff_codestream_sig[:])
}

///|
/// The width and height a JPEG XL image is shown at (orientation applied), from
/// its SizeHeader and ImageMetadata, or None where `b` is not JPEG XL or is cut
/// off before them. Reads only the first few bytes of the codestream.
pub fn jxl_size(b : Bytes) -> (Int32, Int32)? {
  guard sniff_codestream_head(b) is Some(cs) else { return None }
  let bs = @bitstream.Bitstream::new(cs)
  sniff_size_header(bs) catch {
    _ => None
  }
}

///|
fn sniff_size_header(
  bs : @bitstream.Bitstream,
) -> (Int32, Int32)? raise @bitstream.JxlError {
  if bs.read_bits(16) != 0x0aff {
    return None
  }
  // SizeHeader (jxl-image header.rs)
  let div8 = bs.read_bool()
  let height = if div8 {
    (bs.read_bits_int(5) + 1) * 8
  } else {
    sniff_size_u32(bs)
  }
  let ratio = bs.read_bits_int(3)
  let width = if ratio == 0 {
    if div8 {
      (bs.read_bits_int(5) + 1) * 8
    } else {
      sniff_size_u32(bs)
    }
  } else {
    let (num, den) = match ratio {
      1 => (1L, 1L)
      2 => (12L, 10L)
      3 => (4L, 3L)
      4 => (3L, 2L)
      5 => (16L, 9L)
      6 => (5L, 4L)
      _ => (2L, 1L)
    }
    let w = height.to_int64() * num / den
    if w > 0x7fffffffL {
      return None
    }
    w.to_int()
  }
  // ImageMetadata: all_default, extra_fields, orientation
  let orientation = if bs.read_bool() {
    1
  } else if bs.read_bool() {
    bs.read_bits_int(3) + 1
  } else {
    1
  }
  if width <= 0 || height <= 0 {
    return None
  }
  Some(if orientation > 4 { (height, width) } else { (width, height) })
}

///|
fn sniff_size_u32(bs : @bitstream.Bitstream) -> Int32 raise @bitstream.JxlError {
  let v = bs.read_u32(
    @bitstream.cu(1, 9),
    @bitstream.cu(1, 13),
    @bitstream.cu(1, 18),
    @bitstream.cu(1, 30),
  )
  // values above i32 range cannot be decoded here anyway
  if v > 0x7fffffffU {
    0
  } else {
    v.reinterpret_as_int()
  }
}

///|
/// The first bytes of the codestream: `b` itself when it is a bare codestream,
/// else the payloads of its `jxlc` box or its `jxlp` boxes joined (at most 64
/// bytes, enough for the headers read here).
fn sniff_codestream_head(b : Bytes) -> Bytes? {
  if b.has_prefix(sniff_codestream_sig[:]) {
    return Some(b)
  }
  if !b.has_prefix(sniff_container_sig[:]) {
    return None
  }
  let n = b.length()
  let be32 = fn(i : Int32) -> Int64 {
    (b[i].to_int64() << 24) |
    (b[i + 1].to_int64() << 16) |
    (b[i + 2].to_int64() << 8) |
    b[i + 3].to_int64()
  }
  let out = Buffer()
  let want = 64
  let mut at = 0
  while at + 8 <= n && out.length() < want {
    let size = be32(at)
    let ty = b[at + 4:at + 8]
    let (body, end) = if size == 1L {
      if at + 16 > n {
        break
      }
      let big = (be32(at + 8) << 32) | be32(at + 12)
      (at + 16, if big > (n - at).to_int64() { n } else { at + big.to_int() })
    } else if size == 0L {
      (at + 8, n)
    } else if size < 8L {
      return None
    } else {
      (at + 8, if size > (n - at).to_int64() { n } else { at + size.to_int() })
    }
    if ty == b"jxlc"[:] {
      out.write_bytesview(b[body:end])
      break
    } else if ty == b"jxlp"[:] {
      if body + 4 <= end {
        out.write_bytesview(b[body + 4:end])
      }
    }
    if end <= at {
      break
    }
    at = end
  }
  if out.length() == 0 {
    None
  } else {
    Some(out.to_bytes())
  }
}
