// Fuzz comparison against pxfm 0.1.30: the input streams below mirror
// `testdata/fixgen/src/main.rs` exactly; `fuzz_digests` holds FNV-1a digests
// of the upstream outputs for each chunk of `fuzz_chunk_size` inputs.
//
// By default one chunk per variant runs; set PXFM_FUZZ_FULL=1 to run all
// chunks (16 x 65536 = 1,048,576 inputs per variant).

///|
priv struct FuzzRng {
  mut state : UInt64
}

///|
fn FuzzRng::next(self : FuzzRng) -> UInt64 {
  self.state = self.state + 0x9e3779b97f4a7c15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9UL
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebUL
  z ^ (z >> 31)
}

///|
fn FuzzRng::below(self : FuzzRng, n : UInt64) -> UInt64 {
  self.next() % n
}

///|
fn FuzzRng::range(self : FuzzRng, lo : UInt64, hi : UInt64) -> UInt64 {
  lo + self.next() % (hi - lo + 1UL)
}

///|
priv struct FuzzDom {
  lo : UInt64
  hi : UInt64
  signed : Bool
}

///|
let fuzz_sign64 : UInt64 = 1UL << 63

///|
fn gen_x64(r : FuzzRng, d : FuzzDom) -> UInt64 {
  match r.below(12UL) {
    0 => r.next()
    1 => r.range(0UL, 0x3ff0000000000000UL)
    2 => r.range(1UL, 0x4000000000000000UL)
    3 => {
      let b = r.range(d.lo, d.hi)
      let s = r.next() & 1UL
      if d.signed && s == 1UL {
        b | fuzz_sign64
      } else {
        b
      }
    }
    4 => 0x3ff0000000000000UL + r.range(0UL, 1UL << 21) - (1UL << 20)
    5 => fuzz_special64[r.below(fuzz_special64.length().to_uint64()).to_int()]
    6 => {
      let b = r.range(1UL, 0xfffffffffffffUL)
      let s = r.next() & fuzz_sign64
      b | s
    }
    7 => tb((r.range(0UL, 800UL).reinterpret_as_int64() - 400L).to_double())
    8 => tb(r.range(0UL, 1UL << 24).to_double() / 16777216.0)
    9 => r.range(d.lo, d.hi)
    10 => r.range(0x4300000000000000UL, 0x7fefffffffffffffUL)
    _ => r.range(0x0010000000000000UL, 0x3c90000000000000UL)
  }
}

///|
fn gen_y64(r : FuzzRng) -> UInt64 {
  let g = fuzz_gamma64
  match r.below(10UL) {
    0 | 1 => g[r.below(g.length().to_uint64()).to_int()]
    2 => r.next()
    3 => tb((r.range(0UL, 220UL).reinterpret_as_int64() - 110L).to_double())
    4 => {
      let b = r.range(0UL, 0x4030000000000000UL)
      let s = r.next() & fuzz_sign64
      b | s
    }
    5 => fuzz_special64[r.below(fuzz_special64.length().to_uint64()).to_int()]
    6 => {
      let b = r.range(0x3c00000000000000UL, 0x3ff0000000000000UL)
      let s = r.next() & fuzz_sign64
      b | s
    }
    7 => {
      let b = r.range(0x4030000000000000UL, 0x4400000000000000UL)
      let s = r.next() & fuzz_sign64
      b | s
    }
    8 =>
      tb((r.range(0UL, 400UL).reinterpret_as_int64() - 200L).to_double() + 0.5)
    _ => tb(1.0 / r.range(1UL, 20UL).to_double())
  }
}

///|
fn gen_x32(r : FuzzRng) -> UInt32 {
  match r.below(12UL) {
    0 => r.next().to_uint()
    1 => r.range(0UL, 0x3f800000UL).to_uint()
    2 => r.range(1UL, 0x40000000UL).to_uint()
    3 => r.range(0x00800000UL, 0x7f7fffffUL).to_uint()
    4 => 0x3f800000U + r.range(0UL, 1UL << 13).to_uint() - (1U << 12)
    5 => fuzz_special32[r.below(fuzz_special32.length().to_uint64()).to_int()]
    6 => {
      let b = r.range(1UL, 0x7fffffUL).to_uint()
      let s = r.next().to_uint() & 0x80000000U
      b | s
    }
    7 =>
      tbf(Float::from_int64(r.range(0UL, 800UL).reinterpret_as_int64() - 400L))
    8 => {
      let n : Float = 65535.0
      tbf(Float::from_uint64(r.range(0UL, 65535UL)) / n)
    }
    9 => r.range(0UL, 0x3f800000UL).to_uint() | 0x80000000U
    10 => {
      let n : Float = 255.0
      tbf(Float::from_uint64(r.range(0UL, 255UL)) / n)
    }
    _ => r.range(0x4b000000UL, 0x7f7fffffUL).to_uint()
  }
}

