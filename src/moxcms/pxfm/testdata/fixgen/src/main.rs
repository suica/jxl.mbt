//! Fixture / fuzz-digest generator for the MoonBit port `suica/jxl/moxcms/pxfm`.
//!
//! Reference: pxfm 0.1.30 on x86_64 Linux, default rustc flags (no
//! `target_feature = "fma"` at compile time). Functions with runtime dispatch
//! (`f_exp`, `f_exp10`, `f_exp2`, `f_powf`, `f_cbrtf`) pick their AVX+FMA
//! implementation on CPUs that have it; `pxfm_generic` is a copy whose dispatch
//! never does, so it gives what the generic implementation produces.
//!
//! Modes:
//!   fixgen fixtures <out.txt> [mine cap regular]   regular + special + slow-path inputs
//!   fixgen digests <out.mbt> [chunks]              per-chunk FNV digests of the fuzz streams
//!   fixgen dump <variant> <chunk>                  inputs/outputs of one fuzz chunk
//!   fixgen consts                                  print f32 constants used by the port
//!
//! Driven by `../regen.sh`, which vendors the instrumented copies next to
//! this crate (`../vendor/pxfm_instr`, `../vendor/pxfm_generic`).
//!
//! The input generator (`Rng`, `gen_*`) is mirrored exactly by
//! `fuzz_wbtest.mbt` in the MoonBit package.

use std::collections::BTreeMap;
use std::io::Write;

const SIGN64: u64 = 1 << 63;
const CHUNK: usize = 65536;

#[derive(Clone)]
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    fn range(&mut self, lo: u64, hi: u64) -> u64 {
        lo + self.next() % (hi - lo + 1)
    }
}

fn gamma64() -> Vec<u64> {
    let m1 = 2610.0f64 / 16384.0;
    let m2 = 2523.0f64 / 4096.0 * 128.0;
    let v: Vec<f64> = vec![
        2.4,
        1.0 / 2.4,
        1.0 / 0.45,
        0.45,
        2.6,
        1.0 / 2.6,
        m1,
        1.0 / m1,
        m2,
        1.0 / m2,
        1.0 / 78.84375,
        1.0 / 0.1593017578125,
        1.2,
        1.0 / 1.2,
        2.2,
        1.0 / 2.2,
        2.8,
        1.0 / 2.8,
        1.8,
        1.0 / 1.8,
        0.5,
        2.0,
        3.0,
        1.0 / 3.0,
        0.631651345306265,
        0.6523997524738018,
        0.6007557017508491,
        1.33654221029386,
        -2.4,
        -0.45,
        2.19921875,
        1.0 / 2.19921875,
    ];
    v.into_iter().map(f64::to_bits).collect()
}

fn gamma32() -> Vec<u32> {
    let m1 = 2610.0f32 / 16384.0;
    let m2 = 2523.0f32 / 4096.0 * 128.0;
    let v: Vec<f32> = vec![
        2.4,
        1.0 / 2.4,
        1.0 / 0.45,
        0.45,
        2.6,
        1.0 / 2.6,
        m1,
        1.0 / m1,
        m2,
        1.0 / m2,
        (1.0f64 / 2.4) as f32,
        (1.0f64 / 0.45) as f32,
        (1.0f64 / 2.6) as f32,
        1.2,
        1.0 / 1.2,
        2.2,
        1.0 / 2.2,
        2.8,
        1.0 / 2.8,
        0.5,
        2.0,
        3.0,
        1.0 / 3.0,
        0.631651345306265,
        0.6523997524738018,
        0.6007557017508491,
        1.33654221029386,
        -2.4,
        -0.45,
        2.19921875,
    ];
    v.into_iter().map(f32::to_bits).collect()
}

