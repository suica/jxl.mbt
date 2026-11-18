// Upstream parity tests: the expected outcomes in icc_parity_data_wbtest.mbt were produced by
// running upstream jxl-oxide (release build) on the same inputs, plain and mutated
// (generator: scratch-colorhdr/parity in the session workspace). Cases where upstream panics
// are marked `Panic` and skipped (the port aborts at the same place).

///|
priv enum Expect {
  Full(String)
  Hash(UInt64)
  Panic
}

///|
fn fnv_bytes(b : BytesView) -> UInt64 {
  let mut h = 0xcbf29ce484222325UL
  for x in b {
    h = (h ^ x.to_uint64()) * 0x100000001b3UL
  }
  h
}

///|
fn fnv_str(s : String) -> UInt64 {
  let mut h = 0xcbf29ce484222325UL
  for i in 0..<s.length() {
    h = (h ^ (s.code_unit_at(i).to_int() & 0xff).to_uint64()) * 0x100000001b3UL
  }
  h
}

///|
fn hex16(v : UInt64) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder::new()
  for i in 0..<16 {
    let d = ((v >> (60 - 4 * i)) & 0xf).to_int()
    buf.write_char(digits.code_unit_at(d).to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
/// Normalised error text, matching the generator's `norm_color`/`norm_bs`.
fn norm_err(e : Error) -> String {
  match e {
    @bitstream.Color(s) => s
    @bitstream.Decoder(_) => "Decoder"
    @bitstream.Eof => "Eof"
    @bitstream.Io(_) => "Io"
    @bitstream.InvalidBox => "InvalidBox"
    @bitstream.NonZeroPadding => "NonZeroPadding"
    @bitstream.InvalidFloat => "InvalidFloat"
    @bitstream.InvalidEnum(n, v) => "InvalidEnum(\{n},\{v})"
    @bitstream.ValidationFailed(s) => "ValidationFailed(\{s})"
    @bitstream.ProfileConformance(s) => "ProfileConformance(\{s})"
    @bitstream.CannotSkip => "CannotSkip"
    @bitstream.NotAligned => "NotAligned"
    e => "Other(\{e})"
  }
}

///|
fn enum_encoding_debug(e : EnumColourEncoding) -> String {
  "EnumColourEncoding { colour_space: \{colour_space_debug(e.colour_space)}, white_point: \{white_point_debug(e.white_point)}, primaries: \{primaries_debug(e.primaries)}, tf: \{transfer_function_debug(e.tf)}, rendering_intent: \{rendering_intent_debug(e.rendering_intent)} }"
}

///|
/// `ColorEncodingWithProfile::with_icc(icc).encoding()` (or its error), then `icc_tf(icc)`.
fn icc_parse_outcome(icc : Bytes) -> String {
  let enc = try parse_icc(icc) catch {
    @bitstream.Color("UnsupportedIccProfile") =>
      try parse_icc_raw(icc) catch {
        e => "ERR:" + norm_err(e)
      } noraise {
        raw => "IccProfile(\{colour_space_debug(raw.color_space())})"
      }
    e => "ERR:" + norm_err(e)
  } noraise {
    e => "Enum(\{enum_encoding_debug(e)})"
  }
  let tf = match icc_tf(icc) {
    Some(tf) => "Some(\{transfer_function_debug(tf)})"
    None => "None"
  }
  enc + "|" + tf
}

///|
fn decode_outcome(s : Bytes) -> String {
  try decode_icc(s) catch {
    e => "ERR:" + norm_err(e)
  } noraise {
    v => "OK \{v.length()} \{hex16(fnv_bytes(v[:]))}"
  }
}

///|
fn read_outcome(cs : Bytes) -> String {
  let bs = @bitstream.Bitstream::new(cs)
  let h = @image.ImageHeader::parse(bs) catch {
    e => return "HDR:" + norm_err(e)
  }
  if !h.metadata.colour_encoding.want_icc() {
    return "NOICC"
  }
  try read_icc(bs) catch {
    e => "ERR:" + norm_err(e)
  } noraise {
    v => "OK \{v.length()} \{hex16(fnv_bytes(v[:]))} \{bs.num_read_bits()}"
  }
}

///|
fn apply_mutation(b : Bytes, m : Array[(Int32, Int32)]) -> Bytes {
  let v = b.to_fixedarray()
  for x in m {
    let (o, mask) = x
    v[o] = (v[o].to_int() ^ mask).to_byte()
  }
  Bytes::from_fixedarray(v)
}

///|
/// Checks `outcome` against `expect`; returns false when the case was skipped.
fn check_expect(
  label : String,
  outcome : String,
  expect : Expect,
) -> Unit raise Error {
  match expect {
    Full(s) => assert_eq(outcome, s, msg=label)
    Hash(h) =>
      if fnv_str(outcome) != h {
        fail("\{label}: outcome differs from upstream: \{outcome}")
      }
    Panic => ()
  }
}

///|
fn run_cases(
  name : String,
  cases : Array[(Bytes, Array[(Int32, Int32)], Expect)],
  outcome : (Bytes) -> String,
) -> Unit raise Error {
  let mut skipped = 0
  for i, c in cases {
    let (input, m, expect) = c
    if expect is Panic {
      skipped += 1
      continue
    }
    check_expect(
      "\{name} #\{i} \{m}",
      outcome(apply_mutation(input, m)),
      expect,
    )
  }
  println(
    "\{name}: \{cases.length() - skipped} cases match upstream, \{skipped} upstream panics skipped",
  )
}

///|
test "parity: colour_encoding_to_icc bytes and re-parse" {
  for i, c in parity_synth {
    let (enc, len, hash, expect) = c
    let icc = colour_encoding_to_icc(enc)
    assert_eq((i, icc.length(), fnv_bytes(icc[:])), (i, len, hash))
    check_expect("synth #\{i}", icc_parse_outcome(icc), expect)
  }
}

///|
test "parity: ICC profile parsing" {
  run_cases("icc_parse", parity_icc_parse, icc_parse_outcome)
}

///|
test "parity: decode_icc" {
  run_cases("decode_icc", parity_icc_decode, decode_outcome)
}

///|
test "parity: read_icc" {
  run_cases("read_icc", parity_icc_read, read_outcome)
}

///|
/// Upstream panics on this input (`12 * tag_count` wraps in `u32`, then the tag table slice
/// is out of range); the port aborts at the same point.
test "panic parity: parse_icc_raw with wrapped tag table size" {
  let icc = apply_mutation(profile_srgb_rel, [(105, 128), (39, 214), (128, 64)])
  ignore(parse_icc_raw(icc))
}
