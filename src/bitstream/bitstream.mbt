///|
/// LSB-first bit reader over a byte buffer, ported from jxl-bitstream.
pub struct Bitstream {
  bytes : Bytes
  /// One past the last byte this reader may read.
  end : Int32
  /// Next byte to load into `buf`.
  mut pos : Int32
  mut buf : UInt64
  mut num_read_bits : Int32
  mut remaining_buf_bits : Int32
}

///|
pub fn Bitstream::new(bytes : Bytes) -> Bitstream {
  {
    bytes,
    end: bytes.length(),
    pos: 0,
    buf: 0,
    num_read_bits: 0,
    remaining_buf_bits: 0,
  }
}

///|
/// A reader over `bytes[start:start+len]`.
pub fn Bitstream::new_range(
  bytes : Bytes,
  start : Int32,
  len : Int32,
) -> Bitstream {
  {
    bytes,
    end: start + len,
    pos: start,
    buf: 0,
    num_read_bits: 0,
    remaining_buf_bits: 0,
  }
}

///|
/// An independent copy of the reader state (Rust `Clone`).
pub fn Bitstream::clone(self : Bitstream) -> Bitstream {
  {
    bytes: self.bytes,
    end: self.end,
    pos: self.pos,
    buf: self.buf,
    num_read_bits: self.num_read_bits,
    remaining_buf_bits: self.remaining_buf_bits,
  }
}

///|
pub fn Bitstream::num_read_bits(self : Bitstream) -> Int32 {
  self.num_read_bits
}

///|
/// Number of bytes not yet loaded into the bit buffer.
pub fn Bitstream::bytes_left(self : Bitstream) -> Int32 {
  self.end - self.pos
}

///|
/// Number of bits that can still be read.
pub fn Bitstream::bits_left(self : Bitstream) -> Int32 {
  self.remaining_buf_bits + (self.end - self.pos) * 8
}

///|
/// Fills bit buffer from byte buffer (upstream `refill`: an 8-byte load when
/// at least 8 bytes are left, otherwise byte by byte up to 56 bits).
#inline
fn Bitstream::refill(self : Bitstream) -> Unit {
  let p = self.pos
  if self.end - p >= 8 {
    let b = self.bytes
    let bits = b[p].to_uint64() |
      (b[p + 1].to_uint64() << 8) |
      (b[p + 2].to_uint64() << 16) |
      (b[p + 3].to_uint64() << 24) |
      (b[p + 4].to_uint64() << 32) |
      (b[p + 5].to_uint64() << 40) |
      (b[p + 6].to_uint64() << 48) |
      (b[p + 7].to_uint64() << 56)
    self.buf = self.buf | (bits << self.remaining_buf_bits)
    let read_bytes = (63 - self.remaining_buf_bits) >> 3
    self.remaining_buf_bits = self.remaining_buf_bits | 56
    self.pos = p + read_bytes
  } else {
    self.refill_slow()
  }
}

///|
fn Bitstream::refill_slow(self : Bitstream) -> Unit {
  while self.remaining_buf_bits < 56 {
    if self.pos >= self.end {
      return
    }
    self.buf = self.buf |
      (self.bytes[self.pos].to_uint64() << self.remaining_buf_bits)
    self.remaining_buf_bits += 8
    self.pos += 1
  }
}

///|
/// Peeks `n` bits (n <= 32), refilling the buffer first.
pub fn Bitstream::peek_bits(self : Bitstream, n : Int32) -> UInt32 {
  self.refill()
  (self.buf & ((1UL << n) - 1)).to_uint()
}

///|
/// Peeks `n` bits without refilling; only valid after a `peek_bits`.
pub fn Bitstream::peek_bits_prefilled(self : Bitstream, n : Int32) -> UInt32 {
  (self.buf & ((1UL << n) - 1)).to_uint()
}

