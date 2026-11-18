///|
fn fnv1a(b : Bytes) -> UInt32 {
  let mut h = 0x811c9dc5U
  for x in b {
    h = (h ^ x.to_uint()) * 0x01000193U
  }
  h
}

///|
test "dictionary size" {
  let d = dictionary_data()
  assert_eq(d.length(), 122784)
  assert_eq(dictionary_offsets_by_length[25], 122784)
}

///|
test "truncated stream" {
  let b64 =
    #|CxWAVGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZwM=
  let data = decode_base64(b64)
  // quickfox; a truncated stream must raise unless partial
  let short = data[0:10].to_owned()
  try decompress(short) catch {
    Brotli(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected an error")
  }
  let partial = decompress_partial(short)
  assert_true(partial.length() < 43)
  // Trailing data after the end of the stream is an error.
  let long = Bytes::from_array([..data, b'\x00'])
  try decompress(long) catch {
    Brotli(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected an error")
  }
}
