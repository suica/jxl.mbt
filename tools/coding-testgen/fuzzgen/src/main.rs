// Differential test generator: runs upstream jxl-coding on pseudo-random
// bitstreams and emits a MoonBit test file with inputs and expected hashes.
use jxl_bitstream::Bitstream;
use jxl_coding::{read_clusters, read_permutation, Decoder, Error, RleToken};

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 >> 16) as u32
    }
}

fn err_codes(e: &Error) -> Vec<u32> {
    let base = 0xdead0000u32;
    match e {
        Error::Bitstream(_) => vec![base + 1],
        Error::Lz77NotAllowed => vec![base + 2],
        Error::InvalidAnsHistogram => vec![base + 3],
        Error::InvalidAnsStream => vec![base + 4],
        Error::InvalidIntegerConfig { split_exponent, msb_in_token, lsb_in_token } => {
            vec![base + 5, *split_exponent, *msb_in_token, lsb_in_token.unwrap_or(0xffffffff)]
        }
        Error::InvalidPermutation => vec![base + 6],
        Error::InvalidPrefixHistogram => vec![base + 7],
        Error::PrefixSymbolTooLarge(n) => vec![base + 8, *n as u32],
        Error::InvalidCluster(id) => vec![base + 9, *id],
        Error::ClusterHole { num_expected_clusters, num_actual_clusters } => {
            vec![base + 10, *num_expected_clusters, *num_actual_clusters]
        }
        Error::UnexpectedLz77Repeat => vec![base + 11],
        Error::InvalidLz77Symbol => vec![base + 12],
        _ => vec![base + 99],
    }
}

const K: u32 = 200;

fn ctx_of(j: u32, num_dist: u32) -> u32 {
    (j * 7 + j / 3) % num_dist
}
fn mult_of(j: u32) -> u32 {
    if j % 3 == 0 { 0 } else { j % 5 + 1 }
}

fn run(bytes: &[u8], mode: u32, num_dist: u32, p1: u32, p2: u32, log: &mut Vec<u32>) -> bool {
    let mut bs = Bitstream::new(bytes);
    let fail = |log: &mut Vec<u32>, e: Error| log.extend(err_codes(&e));
    match mode {
        0 | 1 => {
            let mut dec = match Decoder::parse(&mut bs, num_dist) {
                Ok(d) => d,
                Err(e) => {
                    fail(log, e);
                    return false;
                }
            };
            log.push(bs.num_read_bits() as u32);
            let map = dec.cluster_map().to_vec();
            for &c in &map {
                log.push(c as u32);
                log.push(dec.single_token(c).unwrap_or(0xffffffff));
            }
            if mode == 0 {
                if p1 & 1 == 1 {
                    if let Err(e) = dec.begin(&mut bs) {
                        fail(log, e);
                        return true;
                    }
                }
                for j in 0..K {
                    if j == K / 2 {
                        let mut d2 = dec.clone();
                        let mut b2 = bs.clone();
                        for jj in 0..5 {
                            match d2.read_varint_with_multiplier(&mut b2, ctx_of(jj + 3, num_dist), mult_of(jj)) {
                                Ok(v) => log.push(v),
                                Err(e) => {
                                    fail(log, e);
                                    break;
                                }
                            }
                        }
                    }
                    let r = if p2 & 1 == 1 {
                        let cl = map[ctx_of(j, num_dist) as usize];
                        dec.read_varint_with_multiplier_clustered(&mut bs, cl, mult_of(j))
                    } else {
                        dec.read_varint_with_multiplier(&mut bs, ctx_of(j, num_dist), mult_of(j))
                    };
                    match r {
                        Ok(v) => log.push(v),
                        Err(e) => {
                            fail(log, e);
                            return true;
                        }
                    }
                }
                log.push(bs.num_read_bits() as u32);
                match dec.finalize() {
                    Ok(()) => log.push(1),
                    Err(e) => fail(log, e),
                }
            } else {
                if let Some(mut rle) = dec.as_rle() {
                    log.push(0x11);
                    for j in 0..K {
                        let cl = map[ctx_of(j, num_dist) as usize];
                        match rle.read_varint_clustered(&mut bs, cl) {
                            Ok(RleToken::Value(v)) => {
                                log.push(0);
                                log.push(v)
                            }
                            Ok(RleToken::Repeat(v)) => {
                                log.push(1);
                                log.push(v)
                            }
                            Err(e) => {
                                fail(log, e);
                                return true;
                            }
                        }
                    }
                } else if let Some(mut d) = dec.as_with_lz77() {
                    log.push(0x22);
                    for j in 0..K {
                        let cl = map[ctx_of(j, num_dist) as usize];
                        match d.read_varint_with_multiplier_clustered(&mut bs, cl, mult_of(j)) {
                            Ok(v) => log.push(v),
                            Err(e) => {
                                fail(log, e);
                                return true;
                            }
                        }
                    }
                } else if let Some(mut d) = dec.as_no_lz77() {
                    log.push(0x33);
                    for j in 0..K {
                        let cl = map[ctx_of(j, num_dist) as usize];
                        log.push(d.single_token(cl).unwrap_or(0xffffffff));
                        match d.read_varint_clustered(&mut bs, cl) {
                            Ok(v) => log.push(v),
                            Err(e) => {
                                fail(log, e);
                                return true;
                            }
                        }
                    }
                }
                log.push(bs.num_read_bits() as u32);
            }
            true
        }
        2 => {
            let mut dec = match Decoder::parse(&mut bs, 8) {
                Ok(d) => d,
                Err(e) => {
                    fail(log, e);
                    return false;
                }
            };
            let size = 1 + p1 % 300;
            let skip = p2 % (size + 1);
            match read_permutation(&mut bs, &mut dec, size, skip) {
                Ok(p) => {
                    log.push(p.len() as u32);
                    for v in p {
                        log.push(v as u32);
                    }
                }
                Err(e) => fail(log, e),
            }
            log.push(bs.num_read_bits() as u32);
            true
        }
        _ => {
            match read_clusters(&mut bs, num_dist) {
                Ok((n, map)) => {
                    log.push(n);
                    for v in map {
                        log.push(v as u32);
                    }
                }
                Err(e) => {
                    fail(log, e);
                    return false;
                }
            }
            log.push(bs.num_read_bits() as u32);
            true
        }
    }
}