///|
pub fn Bitstream::consume_bits(
  self : Bitstream,
  n : Int32,
) -> Unit raise JxlError {
  if n > self.remaining_buf_bits {
    raise Eof
  }
  self.remaining_buf_bits -= n
  self.num_read_bits += n
  self.buf = self.buf >> n
}

///|
/// Reads `n` bits (n <= 32) as an unsigned value.
pub fn Bitstream::read_bits(
  self : Bitstream,
  n : Int32,
) -> UInt32 raise JxlError {
  let ret = self.peek_bits(n)
  self.consume_bits(n)
  ret
}

///|
/// `read_bits` returning a (non-negative) `Int`; n must be <= 31.
pub fn Bitstream::read_bits_int(
  self : Bitstream,
  n : Int32,
) -> Int32 raise JxlError {
  self.read_bits(n).reinterpret_as_int()
}

///|
pub fn Bitstream::skip_bits(self : Bitstream, n : Int32) -> Unit raise JxlError {
  if n <= self.remaining_buf_bits {
    self.num_read_bits += n
    self.remaining_buf_bits -= n
    self.buf = self.buf >> n
    return
  }
  let mut n = n - self.remaining_buf_bits
  self.num_read_bits += self.remaining_buf_bits
  self.buf = 0
  self.remaining_buf_bits = 0
  let avail = self.end - self.pos
  if n.to_int64() > avail.to_int64() * 8L {
    // Upstream counts the remaining bytes as read but does not advance the
    // byte slice.
    self.num_read_bits += avail * 8
    raise Eof
  }
  self.num_read_bits += n
  self.pos += n / 8
  n = n % 8
  self.refill()
  if self.remaining_buf_bits < n {
    raise Eof
  }
  self.remaining_buf_bits -= n
  self.buf = self.buf >> n
}

///|
pub fn Bitstream::zero_pad_to_byte(self : Bitstream) -> Unit raise JxlError {
  let byte_boundary = (self.num_read_bits + 7) / 8 * 8
  let n = byte_boundary - self.num_read_bits
  if self.read_bits(n) != 0 {
    raise NonZeroPadding
  }
}

///|
/// A `U32` distribution entry: constant, or `offset + u(bits)`.
pub(all) enum U32Spec {
  Constant(UInt32)
  BitsOffset(UInt32, Int32)
}

///|
/// `u(n)`
pub fn u(n : Int32) -> U32Spec {
  BitsOffset(0, n)
}

///|
/// `c + u(n)`
pub fn cu(c : UInt32, n : Int32) -> U32Spec {
  BitsOffset(c, n)
}

///|
/// `c`
pub fn c(v : UInt32) -> U32Spec {
  Constant(v)
}

///|
pub fn Bitstream::read_u32(
  self : Bitstream,
  d0 : U32Spec,
  d1 : U32Spec,
  d2 : U32Spec,
  d3 : U32Spec,
) -> UInt32 raise JxlError {
  let d = match self.read_bits(2) {
    0 => d0
    1 => d1
    2 => d2
    _ => d3
  }
  match d {
    Constant(x) => x
    BitsOffset(offset, n) => self.read_bits(n) + offset
  }
}

///|
pub fn Bitstream::read_u64(self : Bitstream) -> UInt64 raise JxlError {
  match self.read_bits(2) {
    0 => 0
    1 => self.read_bits(4).to_uint64() + 1
    2 => self.read_bits(8).to_uint64() + 17
    _ => {
      let mut value = self.read_bits(12).to_uint64()
      let mut shift = 12
      while self.read_bits(1) == 1 {
        if shift == 60 {
          value = value | (self.read_bits(4).to_uint64() << shift)
          break
        }
        value = value | (self.read_bits(8).to_uint64() << shift)
        shift += 8
      }
      value
    }
  }
}

///|
pub fn Bitstream::read_bool(self : Bitstream) -> Bool raise JxlError {
  self.read_bits(1) != 0
}