///|
fn gen_y32(r : FuzzRng) -> UInt32 {
  let g = fuzz_gamma32
  match r.below(10UL) {
    0 | 1 => g[r.below(g.length().to_uint64()).to_int()]
    2 => r.next().to_uint()
    3 => tbf(Float::from_int64(r.range(0UL, 60UL).reinterpret_as_int64() - 30L))
    4 => {
      let b = r.range(0UL, 0x41800000UL).to_uint()
      let s = r.next().to_uint() & 0x80000000U
      b | s
    }
    5 => fuzz_special32[r.below(fuzz_special32.length().to_uint64()).to_int()]
    6 => {
      let b = r.range(0x30000000UL, 0x3f800000UL).to_uint()
      let s = r.next().to_uint() & 0x80000000U
      b | s
    }
    7 => {
      let b = r.range(0x41800000UL, 0x4f800000UL).to_uint()
      let s = r.next().to_uint() & 0x80000000U
      b | s
    }
    8 => {
      let h : Float = 0.5
      tbf(
        Float::from_int64(r.range(0UL, 400UL).reinterpret_as_int64() - 200L) + h,
      )
    }
    _ => {
      let one : Float = 1.0
      tbf(one / Float::from_uint64(r.range(1UL, 20UL)))
    }
  }
}

///|
fn fuzz_input(name : String, r : FuzzRng) -> (UInt64, UInt64) {
  match name {
    "exp" | "exp_generic" =>
      (gen_x64(r, { lo: 0UL, hi: 0x4087800000000000UL, signed: true, }), 0UL)
    "exp10" | "exp10_generic" =>
      (gen_x64(r, { lo: 0UL, hi: 0x4074800000000000UL, signed: true, }), 0UL)
    "exp2" | "exp2_generic" =>
      (gen_x64(r, { lo: 0UL, hi: 0x4091000000000000UL, signed: true, }), 0UL)
    "log" | "log10" =>
      (
        gen_x64(r, {
          lo: 0x0010000000000000UL,
          hi: 0x7fefffffffffffffUL,
          signed: false,
        }),
        0UL,
      )
    "pow" | "pow_generic" => {
      let x = gen_x64(r, {
        lo: 0x3e00000000000000UL,
        hi: 0x4100000000000000UL,
        signed: true,
      })
      let y = gen_y64(r)
      (x, y)
    }
    "powf" | "powf_generic" | "dirty_powf" => {
      let x = gen_x32(r).to_uint64()
      let y = gen_y32(r).to_uint64()
      (x, y)
    }
    "cbrtf" | "cbrtf_generic" => (gen_x32(r).to_uint64(), 0UL)
    _ => abort("unknown variant " + name)
  }
}

///|
test "pxfm fuzz digests match upstream" {
  let full = match @env.get_env_var("PXFM_FUZZ_FULL") {
    Some(v) => v != "" && v != "0"
    None => false
  }
  let mut evaluated = 0
  let failures = []
  for entry in fuzz_digests {
    let (name, seed, digests) = entry
    let r : FuzzRng = { state: seed, }
    let chunks = if full { digests.length() } else { 1 }
    for c in 0..<chunks {
      let mut h = 0xcbf29ce484222325UL
      for _ in 0..<fuzz_chunk_size {
        let (a, b) = fuzz_input(name, r)
        h = (h ^ eval_variant(name, a, b)) * 0x100000001b3UL
      }
      evaluated += fuzz_chunk_size
      if h != digests[c] {
        failures.push("\{name} chunk \{c}")
      }
    }
  }
  println("fuzz inputs evaluated: \{evaluated}")
  if !failures.is_empty() {
    fail("digest mismatch: " + failures.join(", "))
  }
}