fn fnv(log: &[u32]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &v in log {
        for i in 0..4 {
            h ^= ((v >> (8 * i)) & 0xff) as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
    }
    h
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let want: usize = args.get(1).map(|s| s.parse().unwrap()).unwrap_or(300);
    let seed: u64 = args.get(2).map(|s| s.parse().unwrap()).unwrap_or(12345);
    let mut rng = Rng(seed);
    let mut out = Vec::new();
    let mut ok_count = [0usize; 4];
    let mut tries = 0;
    while out.len() < want && tries < 2_000_000 {
        tries += 1;
        let mode = rng.next() % 4;
        let len = 16 + rng.next() as usize % 240;
        let sparse = rng.next() % 3;
        let mut bytes = vec![0u8; len];
        for b in &mut bytes {
            let mut v = rng.next() as u8;
            for _ in 0..sparse {
                v &= rng.next() as u8;
            }
            *b = v;
        }
        let num_dist = match rng.next() % 4 {
            0 => 1,
            1 => 2,
            2 => 1 + rng.next() % 8,
            _ => 1 + rng.next() % 64,
        };
        let p1 = rng.next();
        let p2 = rng.next();
        let mut log = Vec::new();
        let res = std::panic::catch_unwind(|| {
            let mut log = Vec::new();
            let ok = run(&bytes, mode, num_dist, p1, p2, &mut log);
            (ok, log)
        });
        let (ok, l) = match res {
            Ok(x) => x,
            Err(_) => continue,
        };
        log.extend(l);
        // keep all successful parses, and a few failures
        if !ok && rng.next() % 50 != 0 {
            continue;
        }
        if ok {
            ok_count[mode as usize] += 1;
        }
        let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        out.push(format!(
            "  (\"{hex}\", {mode}, {num_dist}, {p1}U, {p2}U, {}, 0x{:016x}UL),",
            log.len(),
            fnv(&log)
        ));
    }
    eprintln!("tries {tries}, ok per mode {ok_count:?}");
    println!("// Generated by scratch-coding/fuzz (upstream jxl-coding run on pseudo-random input).");
    println!("// (input hex, mode, num_dist, p1, p2, log length, FNV-1a hash of log)");
    println!();
    println!("///|");
    println!("let fuzz_cases : Array[(String, Int, Int, UInt, UInt, Int, UInt64)] = [");
    for l in out {
        println!("{l}");
    }
    println!("]");
}