///|
pub fn Bitstream::read_f16_as_f32(self : Bitstream) -> Float raise JxlError {
  let v = self.read_bits(16)
  let neg_bit = (v & 0x8000) << 16
  if (v & 0x7fff) == 0 {
    return Float::reinterpret_from_uint(neg_bit)
  }
  let mantissa = v & 0x3ff
  let exponent = (v >> 10) & 0x1f
  if exponent == 0x1f {
    raise InvalidFloat
  } else if exponent == 0 {
    let val : Float = (1.0 : Float) /
      16384.0 *
      (Float::from_int(mantissa.reinterpret_as_int()) / 1024.0)
    if neg_bit != 0 {
      -val
    } else {
      val
    }
  } else {
    let mantissa = mantissa << 13
    let exponent = exponent + 112
    Float::reinterpret_from_uint(mantissa | (exponent << 23) | neg_bit)
  }
}

///|
/// Reads the raw value of an `Enum(T)` field; callers map it to their enum
/// and raise `InvalidEnum(name, value)` when it is out of range.
pub fn Bitstream::read_enum_raw(self : Bitstream) -> UInt32 raise JxlError {
  self.read_u32(c(0), c(1), cu(2, 4), cu(18, 6))
}

///|
/// Reads `n` bytes (after the reader is byte aligned) into a new buffer.
pub fn Bitstream::read_bytes_aligned(
  self : Bitstream,
  n : Int32,
) -> Bytes raise JxlError {
  if self.num_read_bits % 8 != 0 {
    raise NotAligned
  }
  if n > self.bits_left() / 8 {
    raise Eof
  }
  let out = FixedArray::make(n, b'\x00')
  for i in 0..<n {
    out[i] = self.read_bits(8).to_byte()
  }
  Bytes::from_array(out)
}

///|
pub fn unpack_signed(x : UInt32) -> Int32 {
  let bit = x & 1
  let base = x >> 1
  let flip = 0U - bit
  (base ^ flip).reinterpret_as_int()
}

///|
pub fn unpack_signed_u64(x : UInt64) -> Int64 {
  let bit = x & 1
  let base = x >> 1
  let flip = 0UL - bit
  (base ^ flip).reinterpret_as_int64()
}

///|
/// The `Name` bundle: a UTF-8 string with a U32 length prefix.
pub fn read_name(bs : Bitstream) -> String raise JxlError {
  let len = bs.read_u32(c(0), u(4), cu(16, 5), cu(48, 10)).reinterpret_as_int()
  let data = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    data[i] = bs.read_bits(8).to_byte()
  }
  @utf8.decode(Bytes::from_array(data)) catch {
    _ => raise ValidationFailed("non-UTF-8 name")
  }
}

///|
/// Name type which is read by some JPEG XL headers (jxl-oxide-common `Name`).
#derive(Eq, Debug)
pub(all) struct Name(String)

///|
/// `Name::parse` (the `Bundle` impl): a UTF-8 string with a U32 length
/// prefix.
pub fn Name::parse(bs : Bitstream) -> Name raise JxlError {
  Name(read_name(bs))
}

///|
/// The string of the name (Rust `Deref<Target = String>`).
pub fn Name::as_str(self : Name) -> String {
  self.0
}

///|
/// An enum that can be read with [Bitstream::read_enum] (Rust
/// `E: TryFrom<u32>` plus `std::any::type_name::<E>()` for the error).
pub(open) trait JxlEnum {
  fn try_from_u32(UInt32) -> Self?
  fn type_name() -> String
}

///|
/// Reads an enum as defined in the JPEG XL specification.
///
/// Raises `InvalidEnum(type_name, value)` if the value is not a variant.
pub fn[E : JxlEnum] Bitstream::read_enum(self : Bitstream) -> E raise JxlError {
  let v = self.read_u32(c(0), c(1), cu(2, 4), cu(18, 6))
  match E::try_from_u32(v) {
    Some(e) => e
    None => raise InvalidEnum(E::type_name(), v)
  }
}
