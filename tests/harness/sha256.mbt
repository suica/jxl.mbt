// Minimal SHA-256 (FIPS 180-4), used to check reconstructed JPEG data
// (jxl-oxide-tests uses `ring::digest::SHA256`).

///|
let sha256_k : FixedArray[UInt32] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
  0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
  0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
  0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
  0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
  0xc67178f2,
]

///|
fn rotr(x : UInt32, n : Int32) -> UInt32 {
  (x >> n) | (x << (32 - n))
}

///|
/// SHA-256 digest of `data` (32 bytes).
pub fn sha256(data : BytesView) -> Bytes {
  let h : FixedArray[UInt32] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
    0x5be0cd19,
  ]
  let len = data.length()
  // padded length: len + 1 + pad + 8, multiple of 64
  let total = (len + 9 + 63) / 64 * 64
  let w = FixedArray::make(64, (0 : UInt32))
  let byte_at = fn(i : Int32) -> UInt32 {
    if i < len {
      data[i].to_uint()
    } else if i == len {
      0x80
    } else if i >= total - 8 {
      let bit_len = len.to_int64() * 8L
      let shift = (total - 1 - i) * 8
      (bit_len >> shift).to_uint() & 0xff
    } else {
      0
    }
  }
  for block = 0; block < total; block = block + 64 {
    let fast = block + 64 <= len
    for t in 0..<16 {
      let p = block + t * 4
      w[t] = if fast {
        (data[p].to_uint() << 24) |
        (data[p + 1].to_uint() << 16) |
        (data[p + 2].to_uint() << 8) |
        data[p + 3].to_uint()
      } else {
        (byte_at(p) << 24) |
        (byte_at(p + 1) << 16) |
        (byte_at(p + 2) << 8) |
        byte_at(p + 3)
      }
    }
    for t in 16..<64 {
      let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
      let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
      w[t] = w[t - 16] + s0 + w[t - 7] + s1
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    let mut f = h[5]
    let mut g = h[6]
    let mut hh = h[7]
    for t in 0..<64 {
      let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      let ch = (e & f) ^ (e.lnot() & g)
      let t1 = hh + s1 + ch + sha256_k[t] + w[t]
      let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      let maj = (a & b) ^ (a & c) ^ (b & c)
      let t2 = s0 + maj
      hh = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    h[0] += a
    h[1] += b
    h[2] += c
    h[3] += d
    h[4] += e
    h[5] += f
    h[6] += g
    h[7] += hh
  }
  Bytes::makei(32, fn(i) { (h[i / 4] >> ((3 - i % 4) * 8)).to_byte() })
}

///|
/// Lower-case hex string of `data`.
pub fn to_hex(data : BytesView) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  for b in data {
    let v = b.to_int()
    sb.write_char(digits.code_unit_at(v >> 4).to_int().unsafe_to_char())
    sb.write_char(digits.code_unit_at(v & 15).to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
pub fn sha256_hex(data : BytesView) -> String {
  to_hex(sha256(data))
}

///|
/// `ring::test::from_hex`.
pub fn from_hex(hex : String) -> Bytes raise Failure {
  guard hex.length() % 2 == 0 else { fail("odd hex length") }
  let digit = fn(c : Int) raise Failure {
    if c >= '0'.to_int() && c <= '9'.to_int() {
      c - '0'.to_int()
    } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
      c - 'a'.to_int() + 10
    } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
      c - 'A'.to_int() + 10
    } else {
      fail("invalid hex digit")
    }
  }
  let out = FixedArray::make(hex.length() / 2, b'\x00')
  for i in 0..<out.length() {
    let hi = digit(hex.code_unit_at(2 * i).to_int())
    let lo = digit(hex.code_unit_at(2 * i + 1).to_int())
    out[i] = ((hi << 4) | lo).to_byte()
  }
  Bytes::from_array(out[:])
}
