// Differential test against upstream jxl-coding: `fuzz_cases` were produced
// by running the Rust crate on pseudo-random inputs (see fuzz_cases_test.mbt);
// here the same operations are replayed and the event logs are compared by
// hash.

///|
fn fuzz_err_code(e : @bitstream.JxlError) -> UInt32 {
  let code = match e {
    @bitstream.Eof => 1U
    @bitstream.Decoder(name) =>
      match name {
        "Lz77NotAllowed" => 2
        "InvalidAnsHistogram" => 3
        "InvalidAnsStream" => 4
        "InvalidIntegerConfig" => 5
        "InvalidPermutation" => 6
        "InvalidPrefixHistogram" => 7
        "PrefixSymbolTooLarge" => 8
        "InvalidCluster" => 9
        "ClusterHole" => 10
        "UnexpectedLz77Repeat" => 11
        "InvalidLz77Symbol" => 12
        _ => 99
      }
    _ => 99
  }
  0xdead0000U + code
}

///|
fn fuzz_ctx_of(j : Int32, num_dist : Int32) -> Int32 {
  (j * 7 + j / 3) % num_dist
}

///|
fn fuzz_mult_of(j : Int32) -> Int32 {
  if j % 3 == 0 {
    0
  } else {
    j % 5 + 1
  }
}

///|
fn hex_to_bytes(s : String) -> Bytes {
  let n = s.length() / 2
  let digit = fn(c : UInt16) -> Int32 {
    let c = c.to_int()
    if c >= '0'.to_int() && c <= '9'.to_int() {
      c - '0'.to_int()
    } else {
      c - 'a'.to_int() + 10
    }
  }
  Bytes::makei(n, i => {
    (digit(s.code_unit_at(2 * i)) * 16 + digit(s.code_unit_at(2 * i + 1))).to_byte()
  })
}

///|
fn fuzz_run(
  bytes : Bytes,
  mode : Int32,
  num_dist : Int32,
  p1 : UInt32,
  p2 : UInt32,
  log : Array[UInt32],
) -> Unit {
  let bs = @bitstream.Bitstream::new(bytes)
  fuzz_run_inner(bs, mode, num_dist, p1, p2, log) catch {
    e => log.push(fuzz_err_code(e))
  }
}

///|
fn fuzz_run_inner(
  bs : @bitstream.Bitstream,
  mode : Int32,
  num_dist : Int32,
  p1 : UInt32,
  p2 : UInt32,
  log : Array[UInt32],
) -> Unit raise @bitstream.JxlError {
  let k = 200
  match mode {
    0 | 1 => {
      let dec = @coding.Decoder::parse(bs, num_dist)
      log.push(bs.num_read_bits().reinterpret_as_uint())
      let map = dec.cluster_map()
      for c in map {
        log.push(c.reinterpret_as_uint())
        log.push(dec.single_token(c).unwrap_or(0xffffffff))
      }
      if mode == 0 {
        if (p1 & 1) == 1 {
          dec.begin(bs)
        }
        for j in 0..<k {
          if j == k / 2 {
            let d2 = dec.clone()
            let b2 = bs.clone()
            try {
              for jj in 0..<5 {
                log.push(
                  d2.read_varint_with_multiplier(
                    b2,
                    fuzz_ctx_of(jj + 3, num_dist),
                    fuzz_mult_of(jj),
                  ),
                )
              }
            } catch {
              e => log.push(fuzz_err_code(e))
            }
          }
          let r = if (p2 & 1) == 1 {
            let cl = map[fuzz_ctx_of(j, num_dist)]
            dec.read_varint_with_multiplier_clustered(bs, cl, fuzz_mult_of(j))
          } else {
            dec.read_varint_with_multiplier(
              bs,
              fuzz_ctx_of(j, num_dist),
              fuzz_mult_of(j),
            )
          }
          log.push(r)
        }
        log.push(bs.num_read_bits().reinterpret_as_uint())
        dec.finalize()
        log.push(1)
      } else {
        if dec.as_rle() is Some(rle) {
          log.push(0x11)
          for j in 0..<k {
            let cl = map[fuzz_ctx_of(j, num_dist)]
            match rle.read_varint_clustered(bs, cl) {
              Value(v) => {
                log.push(0)
                log.push(v)
              }
              Repeat(v) => {
                log.push(1)
                log.push(v)
              }
            }
          }
        } else if dec.as_with_lz77() is Some(d) {
          log.push(0x22)
          for j in 0..<k {
            let cl = map[fuzz_ctx_of(j, num_dist)]
            log.push(
              d.read_varint_with_multiplier_clustered(bs, cl, fuzz_mult_of(j)),
            )
          }
        } else if dec.as_no_lz77() is Some(d) {
          log.push(0x33)
          for j in 0..<k {
            let cl = map[fuzz_ctx_of(j, num_dist)]
            log.push(d.single_token(cl).unwrap_or(0xffffffff))
            log.push(d.read_varint_clustered(bs, cl))
          }
        }
        log.push(bs.num_read_bits().reinterpret_as_uint())
      }
    }
    2 => {
      let dec = @coding.Decoder::parse(bs, 8)
      let size = 1 + (p1 % 300).reinterpret_as_int()
      let skip = (p2 % (size + 1).reinterpret_as_uint()).reinterpret_as_int()
      try {
        let p = @coding.read_permutation(bs, dec, size, skip)
        log.push(p.length().reinterpret_as_uint())
        for v in p {
          log.push(v.reinterpret_as_uint())
        }
      } catch {
        e => log.push(fuzz_err_code(e))
      }
      log.push(bs.num_read_bits().reinterpret_as_uint())
    }
    _ => {
      let (n, map) = @coding.read_clusters(bs, num_dist)
      log.push(n.reinterpret_as_uint())
      for v in map {
        log.push(v.reinterpret_as_uint())
      }
      log.push(bs.num_read_bits().reinterpret_as_uint())
    }
  }
}

///|
fn fnv_hash(log : Array[UInt32]) -> UInt64 {
  let mut h = 0xcbf29ce484222325UL
  for v in log {
    for i in 0..<4 {
      h = h ^ ((v >> (8 * i)) & 0xff).to_uint64()
      h = h * 0x100000001b3UL
    }
  }
  h
}

///|
test "differential against upstream jxl-coding" {
  let mut failures = 0
  for i, case in fuzz_cases {
    let (hex, mode, num_dist, p1, p2, len, hash) = case
    let log = []
    fuzz_run(hex_to_bytes(hex), mode, num_dist, p1, p2, log)
    if log.length() != len || fnv_hash(log) != hash {
      failures += 1
      if failures <= 5 {
        println(
          "case \{i} (mode \{mode}, num_dist \{num_dist}): log len \{log.length()} vs \{len}; hash \{fnv_hash(log)} vs \{hash}",
        )
      }
    }
  }
  assert_eq(failures, 0)
}
