// Port of jxl-jbr/src/huffman.rs.

///|
pub(all) struct HuffmanCode {
  is_ac : Bool
  id : Int32
  is_last : Bool
  counts : FixedArray[Int32] // 17 entries
  values : Array[Int32]
}

///|
pub fn HuffmanCode::encoded_len(self : HuffmanCode) -> Int32 {
  1 + 16 + self.values.length() - 1
}

///|
pub fn HuffmanCode::build(self : HuffmanCode) -> BuiltHuffmanTable {
  let counts = self.counts
  let values = self.values
  let lengths : Array[Int32] = Array::make(values.length(), 0)
  let mut next = 0
  for len in 0..<counts.length() {
    let count = counts[len]
    for _ in 0..<count {
      lengths[next] = len
      next += 1
    }
  }
  let _ = lengths.pop()
  let bits : Array[UInt64] = []
  let mut next_code = 0UL
  let mut prev_len = lengths[0]
  for len in lengths {
    let shift_len = 64 - len
    if len != prev_len {
      next_code = next_code << (len - prev_len)
      prev_len = len
    }
    bits.push(if shift_len >= 64 { 0 } else { next_code << shift_len })
    next_code += 1
  }
  let reordered_lengths = FixedArray::make(256, 0)
  let reordered_bits = FixedArray::make(256, 0UL)
  for i in 0..<lengths.length() {
    let idx = values[i]
    reordered_lengths[idx] = lengths[i]
    reordered_bits[idx] = bits[i]
  }
  { lengths: reordered_lengths, bits: reordered_bits, }
}

///|
pub fn HuffmanCode::parse(
  bitstream : @bitstream.Bitstream,
) -> HuffmanCode raise @bitstream.JxlError {
  let is_ac = bitstream.read_bool()
  let id = bitstream.read_bits_int(2)
  let is_last = bitstream.read_bool()
  let counts = FixedArray::make(17, 0)
  let mut sum_counts = 0
  for i in 0..<17 {
    let x = bitstream
      .read_u32(
        @bitstream.c(0),
        @bitstream.c(1),
        @bitstream.cu(2, 3),
        @bitstream.u(8),
      )
      .reinterpret_as_int()
    sum_counts += x
    counts[i] = x & 0xff
  }
  let values = []
  for _ in 0..<sum_counts {
    let v = bitstream.read_u32(
      @bitstream.u(2),
      @bitstream.cu(4, 2),
      @bitstream.cu(8, 4),
      @bitstream.cu(1, 8),
    )
    values.push(v.reinterpret_as_int() & 0xff)
  }
  { is_ac, id, is_last, counts, values, }
}

///|
pub struct BuiltHuffmanTable {
  priv lengths : FixedArray[Int32]
  priv bits : FixedArray[UInt64]
}

///|
/// Returns `(length, bits)` for `symbol`; `bits` holds the code in its most
/// significant bits.
pub fn BuiltHuffmanTable::lookup(
  self : BuiltHuffmanTable,
  symbol : Int32,
) -> (Int32, UInt64) raise @bitstream.JxlError {
  let idx = symbol & 0xff
  let length = if idx < self.lengths.length() { self.lengths[idx] } else { 0 }
  if length == 0 {
    raise err_huffman_lookup()
  }
  (length, self.bits[idx])
}

///|
let empty_table : BuiltHuffmanTable = { lengths: [], bits: [], }
