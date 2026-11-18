// Port of c/common/transform.c and c/common/dictionary.c (Google brotli, MIT
// License): the RFC 7932 static dictionary and its 121 word transforms.

///|
const TRANSFORM_OMIT_LAST_9 = 9

///|
const TRANSFORM_UPPERCASE_FIRST = 10

///|
const TRANSFORM_UPPERCASE_ALL = 11

///|
const TRANSFORM_OMIT_FIRST_1 = 12

///|
const TRANSFORM_OMIT_FIRST_9 = 20

///|
const NUM_TRANSFORMS = 121

///|
/// `cutOffTransforms[0]`: the identity transform index.
const CUTOFF_TRANSFORM_0 = 0

///|
let dictionary_cache : Ref[Bytes?] = { val: None, }

///|
fn base64_value(c : Int32) -> Int32 {
  if c >= 'A' && c <= 'Z' {
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
    -1
  }
}

///|
/// Decodes base64 text, ignoring characters outside the alphabet.
fn decode_base64(text : String) -> Bytes {
  let out : Array[Byte] = []
  let mut acc = 0
  let mut acc_bits = 0
  for ch in text {
    let v = base64_value(ch.to_int())
    if v < 0 {
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

///|
/// The RFC 7932 static dictionary data (122784 bytes), decoded on first use.
pub fn dictionary_data() -> Bytes {
  match dictionary_cache.val {
    Some(d) => d
    None => {
      let d = decode_base64(dictionary_base64)
      dictionary_cache.val = Some(d)
      d
    }
  }
}

///|
/// `ToUpperCase`: an overly simplified uppercasing model for UTF-8.
fn to_upper_case(p : FixedArray[Byte], i : Int32) -> Int32 {
  let c = p[i].to_int()
  if c < 0xC0 {
    if c >= 'a' && c <= 'z' {
      p[i] = (c ^ 32).to_byte()
    }
    return 1
  }
  // An overly simplified uppercasing model for UTF-8.
  if c < 0xE0 {
    p[i + 1] = p[i + 1] ^ 32
    return 2
  }
  // An arbitrary transform for three byte characters.
  p[i + 2] = p[i + 2] ^ 5
  3
}

///|
/// `BrotliTransformDictionaryWord`: writes the transformed word into `dst`
/// starting at 0 and returns its length. `dst` must have room for
/// 255 + len + 255 + 3 bytes.
fn transform_dictionary_word(
  dst : FixedArray[Byte],
  dict : Bytes,
  word_off : Int32,
  len : Int32,
  transform_idx : Int32,
) -> Int32 {
  let mut idx = 0
  let prefix = prefix_suffix_map[transforms_data[transform_idx * 3]]
  let t = transforms_data[transform_idx * 3 + 1]
  let suffix = prefix_suffix_map[transforms_data[transform_idx * 3 + 2]]
  let prefix_len = prefix_suffix[prefix]
  for k in 0..<prefix_len {
    dst[idx] = prefix_suffix[prefix + 1 + k].to_byte()
    idx += 1
  }
  let mut word = word_off
  let mut len = len
  if t <= TRANSFORM_OMIT_LAST_9 {
    len -= t
  } else if t >= TRANSFORM_OMIT_FIRST_1 && t <= TRANSFORM_OMIT_FIRST_9 {
    let skip = t - (TRANSFORM_OMIT_FIRST_1 - 1)
    word += skip
    len -= skip
  }
  for i in 0..<len {
    dst[idx] = dict[word + i]
    idx += 1
  }
  if t == TRANSFORM_UPPERCASE_FIRST {
    let _ = to_upper_case(dst, idx - len)
  } else if t == TRANSFORM_UPPERCASE_ALL {
    let mut up = idx - len
    while len > 0 {
      let step = to_upper_case(dst, up)
      up += step
      len -= step
    }
  }
  // SHIFT_FIRST / SHIFT_ALL only occur with shared (non-RFC) dictionaries.
  let suffix_len = prefix_suffix[suffix]
  for k in 0..<suffix_len {
    dst[idx] = prefix_suffix[suffix + 1 + k].to_byte()
    idx += 1
  }
  idx
}
