// Differential test against upstream jxl-bitstream: replays the random
// operation sequences of bs_fuzz_cases_test.mbt and compares the log hashes.

///|
priv struct XorShift {
  mut s : UInt64
}

///|
fn XorShift::next(self : XorShift) -> UInt32 {
  self.s = self.s ^ (self.s << 13)
  self.s = self.s ^ (self.s >> 7)
  self.s = self.s ^ (self.s << 17)
  (self.s >> 16).to_uint()
}

///|
fn bs_hex(s : String) -> Bytes {
  let digit = fn(c : UInt16) -> Int32 {
    let c = c.to_int()
    if c <= '9'.to_int() {
      c - '0'.to_int()
    } else {
      c - 'a'.to_int() + 10
    }
  }
  Bytes::makei(s.length() / 2, i => {
    (digit(s.code_unit_at(2 * i)) * 16 + digit(s.code_unit_at(2 * i + 1))).to_byte()
  })
}

///|
fn bs_code(e : @bitstream.JxlError) -> UInt32 {
  match e {
    Eof => 0xdead0001
    NonZeroPadding => 0xdead0002
    InvalidFloat => 0xdead0003
    InvalidEnum(_, value) => 0xdead1000U + value
    _ => 0xdead0099
  }
}

///|
test "bitstream differential against upstream jxl-bitstream" {
  let mut failures = 0
  for i, case in bs_fuzz_cases {
    let (hex, seed, len, hash) = case
    let r = XorShift::{ s: seed.to_uint64() | 1, }
    let bs = @bitstream.Bitstream::new(bs_hex(hex))
    let log : Array[UInt32] = []
    for _ in 0..<60 {
      let op = r.next() % 10
      let res : Result[UInt32, @bitstream.JxlError] = Ok(
        match op {
          0 => bs.read_bits((r.next() % 33).reinterpret_as_int())
          1 => {
            bs.skip_bits((r.next() % 100).reinterpret_as_int())
            0
          }
          2 => bs.peek_bits((r.next() % 33).reinterpret_as_int())
          3 => bs.peek_bits_prefilled((r.next() % 33).reinterpret_as_int())
          4 => {
            bs.consume_bits((r.next() % 70).reinterpret_as_int())
            0
          }
          5 =>
            bs.read_u32(
              @bitstream.c(1),
              @bitstream.u(2),
              @bitstream.cu(3, 4),
              @bitstream.cu(19, 8),
            )
          6 => {
            let v = bs.read_u64()
            v.to_uint() ^ (v >> 32).to_uint()
          }
          7 => bs.read_f16_as_f32().reinterpret_as_uint()
          8 => {
            bs.zero_pad_to_byte()
            0
          }
          _ => if bs.read_bool() { 1 } else { 0 }
        },
      ) catch {
        e => Err(e)
      }
      log.push(op)
      match res {
        Ok(v) => log.push(v)
        Err(e) => log.push(bs_code(e))
      }
      log.push(bs.num_read_bits().reinterpret_as_uint())
    }
    let mut h = 0xcbf29ce484222325UL
    for v in log {
      for k in 0..<4 {
        h = h ^ ((v >> (8 * k)) & 0xff).to_uint64()
        h = h * 0x100000001b3UL
      }
    }
    if log.length() != len || h != hash {
      failures += 1
      if failures <= 3 {
        println("case \{i} differs")
      }
    }
  }
  assert_eq(failures, 0)
}

///|
test "read_u32 doc example" {
  // Upstream doc test of `Bitstream::read_u32`.
  let bs = @bitstream.Bitstream::new(b"\x32")
  let v = bs.read_u32(
    @bitstream.c(1),
    @bitstream.u(2),
    @bitstream.cu(3, 4),
    @bitstream.cu(19, 8),
  )
  assert_eq(v, 15)
}

///|
test "error display matches upstream" {
  let e1 = @bitstream.Eof
  assert_eq("\{e1}", "I/O error: unexpected end of file")
  let e2 = @bitstream.InvalidEnum("ColourSpace", 9)
  assert_eq("\{e2}", "Enum(ColourSpace) read invalid enum value of 9")
  let e3 = @bitstream.Decoder(
    InvalidIntegerConfig(split_exponent=3, msb_in_token=2, lsb_in_token=Some(2)),
  )
  assert_eq("\{e3}", "invalid hybrid integer configuration; 2 + 2 > 3")
  let e4 = @bitstream.Decoder(
    ClusterHole(num_expected_clusters=3, num_actual_clusters=2),
  )
  assert_eq("\{e4}", "distribution cluster has a hole; expected 3, actual 2")
}

///|
#derive(Eq, Debug)
priv enum TestEnum {
  A
  B
}

///|
impl @bitstream.JxlEnum for TestEnum with fn try_from_u32(v) {
  match v {
    0 => Some(A)
    1 => Some(B)
    _ => None
  }
}

///|
impl @bitstream.JxlEnum for TestEnum with fn type_name() {
  "TestEnum"
}

///|
test "read_enum and Name" {
  // selector 1 -> 1 (B); selector 2 -> 2 + u(4) = 2 + 5 = 7 (invalid)
  let bs = @bitstream.Bitstream::new(b"\x59")
  let e : TestEnum = bs.read_enum()
  assert_eq(e, B)
  let r : Result[TestEnum, @bitstream.JxlError] = Ok(bs.read_enum()) catch {
    err => Err(err)
  }
  assert_eq(r, Err(@bitstream.InvalidEnum("TestEnum", 7)))
  // Name: length u32 selector 0 -> 0 bytes
  let bs = @bitstream.Bitstream::new(b"\x00")
  assert_eq(@bitstream.Name::parse(bs).as_str(), "")
}