const SPECIAL64: [u64; 30] = [
    0x0000000000000000,
    0x8000000000000000,
    0x7ff0000000000000,
    0xfff0000000000000,
    0x7ff8000000000000,
    0xfff8000000000000,
    0x7ff0000000000001,
    0x3ff0000000000000,
    0xbff0000000000000,
    0x4000000000000000,
    0xc000000000000000,
    0x4024000000000000,
    0xc024000000000000,
    0x3fe0000000000000,
    0xbfe0000000000000,
    0x0000000000000001,
    0x800fffffffffffff,
    0x0010000000000000,
    0x7fefffffffffffff,
    0xffefffffffffffff,
    0x3ff0000000000001,
    0x3fefffffffffffff,
    0x4008000000000000,
    0x4059000000000000,
    0x01a56e1fc2f8f359,
    0x3c90000000000000,
    0x4086232bdd7abcd2,
    0xc086232bdd7abcd2,
    0x40862e42fefa39ef,
    0xc0874910d52d3052,
];

const SPECIAL32: [u32; 26] = [
    0x00000000, 0x80000000, 0x7f800000, 0xff800000, 0x7fc00000, 0xffc00000, 0x7f800001,
    0x3f800000, 0xbf800000, 0x40000000, 0xc0000000, 0x41200000, 0x3f000000, 0xbf000000,
    0x00000001, 0x807fffff, 0x00800000, 0x7f7fffff, 0xff7fffff, 0x3f800001, 0x3f7fffff,
    0x40400000, 0x42c80000, 0x4f170000, 0x4f800000, 0xcf800000,
];

#[derive(Clone, Copy)]
struct Dom {
    lo: u64,
    hi: u64,
    signed: bool,
}

const DOM_EXP: Dom = Dom { lo: 0, hi: 0x4087800000000000, signed: true };
const DOM_EXP10: Dom = Dom { lo: 0, hi: 0x4074800000000000, signed: true };
const DOM_EXP2: Dom = Dom { lo: 0, hi: 0x4091000000000000, signed: true };
const DOM_LOG: Dom = Dom { lo: 0x0010000000000000, hi: 0x7fefffffffffffff, signed: false };
const DOM_POWX: Dom = Dom { lo: 0x3e00000000000000, hi: 0x4100000000000000, signed: true };

fn gen_x64(r: &mut Rng, d: Dom) -> u64 {
    match r.below(12) {
        0 => r.next(),
        1 => r.range(0, 0x3ff0000000000000),
        2 => r.range(1, 0x4000000000000000),
        3 => {
            let b = r.range(d.lo, d.hi);
            let s = r.next() & 1;
            if d.signed && s == 1 { b | SIGN64 } else { b }
        }
        4 => 0x3ff0000000000000u64
            .wrapping_add(r.range(0, 1 << 21))
            .wrapping_sub(1 << 20),
        5 => SPECIAL64[r.below(SPECIAL64.len() as u64) as usize],
        6 => {
            let b = r.range(1, 0xfffffffffffff);
            let s = r.next() & SIGN64;
            b | s
        }
        7 => ((r.range(0, 800) as i64 - 400) as f64).to_bits(),
        8 => (r.range(0, 1 << 24) as f64 / 16777216.0).to_bits(),
        9 => r.range(d.lo, d.hi),
        10 => r.range(0x4300000000000000, 0x7fefffffffffffff),
        _ => r.range(0x0010000000000000, 0x3c90000000000000),
    }
}

fn gen_y64(r: &mut Rng, g: &[u64]) -> u64 {
    match r.below(10) {
        0 | 1 => g[r.below(g.len() as u64) as usize],
        2 => r.next(),
        3 => ((r.range(0, 220) as i64 - 110) as f64).to_bits(),
        4 => {
            let b = r.range(0, 0x4030000000000000);
            let s = r.next() & SIGN64;
            b | s
        }
        5 => SPECIAL64[r.below(SPECIAL64.len() as u64) as usize],
        6 => {
            let b = r.range(0x3c00000000000000, 0x3ff0000000000000);
            let s = r.next() & SIGN64;
            b | s
        }
        7 => {
            let b = r.range(0x4030000000000000, 0x4400000000000000);
            let s = r.next() & SIGN64;
            b | s
        }
        8 => ((r.range(0, 400) as i64 - 200) as f64 + 0.5).to_bits(),
        _ => (1.0 / (r.range(1, 20) as f64)).to_bits(),
    }
}

