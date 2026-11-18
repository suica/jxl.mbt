// Port of jxl-coding/src/permutation.rs

///|
/// Read a permutation from the entropy encoded stream.
///
/// Requires `skip <= size`.
pub fn read_permutation(
  bitstream : @bitstream.Bitstream,
  decoder : Decoder,
  size : Int32,
  skip : Int32,
) -> Array[Int32] raise @bitstream.JxlError {
  let end = decoder.read_varint(
    bitstream,
    get_context(size.reinterpret_as_uint()),
  )
  if end > (size - skip).reinterpret_as_uint() {
    raise coding_error(InvalidPermutation)
  }
  let end = end.reinterpret_as_int()
  let lehmer = FixedArray::make(end, 0)
  let mut prev_val = 0U
  for idx in 0..<end {
    let val = decoder.read_varint(bitstream, get_context(prev_val))
    if val >= (size - skip - idx).reinterpret_as_uint() {
      raise coding_error(InvalidPermutation)
    }
    lehmer[idx] = val.reinterpret_as_int()
    prev_val = val
  }
  let temp : Array[Int32] = Array(
    capacity=if size > skip { size - skip } else { 0 },
  )
  for i in skip..<size {
    temp.push(i)
  }
  let permutation : Array[Int32] = Array(capacity=size)
  for idx in 0..<skip {
    permutation.push(idx)
  }
  for idx in lehmer {
    permutation.push(temp.remove(idx))
  }
  for v in temp {
    permutation.push(v)
  }
  permutation
}

///|
fn get_context(x : UInt32) -> Int32 {
  let v = add_log2_ceil(x)
  if v < 7 {
    v
  } else {
    7
  }
}
