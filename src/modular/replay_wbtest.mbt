// Replays modular streams dumped from an instrumented jxl-oxide (the same
// calls jxl-frame and jxl-render make for Modular frames) and compares the
// final channel hashes with jxl-oxide's.
//
// Record format (one per line):
//   G node_limit group_dim bit_depth allow_partial nbits hex ch...
//     (GlobalModular; ch = w:h:S:n | w:h:R:h:v | w:h:J:hh:h:hv:v)
//   S pass:minshift:maxshift ...   (prepare_groups)
//   L lf_group_idx stream_index allow_partial nbits hex
//   P pass_idx group_idx stream_index allow_partial nbits hex
//   F n w:h:hash ...                (channels after the final inverse transforms)
//   V stream_index allow_partial nbits hex group_dim bit_depth ch...
//     (a standalone Modular image of VarDCT: LF quant, HF metadata, raw
//     dequant matrices; Modular::parse, prepare_subimage, decode, finish)
//   W n w:h:hash ...                (channels of the last V image)

///|
fn hex_to_bytes(s : StringView) -> Bytes {
  let n = s.length() / 2
  let out = FixedArray::make(n, b'\x00')
  fn nibble(c : Char) -> Int32 {
    let c = c.to_int()
    if c >= '0'.to_int() && c <= '9'.to_int() {
      c - '0'.to_int()
    } else {
      c - 'a'.to_int() + 10
    }
  }
  for i in 0..<n {
    let hi = nibble(s.unsafe_get(2 * i).unsafe_to_char())
    let lo = nibble(s.unsafe_get(2 * i + 1).unsafe_to_char())
    out[i] = (hi * 16 + lo).to_byte()
  }
  Bytes::from_array(out)
}

///|
fn parse_channel(s : StringView) -> ModularChannelParams {
  let f = s.split(":").map(parse_int_or_tag).collect()
  let shift = match s.split(":").nth(2) {
    Some("S") => ChannelShift::Shifts(f[3])
    Some("R") => ChannelShift::Raw(f[3], f[4])
    _ =>
      ChannelShift::JpegUpsampling(
        has_h_subsample=f[3] != 0,
        h_subsample=f[4] != 0,
        has_v_subsample=f[5] != 0,
        v_subsample=f[6] != 0,
      )
  }
  { width: f[0], height: f[1], shift, }
}

///|
fn parse_int_or_tag(s : StringView) -> Int32 {
  if s == "S" || s == "R" || s == "J" {
    0
  } else {
    parse_int(s.to_owned())
  }
}

///|
/// Returns the number of frames whose final hashes were compared.
fn replay_dump(dump : String) -> Int32 raise {
  let mut global : Modular? = None
  let mut ma_config : MaConfig? = None
  let mut groups : TransformedGlobalModular? = None
  let mut image : ModularImageDestination? = None
  let mut standalone : Modular? = None
  let mut checked = 0
  for line in dump.split("\n") {
    let f = line.split(" ").collect()
    if f.length() < 2 {
      continue
    }
    match f[0] {
      "G" => {
        let node_limit = parse_int(f[1].to_owned())
        let group_dim = parse_int(f[2].to_owned())
        let bit_depth = parse_int(f[3].to_owned())
        let allow_partial = f[4] == "1"
        let bs = @bitstream.Bitstream::new(hex_to_bytes(f[6]))
        let channels = []
        for i in 7..<f.length() {
          channels.push(parse_channel(f[i]))
        }
        let config = if bs.read_bool() {
          Some(
            MaConfig::parse(bs, {
              tracker: None,
              node_limit,
              depth_limit: 2048,
            }),
          )
        } else {
          None
        }
        let params = ModularParams::with_channels(
          group_dim,
          bit_depth,
          channels,
          config,
          None,
        )
        let modular = Modular::parse(bs, params)
        if modular.image_mut() is Some(img) {
          let gmodular = img.prepare_gmodular()
          gmodular.decode(bs, 0, allow_partial)
        }
        global = Some(modular)
        ma_config = config
        groups = None
        image = None
      }
      "S" => {
        let map = @sorted_map.SortedMap([])
        for i in 1..<f.length() {
          let p = f[i]
            .split(":")
            .map(fn(x) { parse_int(x.to_owned()) })
            .collect()
          map.set(p[0], (p[1], p[2]))
        }
        let img = global.unwrap().try_clone().image_mut().unwrap()
        image = Some(img)
        groups = Some(img.prepare_groups(map))
      }
      "L" =>
        if groups is Some(g) {
          let idx = parse_int(f[1].to_owned())
          let stream = parse_int(f[2].to_owned())
          let allow_partial = f[3] == "1"
          let bs = @bitstream.Bitstream::new(hex_to_bytes(f[5]))
          let sub = g.lf_groups[idx]
          if !sub.is_empty() {
            let rec = sub.recursive(bs, ma_config, None)
            let s = rec.prepare_subimage()
            s.decode(bs, stream, allow_partial)
            s.finish() |> ignore
          }
        }
      "P" =>
        if groups is Some(g) {
          let pass_idx = parse_int(f[1].to_owned())
          let group_idx = parse_int(f[2].to_owned())
          let stream = parse_int(f[3].to_owned())
          let allow_partial = f[4] == "1"
          let bs = @bitstream.Bitstream::new(hex_to_bytes(f[6]))
          let sub = g.pass_groups[pass_idx][group_idx]
          let rec = sub.recursive(bs, ma_config, None)
          let s = rec.prepare_subimage()
          s.decode(bs, stream, allow_partial)
          s.finish() |> ignore
        }
      "F" => {
        let img = image.unwrap()
        img.prepare_subimage().finish() |> ignore
        check_channels(img.image_channels(), f)
        checked += 1
        groups = None
        image = None
      }
      "V" => {
        let stream = parse_int(f[1].to_owned())
        let allow_partial = f[2] == "1"
        let bs = @bitstream.Bitstream::new(hex_to_bytes(f[4]))
        let group_dim = parse_int(f[5].to_owned())
        let bit_depth = parse_int(f[6].to_owned())
        let channels = []
        for i in 7..<f.length() {
          channels.push(parse_channel(f[i]))
        }
        let params = ModularParams::with_channels(
          group_dim,
          bit_depth,
          channels,
          ma_config,
          None,
        )
        let modular = Modular::parse(bs, params)
        let s = modular.image_mut().unwrap().prepare_subimage()
        s.decode(bs, stream, allow_partial)
        s.finish() |> ignore
        standalone = Some(modular)
      }
      "W" => {
        let chans = standalone.unwrap().image().unwrap().image_channels()
        check_channels(chans, f)
        checked += 1
      }
      _ => ()
    }
  }
  checked
}

///|
fn check_channels(
  chans : Array[@grid.Grid[Int32]],
  f : Array[StringView],
) -> Unit raise {
  assert_eq(chans.length(), parse_int(f[1].to_owned()))
  for i, g in chans {
    let p = f[i + 2].split(":").collect()
    assert_eq(g.width, parse_int(p[0].to_owned()))
    assert_eq(g.height, parse_int(p[1].to_owned()))
    let hash = { h: 2166136261U, }
    for v in g.buf {
      hash.add(v)
    }
    assert_eq(hash.h, @string.parse_uint(p[2]), msg="channel \{i}")
  }
}