fn gen_x32(r: &mut Rng) -> u32 {
    match r.below(12) {
        0 => r.next() as u32,
        1 => r.range(0, 0x3f800000) as u32,
        2 => r.range(1, 0x40000000) as u32,
        3 => r.range(0x00800000, 0x7f7fffff) as u32,
        4 => 0x3f800000u32
            .wrapping_add(r.range(0, 1 << 13) as u32)
            .wrapping_sub(1 << 12),
        5 => SPECIAL32[r.below(SPECIAL32.len() as u64) as usize],
        6 => {
            let b = r.range(1, 0x7fffff) as u32;
            let s = (r.next() as u32) & 0x80000000;
            b | s
        }
        7 => ((r.range(0, 800) as i64 - 400) as f32).to_bits(),
        8 => (r.range(0, 65535) as f32 / 65535.0f32).to_bits(),
        9 => (r.range(0, 0x3f800000) as u32) | 0x80000000,
        10 => (r.range(0, 255) as f32 / 255.0f32).to_bits(),
        _ => r.range(0x4b000000, 0x7f7fffff) as u32,
    }
}

fn gen_y32(r: &mut Rng, g: &[u32]) -> u32 {
    match r.below(10) {
        0 | 1 => g[r.below(g.len() as u64) as usize],
        2 => r.next() as u32,
        3 => ((r.range(0, 60) as i64 - 30) as f32).to_bits(),
        4 => {
            let b = r.range(0, 0x41800000) as u32;
            let s = (r.next() as u32) & 0x80000000;
            b | s
        }
        5 => SPECIAL32[r.below(SPECIAL32.len() as u64) as usize],
        6 => {
            let b = r.range(0x30000000, 0x3f800000) as u32;
            let s = (r.next() as u32) & 0x80000000;
            b | s
        }
        7 => {
            let b = r.range(0x41800000, 0x4f800000) as u32;
            let s = (r.next() as u32) & 0x80000000;
            b | s
        }
        8 => ((r.range(0, 400) as i64 - 200) as f32 + 0.5f32).to_bits(),
        _ => (1.0f32 / (r.range(1, 20) as f32)).to_bits(),
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Lib {
    Real,
    Instr,
    Generic,
}

#[derive(Clone, Copy)]
enum Kind {
    U64(Dom),
    B64,
    U32,
    B32,
}

struct Variant {
    name: &'static str,
    kind: Kind,
    generic: bool,
}

const VARIANTS: [Variant; 15] = [
    Variant { name: "exp", kind: Kind::U64(DOM_EXP), generic: false },
    Variant { name: "exp_generic", kind: Kind::U64(DOM_EXP), generic: true },
    Variant { name: "exp10", kind: Kind::U64(DOM_EXP10), generic: false },
    Variant { name: "exp10_generic", kind: Kind::U64(DOM_EXP10), generic: true },
    Variant { name: "exp2", kind: Kind::U64(DOM_EXP2), generic: false },
    Variant { name: "exp2_generic", kind: Kind::U64(DOM_EXP2), generic: true },
    Variant { name: "log", kind: Kind::U64(DOM_LOG), generic: false },
    Variant { name: "log10", kind: Kind::U64(DOM_LOG), generic: false },
    Variant { name: "pow", kind: Kind::B64, generic: false },
    Variant { name: "pow_generic", kind: Kind::B64, generic: true },
    Variant { name: "powf", kind: Kind::B32, generic: false },
    Variant { name: "powf_generic", kind: Kind::B32, generic: true },
    Variant { name: "dirty_powf", kind: Kind::B32, generic: false },
    Variant { name: "cbrtf", kind: Kind::U32, generic: false },
    Variant { name: "cbrtf_generic", kind: Kind::U32, generic: true },
];

fn eval(v: usize, lib: Lib, a: u64, b: u64) -> u64 {
    let lib = if VARIANTS[v].generic && lib == Lib::Real { Lib::Generic } else { lib };
    let fa = f64::from_bits(a);
    let fb = f64::from_bits(b);
    let ga = f32::from_bits(a as u32);
    let gb = f32::from_bits(b as u32);
    macro_rules! pick {
        ($f:ident, $($arg:expr),*) => {
            match lib {
                Lib::Real => pxfm::$f($($arg),*),
                Lib::Instr => pxfm_instr::$f($($arg),*),
                Lib::Generic => pxfm_generic::$f($($arg),*),
            }
        };
    }
    match VARIANTS[v].name.trim_end_matches("_generic") {
        "exp" => pick!(f_exp, fa).to_bits(),
        "exp10" => pick!(f_exp10, fa).to_bits(),
        "exp2" => pick!(f_exp2, fa).to_bits(),
        "log" => pick!(f_log, fa).to_bits(),
        "log10" => pick!(f_log10, fa).to_bits(),
        "pow" => pick!(f_pow, fa, fb).to_bits(),
        "powf" => pick!(f_powf, ga, gb).to_bits() as u64,
        "dirty_powf" => pick!(dirty_powf, ga, gb).to_bits() as u64,
        "cbrtf" => pick!(f_cbrtf, ga).to_bits() as u64,
        n => panic!("{n}"),
    }
}

fn hits(lib: Lib) -> u32 {
    match lib {
        Lib::Instr => pxfm_instr::hits(),
        Lib::Generic => pxfm_generic::hits(),
        Lib::Real => 0,
    }
}

fn reset_hits(lib: Lib) {
    match lib {
        Lib::Instr => pxfm_instr::reset_hits(),
        Lib::Generic => pxfm_generic::reset_hits(),
        Lib::Real => {}
    }
}

fn gen_input(v: usize, r: &mut Rng, g64: &[u64], g32: &[u32]) -> (u64, u64) {
    match VARIANTS[v].kind {
        Kind::U64(d) => (gen_x64(r, d), 0),
        Kind::B64 => {
            let x = gen_x64(r, DOM_POWX);
            let y = gen_y64(r, g64);
            (x, y)
        }
        Kind::U32 => (gen_x32(r) as u64, 0),
        Kind::B32 => {
            let x = gen_x32(r) as u64;
            let y = gen_y32(r, g32) as u64;
            (x, y)
        }
    }
}

fn arity(v: usize) -> usize {
    match VARIANTS[v].kind {
        Kind::U64(_) | Kind::U32 => 1,
        _ => 2,
    }
}

fn fuzz_seed(v: usize) -> u64 {
    0x5eed_0000_0000_0000u64 ^ ((v as u64 + 1) * 0x0100_0000_0001)
}

fn fnv(h: u64, b: u64) -> u64 {
    (h ^ b).wrapping_mul(0x100000001b3)
}

fn digests(out: &str, chunks: usize) {
    let g64 = gamma64();
    let g32 = gamma32();
    let mut s = String::new();
    s.push_str("// Generated by testdata/fixgen (`fixgen digests`). Do not edit.\n");
    s.push_str("// FNV-1a-64 digests of pxfm 0.1.30 outputs over the fuzz input streams.\n\n");
    s.push_str("///|\nlet fuzz_gamma64 : FixedArray[UInt64] = [\n");
    for b in &g64 {
        s.push_str(&format!("  0x{b:016x}UL,\n"));
    }
    s.push_str("]\n\n///|\nlet fuzz_gamma32 : FixedArray[UInt] = [\n");
    for b in &g32 {
        s.push_str(&format!("  0x{b:08x}U,\n"));
    }
    s.push_str("]\n\n///|\nlet fuzz_special64 : FixedArray[UInt64] = [\n");
    for b in &SPECIAL64 {
        s.push_str(&format!("  0x{b:016x}UL,\n"));
    }
    s.push_str("]\n\n///|\nlet fuzz_special32 : FixedArray[UInt] = [\n");
    for b in &SPECIAL32 {
        s.push_str(&format!("  0x{b:08x}U,\n"));
    }
    s.push_str("]\n\n");
    s.push_str(&format!("///|\nlet fuzz_chunk_size : Int = {CHUNK}\n\n"));
    s.push_str("///|\n/// (variant name, seed, per-chunk digests)\nlet fuzz_digests : Array[(String, UInt64, FixedArray[UInt64])] = [\n");
    let handles: Vec<_> = (0..VARIANTS.len())
        .map(|v| {
            let g64 = g64.clone();
            let g32 = g32.clone();
            std::thread::spawn(move || {
                let mut r = Rng(fuzz_seed(v));
                let mut ds = Vec::new();
                for _ in 0..chunks {
                    let mut h = 0xcbf29ce484222325u64;
                    for _ in 0..CHUNK {
                        let (a, b) = gen_input(v, &mut r, &g64, &g32);
                        h = fnv(h, eval(v, Lib::Real, a, b));
                    }
                    ds.push(h);
                }
                ds
            })
        })
        .collect();
    for (v, hd) in handles.into_iter().enumerate() {
        let ds = hd.join().unwrap();
        s.push_str(&format!(
            "  (\"{}\", 0x{:016x}UL, [\n",
            VARIANTS[v].name,
            fuzz_seed(v)
        ));
        for d in ds {
            s.push_str(&format!("    0x{d:016x}UL,\n"));
        }
        s.push_str("  ]),\n");
    }
    s.push_str("]\n");
    std::fs::write(out, s).unwrap();
}

fn dump(name: &str, chunk: usize) {
    let g64 = gamma64();
    let g32 = gamma32();
    let v = VARIANTS.iter().position(|x| x.name == name).unwrap();
    let mut r = Rng(fuzz_seed(v));
    for c in 0..=chunk {
        for i in 0..CHUNK {
            let (a, b) = gen_input(v, &mut r, &g64, &g32);
            if c == chunk {
                println!("{i} {a:016x} {b:016x} {:016x}", eval(v, Lib::Real, a, b));
            }
        }
    }
}

/// Mines inputs that take slow paths, keyed by the hit mask.
fn mine(v: usize, total: u64, cap: usize) -> BTreeMap<u32, Vec<(u64, u64)>> {
    let threads = 46u64;
    let per = total / threads;
    let lib = if VARIANTS[v].generic { Lib::Generic } else { Lib::Instr };
    let handles: Vec<_> = (0..threads)
        .map(|t| {
            std::thread::spawn(move || {
                let g64 = gamma64();
                let g32 = gamma32();
                let mut r = Rng(0x6d69_6e65_0000_0000 ^ ((v as u64) << 40) ^ (t * 0x9e37_79b9));
                let mut m: BTreeMap<u32, Vec<(u64, u64)>> = BTreeMap::new();
                let mut bad = 0u64;
                for _ in 0..per {
                    let (a, b) = gen_input(v, &mut r, &g64, &g32);
                    reset_hits(lib);
                    let o = eval(v, lib, a, b);
                    let h = hits(lib);
                    if h != 0 {
                        if lib == Lib::Instr && o != eval(v, Lib::Real, a, b) {
                            bad += 1;
                        }
                        let e = m.entry(h).or_default();
                        if e.len() < cap {
                            e.push((a, b));
                        }
                    }
                }
                (m, bad)
            })
        })
        .collect();
    let mut all: BTreeMap<u32, Vec<(u64, u64)>> = BTreeMap::new();
    let mut bad = 0;
    for hd in handles {
        let (m, b) = hd.join().unwrap();
        bad += b;
        for (k, vs) in m {
            let e = all.entry(k).or_default();
            for x in vs {
                if e.len() < cap {
                    e.push(x);
                }
            }
        }
    }
    assert_eq!(bad, 0, "instrumented copy disagrees with pxfm");
    all
}

fn fixtures(out: &str, mine_total: u64, cap: usize, regular: usize) {
    let g64 = gamma64();
    let g32 = gamma32();
    let mut f = std::fs::File::create(out).unwrap();
    for v in 0..VARIANTS.len() {
        let mut ins: Vec<(u64, u64)> = Vec::new();
        // specials
        match VARIANTS[v].kind {
            Kind::U64(_) => ins.extend(SPECIAL64.iter().map(|&a| (a, 0))),
            Kind::U32 => ins.extend(SPECIAL32.iter().map(|&a| (a as u64, 0))),
            Kind::B64 => {
                for &a in &SPECIAL64 {
                    for &b in &SPECIAL64 {
                        ins.push((a, b));
                    }
                }
            }
            Kind::B32 => {
                for &a in &SPECIAL32 {
                    for &b in &SPECIAL32 {
                        ins.push((a as u64, b as u64));
                    }
                }
            }
        }
        // regular samples
        let mut r = Rng(0xf1f1_0000_0000_0000 ^ (v as u64 * 0x1_0000_0001));
        for _ in 0..regular {
            ins.push(gen_input(v, &mut r, &g64, &g32));
        }
        // slow paths
        let mined = mine(v, mine_total, cap);
        let mut summary = Vec::new();
        for (k, vs) in &mined {
            summary.push(format!("{k:#x}:{}", vs.len()));
            ins.extend(vs.iter().copied());
        }
        eprintln!("{}: {} inputs; slow-path masks {}", VARIANTS[v].name, ins.len(), summary.join(" "));
        for (a, b) in ins {
            let o = eval(v, Lib::Real, a, b);
            match (VARIANTS[v].kind, arity(v)) {
                (Kind::U64(_), _) => writeln!(f, "{} {a:016x} {o:016x}", VARIANTS[v].name),
                (Kind::B64, _) => writeln!(f, "{} {a:016x} {b:016x} {o:016x}", VARIANTS[v].name),
                (Kind::U32, _) => writeln!(f, "{} {a:08x} {o:08x}", VARIANTS[v].name),
                (Kind::B32, _) => writeln!(f, "{} {a:08x} {b:08x} {o:08x}", VARIANTS[v].name),
            }
            .unwrap();
        }
    }
}

fn consts() {
    let c32: [(&str, f32); 6] = [
        ("dirty_log2f u0", 0.4121985850084821691e+0),
        ("dirty_log2f c1", 0.5770780163490337802e+0),
        ("dirty_log2f c2", 0.9617966939259845749e+0),
        ("dirty_log2f c3", 0.2885390081777926802e+1),
        ("dirty_exp2f u0", 0.24022650695908768),
        ("dirty_exp2f c1", 0.69314718055994973),
    ];
    for (n, x) in c32 {
        println!("{n}: 0x{:08x}", x.to_bits());
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("fixtures") => {
            let mine_total = args.get(3).map(|s| s.parse().unwrap()).unwrap_or(200_000_000);
            let cap = args.get(4).map(|s| s.parse().unwrap()).unwrap_or(80);
            let regular = args.get(5).map(|s| s.parse().unwrap()).unwrap_or(400);
            fixtures(&args[2], mine_total, cap, regular)
        }
        Some("digests") => {
            let chunks = args.get(3).map(|s| s.parse().unwrap()).unwrap_or(16);
            digests(&args[2], chunks)
        }
        Some("dump") => dump(&args[2], args[3].parse().unwrap()),
        Some("consts") => consts(),
        _ => eprintln!("usage: fixgen fixtures|digests|dump|consts ..."),
    }
}
