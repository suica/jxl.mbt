// Upstream parity test: the expected outcomes in header_parity_data_wbtest.mbt were produced by
// running upstream `ImageHeader::parse` (jxl-image 0.13.0, release build) on the first bytes of
// every conformance codestream, plain and with random bit flips
// (generator: scratch-colorhdr/parity in the session workspace).

///|
priv enum Expect {
  Full(String)
  Hash(UInt64)
  Panic
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
fn hex_n(v : UInt64, n : Int32) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder::new()
  for i in 0..<n {
    let d = ((v >> (4 * (n - 1 - i))) & 0xf).to_int()
    buf.write_char(digits.code_unit_at(d).to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
fn fbits(x : Float) -> String {
  hex_n(x.reinterpret_as_uint().to_uint64(), 8)
}

///|
fn norm_err(e : Error) -> String {
  match e {
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
fn bd_str(b : BitDepth) -> String {
  match b {
    IntegerSample(bits_per_sample~) => "I\{bits_per_sample}"
    FloatSample(bits_per_sample~, exp_bits~) =>
      "F\{bits_per_sample}/\{exp_bits}"
  }
}

///|
fn xy_debug(c : Customxy) -> String {
  "Customxy { x: \{c.x}, y: \{c.y} }"
}

///|
/// Rust `{:?}` of `ColourEncoding`.
fn ce_debug(c : ColourEncoding) -> String {
  let cs = (s : ColourSpace) => {
    match s {
      Rgb => "Rgb"
      Grey => "Grey"
      Xyb => "Xyb"
      Unknown => "Unknown"
    }
  }
  match c {
    IccProfile(s) => "IccProfile(\{cs(s)})"
    Enum(e) => {
      let wp = match e.white_point {
        D65 => "D65"
        Custom(xy) => "Custom(\{xy_debug(xy)})"
        E => "E"
        Dci => "Dci"
      }
      let pr = match e.primaries {
        Srgb => "Srgb"
        Custom(red~, green~, blue~) =>
          "Custom { red: \{xy_debug(red)}, green: \{xy_debug(green)}, blue: \{xy_debug(blue)} }"
        Bt2100 => "Bt2100"
        P3 => "P3"
      }
      let tf = match e.tf {
        Gamma(g~, inverted~) => "Gamma { g: \{g}, inverted: \{inverted} }"
        Bt709 => "Bt709"
        Unknown => "Unknown"
        Linear => "Linear"
        Srgb => "Srgb"
        Pq => "Pq"
        Dci => "Dci"
        Hlg => "Hlg"
      }
      let ri = match e.rendering_intent {
        Perceptual => "Perceptual"
        Relative => "Relative"
        Saturation => "Saturation"
        Absolute => "Absolute"
      }
      "Enum(EnumColourEncoding { colour_space: \{cs(e.colour_space)}, white_point: \{wp}, primaries: \{pr}, tf: \{tf}, rendering_intent: \{ri} })"
    }
  }
}

///|
fn header_summary(h : ImageHeader, bits : Int32) -> String {
  let m = h.metadata
  let ec = StringBuilder::new()
  for e in m.ec_info {
    let ty = match e.ty {
      Alpha(alpha_associated~) => "Alpha(\{alpha_associated})"
      Depth => "Depth"
      SpotColour(red~, green~, blue~, solidity~) =>
        "Spot(\{fbits(red)},\{fbits(green)},\{fbits(blue)},\{fbits(solidity)})"
      SelectionMask => "SelectionMask"
      Black => "Black"
      Cfa(cfa_channel~) => "Cfa(\{cfa_channel})"
      Thermal => "Thermal"
      NonOptional => "NonOptional"
      Optional => "Optional"
    }
    let name = StringBuilder::new()
    for b in @utf8.encode(e.name) {
      name.write_string(hex_n(b.to_uint64(), 2))
    }
    ec.write_string("\{ty}:\{bd_str(e.bit_depth)}:\{e.dim_shift}:\{name};")
  }
  let tm = m.tone_mapping
  let size_str = (w : Int32, hh : Int32) => {
    "\{w.reinterpret_as_uint()}x\{hh.reinterpret_as_uint()}"
  }
  let intr = match m.intrinsic_size {
    Some(s) => size_str(s.width, s.height)
    None => "-"
  }
  let prev = match m.preview {
    Some(s) => size_str(s.width, s.height)
    None => "-"
  }
  let anim = match m.animation {
    Some(a) =>
      "\{a.tps_numerator}/\{a.tps_denominator}/\{a.num_loops}/\{a.have_timecodes}"
    None => "-"
  }
  let oim = m.opsin_inverse_matrix
  let o = StringBuilder::new()
  for r in oim.inv_mat {
    for v in r {
      o.write_string(fbits(v))
    }
  }
  for v in oim.opsin_bias {
    o.write_string(fbits(v))
  }
  for v in oim.quant_bias {
    o.write_string(fbits(v))
  }
  o.write_string(fbits(oim.quant_bias_numerator))
  let up = StringBuilder::new()
  for w in [m.up2_weight, m.up4_weight, m.up8_weight] {
    for v in w {
      up.write_string(fbits(v))
    }
  }
  let alpha = match m.alpha() {
    Some(i) => "Some(\{i})"
    None => "None"
  }
  let u = (x : Int32) => x.reinterpret_as_uint().to_string()
  "W=\{u(h.size.width)} H=\{u(h.size.height)} OW=\{u(h.width_with_orientation())} OH=\{u(h.height_with_orientation())} O=\{m.orientation} BD=\{bd_str(m.bit_depth)} EC=[\{ec}] M16=\{m.modular_16bit_buffers} XYB=\{m.xyb_encoded} CE=\{ce_debug(m.colour_encoding)} TM=\{fbits(tm.intensity_target)},\{fbits(tm.min_nits)},\{tm.relative_to_max_display},\{fbits(tm.linear_below)} INTR=\{intr} PREV=\{prev} ANIM=\{anim} OIM=\{o} UP=\{hex_n(fnv_str(up.to_string()), 16)} GRAY=\{m.grayscale()} ALPHA=\{alpha} BITS=\{bits}"
}

///|
fn header_outcome(b : Bytes) -> String {
  let bs = @bitstream.Bitstream::new(b)
  try ImageHeader::parse(bs) catch {
    e => "ERR:" + norm_err(e)
  } noraise {
    h => header_summary(h, bs.num_read_bits())
  }
}

///|
test "parity: ImageHeader::parse on conformance headers" {
  let mut skipped = 0
  for i, c in parity_headers {
    let (input, m, expect) = c
    let v = input.to_fixedarray()
    for x in m {
      let (o, mask) = x
      v[o] = (v[o].to_int() ^ mask).to_byte()
    }
    let outcome = header_outcome(Bytes::from_fixedarray(v))
    match expect {
      Full(s) => assert_eq(outcome, s, msg="header #\{i} \{m}")
      Hash(h) =>
        if fnv_str(outcome) != h {
          fail("header #\{i} \{m}: outcome differs from upstream: \{outcome}")
        }
      Panic => skipped += 1
    }
  }
  println(
    "ImageHeader::parse: \{parity_headers.length() - skipped} cases match upstream",
  )
}
