// Generates MoonBit whitebox parity tests from upstream jxl-oxide behaviour.
// Usage: parity <conformance testcases dir> <test-profiles dir> <out color wbtest> <out image wbtest>
use std::fmt::Write as _;
use std::panic::{AssertUnwindSafe, catch_unwind};

use jxl_bitstream::Bitstream;
use jxl_color::{
    ColorEncodingWithProfile, ColourEncoding, ColourSpace, Customxy, EnumColourEncoding, Primaries,
    RenderingIntent, TransferFunction, WhitePoint,
};
use jxl_image::{BitDepth, ExtraChannelType, ImageHeader};
use jxl_oxide_common::Bundle;

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

fn fnv(s: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in s {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("\\x{x:02x}")).collect()
}

fn norm_bs(e: &jxl_bitstream::Error) -> String {
    use jxl_bitstream::Error::*;
    match e {
        Io(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => "Eof".into(),
        Io(_) => "Io".into(),
        InvalidBox => "InvalidBox".into(),
        NonZeroPadding => "NonZeroPadding".into(),
        InvalidFloat => "InvalidFloat".into(),
        InvalidEnum { name, value } => format!("InvalidEnum({name},{value})"),
        ValidationFailed(s) => format!("ValidationFailed({s})"),
        ProfileConformance(s) => format!("ProfileConformance({s})"),
        CannotSkip => "CannotSkip".into(),
        NotAligned => "NotAligned".into(),
        _ => "Other".into(),
    }
}

fn norm_color(e: &jxl_color::Error) -> String {
    use jxl_color::Error::*;
    match e {
        Bitstream(b) => norm_bs(b),
        Decoder(jxl_coding::Error::Bitstream(b)) => norm_bs(b),
        Decoder(_) => "Decoder".into(),
        InvalidIccStream(s) => format!("InvalidIccStream: {s}"),
        IccParseFailure(s) => format!("IccParseFailure: {s}"),
        UnsupportedIccProfile => "UnsupportedIccProfile".into(),
        e => format!("{e:?}"),
    }
}

fn mbt_xy(c: &Customxy) -> String {
    format!("{{ x: {}, y: {} }}", c.x, c.y)
}

fn mbt_enc(e: &EnumColourEncoding) -> String {
    let cs = format!("{:?}", e.colour_space);
    let wp = match e.white_point {
        WhitePoint::Custom(c) => format!("Custom({})", mbt_xy(&c)),
        w => format!("{w:?}"),
    };
    let pr = match e.primaries {
        Primaries::Custom { red, green, blue } => format!(
            "Custom(red={}, green={}, blue={})",
            mbt_xy(&red),
            mbt_xy(&green),
            mbt_xy(&blue)
        ),
        p => format!("{p:?}"),
    };
    let tf = match e.tf {
        TransferFunction::Gamma { g, inverted } => format!("Gamma(g={g}, inverted={inverted})"),
        t => format!("{t:?}"),
    };
    format!(
        "{{ colour_space: {cs}, white_point: {wp}, primaries: {pr}, tf: {tf}, rendering_intent: {:?} }}",
        e.rendering_intent
    )
}

fn f(x: f32) -> String {
    format!("{:08x}", x.to_bits())
}

fn bd(b: &BitDepth) -> String {
    match b {
        BitDepth::IntegerSample { bits_per_sample } => format!("I{bits_per_sample}"),
        BitDepth::FloatSample {
            bits_per_sample,
            exp_bits,
        } => format!("F{bits_per_sample}/{exp_bits}"),
    }
}

fn header_summary(h: &ImageHeader, bits: usize) -> String {
    let m = &h.metadata;
    let mut ec = String::new();
    for e in &m.ec_info {
        let ty = match e.ty {
            ExtraChannelType::Alpha { alpha_associated } => format!("Alpha({alpha_associated})"),
            ExtraChannelType::Depth => "Depth".into(),
            ExtraChannelType::SpotColour {
                red,
                green,
                blue,
                solidity,
            } => format!("Spot({},{},{},{})", f(red), f(green), f(blue), f(solidity)),
            ExtraChannelType::SelectionMask => "SelectionMask".into(),
            ExtraChannelType::Black => "Black".into(),
            ExtraChannelType::Cfa { cfa_channel } => format!("Cfa({cfa_channel})"),
            ExtraChannelType::Thermal => "Thermal".into(),
            ExtraChannelType::NonOptional => "NonOptional".into(),
            ExtraChannelType::Optional => "Optional".into(),
        };
        let name: String = e.name.bytes().map(|b| format!("{b:02x}")).collect();
        write!(ec, "{ty}:{}:{}:{name};", bd(&e.bit_depth), e.dim_shift).unwrap();
    }
    let tm = &m.tone_mapping;
    let intr = m
        .intrinsic_size
        .as_ref()
        .map(|s| format!("{}x{}", s.width, s.height))
        .unwrap_or("-".into());
    let prev = m
        .preview
        .as_ref()
        .map(|s| format!("{}x{}", s.width, s.height))
        .unwrap_or("-".into());
    let anim = m
        .animation
        .as_ref()
        .map(|a| {
            format!(
                "{}/{}/{}/{}",
                a.tps_numerator, a.tps_denominator, a.num_loops, a.have_timecodes
            )
        })
        .unwrap_or("-".into());
    let oim = &m.opsin_inverse_matrix;
    let mut o = String::new();
    for r in &oim.inv_mat {
        for v in r {
            o += &f(*v);
        }
    }
    for v in oim.opsin_bias.iter().chain(oim.quant_bias.iter()) {
        o += &f(*v);
    }
    o += &f(oim.quant_bias_numerator);
    let mut up = String::new();
    for v in m
        .up2_weight
        .iter()
        .chain(m.up4_weight.iter())
        .chain(m.up8_weight.iter())
    {
        up += &f(*v);
    }
    format!(
        "W={} H={} OW={} OH={} O={} BD={} EC=[{ec}] M16={} XYB={} CE={} TM={},{},{},{} INTR={intr} PREV={prev} ANIM={anim} OIM={o} UP={:016x} GRAY={} ALPHA={:?} BITS={bits}",
        h.size.width,
        h.size.height,
        h.width_with_orientation(),
        h.height_with_orientation(),
        m.orientation,
        bd(&m.bit_depth),
        m.modular_16bit_buffers,
        m.xyb_encoded,
        ce_str(&m.colour_encoding),
        f(tm.intensity_target),
        f(tm.min_nits),
        tm.relative_to_max_display,
        f(tm.linear_below),
        fnv(up.as_bytes()),
        m.grayscale(),
        m.alpha(),
    )
}

fn ce_str(c: &ColourEncoding) -> String {
    match c {
        ColourEncoding::Enum(e) => format!("Enum({e:?})"),
        ColourEncoding::IccProfile(cs) => format!("IccProfile({cs:?})"),
    }
}

fn extract_codestream(data: &[u8]) -> Vec<u8> {
    if data.len() >= 2 && data[0] == 0xff && data[1] == 0x0a {
        return data.to_vec();
    }
    let mut out = Vec::new();
    let mut pos = 0usize;
    while pos + 8 <= data.len() {
        let mut size = u32::from_be_bytes(data[pos..pos + 4].try_into().unwrap()) as u64;
        let ty = &data[pos + 4..pos + 8];
        let mut header = 8;
        if size == 1 {
            size = u64::from_be_bytes(data[pos + 8..pos + 16].try_into().unwrap());
            header = 16;
        } else if size == 0 {
            size = (data.len() - pos) as u64;
        }
        let end = pos + size as usize;
        if ty == b"jxlc" {
            out.extend_from_slice(&data[pos + header..end]);
        } else if ty == b"jxlp" {
            out.extend_from_slice(&data[pos + header + 4..end]);
        }
        pos = end;
    }
    out
}

fn catch<T>(f: impl FnOnce() -> T) -> Option<T> {
    catch_unwind(AssertUnwindSafe(f)).ok()
}

/// Expected value literal: full string for base cases, hash for mutated ones, "PANIC" if upstream panics.
fn expect_lit(r: Option<String>, full: bool) -> String {
    match r {
        None => "Panic".into(),
        Some(s) if full => format!("Full({:?})", s),
        Some(s) => format!("Hash(0x{:016x}UL)", fnv(s.as_bytes())),
    }
}

fn mutations(rng: &mut Rng, len: usize, lo: usize, n: usize) -> Vec<Vec<(usize, u8)>> {
    let mut all = Vec::new();
    if len <= lo {
        return all;
    }
    for _ in 0..n {
        let k = 1 + rng.below(3);
        let mut m = Vec::new();
        for _ in 0..k {
            let off = lo + rng.below(len - lo);
            let mask = if rng.below(2) == 0 {
                1u8 << rng.below(8)
            } else {
                (1 + rng.below(255)) as u8
            };
            m.push((off, mask));
        }
        all.push(m);
    }
    all
}

fn apply(b: &[u8], m: &[(usize, u8)]) -> Vec<u8> {
    let mut v = b.to_vec();
    for &(o, x) in m {
        v[o] ^= x;
    }
    v
}

fn mut_lit(m: &[(usize, u8)]) -> String {
    let parts: Vec<String> = m.iter().map(|(o, x)| format!("({o}, {x})")).collect();
    format!("[{}]", parts.join(", "))
}

fn icc_parse_outcome(icc: &[u8]) -> String {
    match ColorEncodingWithProfile::with_icc(icc) {
        Ok(e) => ce_str(e.encoding()),
        Err(e) => format!("ERR:{}", norm_color(&e)),
    }
}

fn decode_outcome(s: &[u8]) -> String {
    match jxl_color::icc::decode_icc(s) {
        Ok(v) => format!("OK {} {:016x}", v.len(), fnv(&v)),
        Err(e) => format!("ERR:{}", norm_color(&e)),
    }
}

fn read_outcome(cs: &[u8]) -> String {
    let mut bs = Bitstream::new(cs);
    let h = match ImageHeader::parse(&mut bs, ()) {
        Ok(h) => h,
        Err(e) => return format!("HDR:{}", norm_bs(&e)),
    };
    if !h.metadata.colour_encoding.want_icc() {
        return "NOICC".into();
    }
    match jxl_color::icc::read_icc(&mut bs) {
        Ok(v) => format!("OK {} {:016x} {}", v.len(), fnv(&v), bs.num_read_bits()),
        Err(e) => format!("ERR:{}", norm_color(&e)),
    }
}

fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    let args: Vec<String> = std::env::args().collect();
    let conf = &args[1];
    let profiles_dir = &args[2];
    let mut rng = Rng(0x9e3779b97f4a7c15);

    // ---------------- color ----------------
    let mut c = String::new();
    c += "// GENERATED by scratch-colorhdr/parity from upstream jxl-oxide (jxl-color 0.11.0); do not edit.\n";
    c += "// Expected outcomes of upstream code on the same inputs (release build).\n\n";

    // synthesis cases
    let wps = [
        WhitePoint::D65,
        WhitePoint::E,
        WhitePoint::Dci,
        WhitePoint::Custom(Customxy { x: 312700, y: 329000 }),
        WhitePoint::Custom(Customxy { x: 345700, y: 358500 }),
    ];
    let prs = [
        Primaries::Srgb,
        Primaries::Bt2100,
        Primaries::P3,
        Primaries::Custom {
            red: Customxy { x: 734700, y: 265300 },
            green: Customxy { x: 159600, y: 840400 },
            blue: Customxy { x: 36600, y: 100 },
        },
    ];
    let tfs = [
        TransferFunction::Gamma {
            g: 22000000,
            inverted: false,
        },
        TransferFunction::Gamma {
            g: 4545455,
            inverted: true,
        },
        TransferFunction::Bt709,
        TransferFunction::Linear,
        TransferFunction::Srgb,
        TransferFunction::Pq,
        TransferFunction::Dci,
        TransferFunction::Hlg,
    ];
    let ris = [
        RenderingIntent::Perceptual,
        RenderingIntent::Relative,
        RenderingIntent::Saturation,
        RenderingIntent::Absolute,
    ];
    let mut synth: Vec<(EnumColourEncoding, Vec<u8>)> = Vec::new();
    let mut i = 0;
    for cs in [ColourSpace::Rgb, ColourSpace::Grey] {
        for wp in wps {
            for pr in prs {
                for tf in tfs {
                    let e = EnumColourEncoding {
                        colour_space: cs,
                        white_point: wp,
                        primaries: pr,
                        tf,
                        rendering_intent: ris[i % 4],
                    };
                    i += 1;
                    let icc = jxl_color::icc::colour_encoding_to_icc(&e);
                    synth.push((e, icc));
                }
            }
        }
    }
    c += "///|\nlet parity_synth : Array[(EnumColourEncoding, Int, UInt64, Expect)] = [\n";
    for (e, icc) in &synth {
        let parsed = icc_parse_outcome(icc);
        writeln!(
            c,
            "  ({}, {}, 0x{:016x}UL, {}),",
            mbt_enc(e),
            icc.len(),
            fnv(icc),
            expect_lit(Some(format!("{parsed}|{:?}", jxl_color::icc::icc_tf(icc))), false)
        )
        .unwrap();
    }
    c += "]\n\n";

    // ICC profile parsing: test profiles, mutated
    let mut names: Vec<String> = std::fs::read_dir(profiles_dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .collect();
    names.sort();
    c += "///|\nlet parity_icc_parse : Array[(Bytes, Array[(Int, Int)], Expect)] = [\n";
    for name in &names {
        let b = std::fs::read(format!("{profiles_dir}/{name}")).unwrap();
        let var = format!("profile_{}", name.replace('-', "_").replace(".icc", ""));
        let base = catch(|| format!("{}|{:?}", icc_parse_outcome(&b), jxl_color::icc::icc_tf(&b)));
        writeln!(c, "  ({var}, [], {}),", expect_lit(base, true)).unwrap();
        // header-area and tag-table-area mutations, plus anywhere
        let tag_end = 0x84 + 12 * u32::from_be_bytes(b[0x80..0x84].try_into().unwrap()) as usize;
        let mut ms = mutations(&mut rng, 0x84.min(b.len()), 0, 40);
        ms.extend(mutations(&mut rng, tag_end.min(b.len()), 0x80, 60));
        ms.extend(mutations(&mut rng, b.len(), 0, 100));
        for m in ms {
            let v = apply(&b, &m);
            let r = catch(|| format!("{}|{:?}", icc_parse_outcome(&v), jxl_color::icc::icc_tf(&v)));
            writeln!(c, "  ({var}, {}, {}),", mut_lit(&m), expect_lit(r, false)).unwrap();
        }
    }
    c += "]\n\n";

    // ICC stream decoding / reading: conformance codestreams with embedded ICC
    let mut cases: Vec<String> = std::fs::read_dir(conf)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| std::path::Path::new(&format!("{conf}/{n}/input.jxl")).exists())
        .collect();
    cases.sort();
    let mut streams = String::new();
    let mut dec = String::new();
    let mut rd = String::new();
    let mut sid = 0;
    for name in &cases {
        let cs = extract_codestream(&std::fs::read(format!("{conf}/{name}/input.jxl")).unwrap());
        let mut bs = Bitstream::new(&cs);
        let h = ImageHeader::parse(&mut bs, ()).unwrap();
        if !h.metadata.colour_encoding.want_icc() {
            continue;
        }
        let header_bits = bs.num_read_bits();
        let enc = jxl_color::icc::read_icc(&mut bs).unwrap();
        if enc.len() > 3000 {
            continue;
        }
        let end_byte = bs.num_read_bits().div_ceil(8) + 16;
        let prefix = &cs[..end_byte.min(cs.len())];
        writeln!(streams, "///|\nlet parity_enc_{sid} : Bytes = b\"{}\"\n", hex(&enc)).unwrap();
        writeln!(streams, "///|\nlet parity_cs_{sid} : Bytes = b\"{}\"\n", hex(prefix)).unwrap();
        // decode_icc
        writeln!(
            dec,
            "  (parity_enc_{sid}, [], {}),",
            expect_lit(catch(|| decode_outcome(&enc)), true)
        )
        .unwrap();
        let mut ms = mutations(&mut rng, enc.len(), 0, 120);
        ms.extend(mutations(&mut rng, enc.len().min(24), 0, 40));
        for m in ms {
            let v = apply(&enc, &m);
            writeln!(
                dec,
                "  (parity_enc_{sid}, {}, {}),",
                mut_lit(&m),
                expect_lit(catch(|| decode_outcome(&v)), false)
            )
            .unwrap();
        }
        // read_icc
        writeln!(
            rd,
            "  (parity_cs_{sid}, [], {}),",
            expect_lit(catch(|| read_outcome(prefix)), true)
        )
        .unwrap();
        for m in mutations(&mut rng, prefix.len(), header_bits / 8, 60) {
            let v = apply(prefix, &m);
            writeln!(
                rd,
                "  (parity_cs_{sid}, {}, {}),",
                mut_lit(&m),
                expect_lit(catch(|| read_outcome(&v)), false)
            )
            .unwrap();
        }
        sid += 1;
    }
    c += &streams;
    c += "///|\nlet parity_icc_decode : Array[(Bytes, Array[(Int, Int)], Expect)] = [\n";
    c += &dec;
    c += "]\n\n///|\nlet parity_icc_read : Array[(Bytes, Array[(Int, Int)], Expect)] = [\n";
    c += &rd;
    c += "]\n";
    std::fs::write(&args[3], c).unwrap();

    // ---------------- image ----------------
    let mut im = String::new();
    im += "// GENERATED by scratch-colorhdr/parity from upstream jxl-oxide (jxl-image 0.13.0); do not edit.\n";
    im += "// Expected outcomes of upstream `ImageHeader::parse` on conformance headers, plain and mutated.\n\n";
    let mut list = String::new();
    for (idx, name) in cases.iter().enumerate() {
        let cs = extract_codestream(&std::fs::read(format!("{conf}/{name}/input.jxl")).unwrap());
        let prefix = &cs[..cs.len().min(80)];
        writeln!(im, "///|\nlet parity_hdr_{idx} : Bytes = b\"{}\"\n", hex(prefix)).unwrap();
        let outcome = |b: &[u8]| -> String {
            let mut bs = Bitstream::new(b);
            match ImageHeader::parse(&mut bs, ()) {
                Ok(h) => header_summary(&h, bs.num_read_bits()),
                Err(e) => format!("ERR:{}", norm_bs(&e)),
            }
        };
        writeln!(
            list,
            "  (parity_hdr_{idx}, [], {}),",
            expect_lit(catch(|| outcome(prefix)), true)
        )
        .unwrap();
        let mut ms = mutations(&mut rng, prefix.len().min(40), 2, 80);
        ms.extend(mutations(&mut rng, prefix.len(), 2, 20));
        for m in ms {
            let v = apply(prefix, &m);
            writeln!(
                list,
                "  (parity_hdr_{idx}, {}, {}),",
                mut_lit(&m),
                expect_lit(catch(|| outcome(&v)), false)
            )
            .unwrap();
        }
    }
    im += "///|\nlet parity_headers : Array[(Bytes, Array[(Int, Int)], Expect)] = [\n";
    im += &list;
    im += "]\n";
    std::fs::write(&args[4], im).unwrap();
}
