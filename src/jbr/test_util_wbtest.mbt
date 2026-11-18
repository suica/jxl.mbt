///|
fn decode_base64(text : String) -> Bytes {
  let out : Array[Byte] = []
  let mut acc = 0
  let mut acc_bits = 0
  for ch in text {
    let c = ch.to_int()
    let v = if c >= 'A' && c <= 'Z' {
      c - 'A'
    } else if c >= 'a' && c <= 'z' {
      c - 'a' + 26
    } else if c >= '0' && c <= '9' {
      c - '0' + 52
    } else if c == '+' {
      62
    } else if c == '/' {
      63
    } else {
      continue
    }
    acc = ((acc << 6) | v) & 0xffffff
    acc_bits += 6
    if acc_bits >= 8 {
      acc_bits -= 8
      out.push(((acc >> acc_bits) & 0xff).to_byte())
    }
  }
  Bytes::from_array(out)
}
