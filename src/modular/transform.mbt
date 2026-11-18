///|
priv enum TransformInfo {
  Rct(Rct)
  Palette(Palette)
  Squeeze(Squeeze)
}

///|
fn TransformInfo::prepare_transform_info(
  self : TransformInfo,
  channels : ModularChannels,
) -> Unit raise @bitstream.JxlError {
  match self {
    Rct(rct) => rct.transform_channel_info(channels)
    Palette(pal) => pal.transform_channel_info(channels, [], None)
    Squeeze(sq) => {
      sq.set_default_params(channels)
      sq.transform_channel_info(channels, None)
    }
  }
}

///|
fn TransformInfo::prepare_meta_channels(
  self : TransformInfo,
  meta_channels : Array[@grid.Grid[Int32]],
  tracker : @grid.AllocTracker?,
  sample : Sample,
) -> Unit raise @bitstream.JxlError {
  if self is Palette(pal) {
    meta_channels.insert(
      0,
      @grid.Grid::with_alloc_tracker(
        pal.nb_colours,
        pal.num_c,
        0,
        tracker,
        elem_size=sample.size(),
      ),
    )
  }
}

///|
fn TransformInfo::transform_channels(
  self : TransformInfo,
  channels : ModularChannels,
  meta_channel_grids : Array[@grid.SubGrid[Int32]],
  grids : Array[TransformedGrid],
) -> Unit raise @bitstream.JxlError {
  match self {
    Rct(rct) => rct.transform_channel_info(channels)
    Palette(pal) =>
      pal.transform_channel_info(channels, meta_channel_grids, Some(grids))
    Squeeze(sq) => sq.transform_channel_info(channels, Some(grids))
  }
}

///|
fn TransformInfo::inverse(
  self : TransformInfo,
  grids : Array[TransformedGrid],
  bit_depth : Int32,
  pool : @threadpool.JxlThreadPool,
  sample : Sample,
) -> Unit {
  match self {
    Rct(rct) => rct.inverse(grids, pool, sample)
    Palette(pal) => pal.inverse(grids, bit_depth, sample)
    Squeeze(sq) => sq.inverse(grids, pool, sample)
  }
}

///|
fn TransformInfo::is_palette(self : TransformInfo) -> Bool {
  self is Palette(_)
}

///|
fn TransformInfo::is_squeeze(self : TransformInfo) -> Bool {
  self is Squeeze(_)
}

///|
fn TransformInfo::parse(
  bs : @bitstream.Bitstream,
  wp_header : WpHeader,
) -> TransformInfo raise @bitstream.JxlError {
  let tr = bs.read_bits(2)
  match tr {
    0 => Rct(Rct::parse(bs))
    1 => Palette(Palette::parse(bs, wp_header))
    2 => Squeeze(Squeeze::parse(bs))
    value => raise @bitstream.InvalidEnum("TransformId", value)
  }
}

///|
fn read_begin_c(bs : @bitstream.Bitstream) -> Int32 raise @bitstream.JxlError {
  bs
  .read_u32(
    @bitstream.u(3),
    @bitstream.cu(8, 6),
    @bitstream.cu(72, 10),
    @bitstream.cu(1096, 13),
  )
  .reinterpret_as_int()
}

///|
priv struct Rct {
  begin_c : Int32
  rct_type : Int32
}

///|
fn Rct::parse(bs : @bitstream.Bitstream) -> Rct raise @bitstream.JxlError {
  let begin_c = read_begin_c(bs)
  let rct_type = bs
    .read_u32(
      @bitstream.c(6),
      @bitstream.u(2),
      @bitstream.cu(2, 4),
      @bitstream.cu(10, 6),
    )
    .reinterpret_as_int()
  { begin_c, rct_type, }
}

///|
priv struct Squeeze {
  sp : Array[SqueezeParams]
}

///|
fn Squeeze::parse(
  bs : @bitstream.Bitstream,
) -> Squeeze raise @bitstream.JxlError {
  let num_sq = bs
    .read_u32(
      @bitstream.c(0),
      @bitstream.cu(1, 4),
      @bitstream.cu(9, 6),
      @bitstream.cu(41, 8),
    )
    .reinterpret_as_int()
  let sp = []
  for _ in 0..<num_sq {
    sp.push(SqueezeParams::parse(bs))
  }
  { sp, }
}

///|
priv struct SqueezeParams {
  horizontal : Bool
  in_place : Bool
  begin_c : Int32
  num_c : Int32
}

///|
fn SqueezeParams::parse(
  bs : @bitstream.Bitstream,
) -> SqueezeParams raise @bitstream.JxlError {
  let horizontal = bs.read_bool()
  let in_place = bs.read_bool()
  let begin_c = read_begin_c(bs)
  let num_c = bs
    .read_u32(
      @bitstream.c(1),
      @bitstream.c(2),
      @bitstream.c(3),
      @bitstream.cu(4, 4),
    )
    .reinterpret_as_int()
  { horizontal, in_place, begin_c, num_c, }
}

///|
priv struct Palette {
  begin_c : Int32
  num_c : Int32
  nb_colours : Int32
  nb_deltas : Int32
  d_pred : Predictor
  wp_header : WpHeader?
}

///|
fn Palette::parse(
  bs : @bitstream.Bitstream,
  wp_header : WpHeader,
) -> Palette raise @bitstream.JxlError {
  let begin_c = read_begin_c(bs)
  let num_c = bs
    .read_u32(
      @bitstream.c(1),
      @bitstream.c(3),
      @bitstream.c(4),
      @bitstream.cu(1, 13),
    )
    .reinterpret_as_int()
  let nb_colours = bs
    .read_u32(
      @bitstream.u(8),
      @bitstream.cu(256, 10),
      @bitstream.cu(1280, 12),
      @bitstream.cu(5376, 16),
    )
    .reinterpret_as_int()
  let nb_deltas = bs
    .read_u32(
      @bitstream.c(0),
      @bitstream.cu(1, 8),
      @bitstream.cu(257, 10),
      @bitstream.cu(1281, 16),
    )
    .reinterpret_as_int()
  let d_pred = Predictor::try_from(bs.read_bits(4))
  {
    begin_c,
    num_c,
    nb_colours,
    nb_deltas,
    d_pred,
    wp_header: if d_pred == SelfCorrecting {
      Some(wp_header)
    } else {
      None
    },
  }
}

///|
fn Rct::transform_channel_info(
  self : Rct,
  channels : ModularChannels,
) -> Unit raise @bitstream.JxlError {
  let begin_c = self.begin_c
  let end_c = self.begin_c + 3
  if end_c > channels.info.length() {
    raise modular_error("InvalidRctParams")
  }
  let { width, height, .. } = channels.info[begin_c]
  for i in (begin_c + 1)..<end_c {
    let info = channels.info[i]
    if width != info.width || height != info.height {
      raise modular_error("InvalidRctParams")
    }
  }
}

///|
fn Rct::inverse(
  self : Rct,
  grids : Array[TransformedGrid],
  pool : @threadpool.JxlThreadPool,
  sample : Sample,
) -> Unit {
  let permutation = self.rct_type / 7
  let ty = self.rct_type % 7
  let begin_c = self.begin_c
  let a = grids[begin_c].grid()
  let b = grids[begin_c + 1].grid()
  let c = grids[begin_c + 2].grid()
  inverse_rct(ty, permutation, a, b, c, pool, sample is I16)
}

///|
fn Palette::transform_channel_info(
  self : Palette,
  channels : ModularChannels,
  meta_channel_grids : Array[@grid.SubGrid[Int32]],
  grids : Array[TransformedGrid]?,
) -> Unit raise @bitstream.JxlError {
  let begin_c = self.begin_c
  let end_c = begin_c + self.num_c
  if end_c > channels.info.length() {
    raise modular_error("InvalidPaletteParams")
  }
  if begin_c < channels.nb_meta_channels {
    if end_c > channels.nb_meta_channels {
      raise modular_error("InvalidPaletteParams")
    }
    channels.nb_meta_channels = channels.nb_meta_channels + 2 - self.num_c
  } else {
    channels.nb_meta_channels += 1
  }
  let { width, height, .. } = channels.info[begin_c]
  for i in (begin_c + 1)..<end_c {
    let info = channels.info[i]
    if info.width != width || info.height != height {
      raise modular_error("InvalidPaletteParams")
    }
  }
  channels.info.drain(begin_c + 1, end_c) |> ignore
  channels.info.insert(
    0,
    ModularChannelInfo::new_unshiftable(self.nb_colours, self.num_c),
  )
  if grids is Some(grids) {
    let members = grids.drain(begin_c + 1, end_c)
    grids[begin_c] = grids[begin_c].merge(members)
    let palette_grid = meta_channel_grids.pop().unwrap()
    grids.insert(0, TransformedGrid::from(palette_grid))
  }
}

///|
fn Palette::inverse(
  self : Palette,
  grids : Array[TransformedGrid],
  bit_depth : Int32,
  sample : Sample,
) -> Unit {
  let begin_c = self.begin_c
  let num_c = self.num_c
  let palette_grid = grids.remove(0)
  let (leader, members) = grids[begin_c].unmerge(num_c - 1)
  grids[begin_c] = leader
  let targets = [leader.grid()]
  for m in members {
    targets.push(m.grid())
  }
  self.inverse_inner(palette_grid.grid(), targets, bit_depth, sample)
  for i, grid in members {
    grids.insert(begin_c + 1 + i, grid)
  }
}

///|
fn Squeeze::set_default_params(
  self : Squeeze,
  channels : ModularChannels,
) -> Unit {
  if !self.sp.is_empty() {
    return
  }
  let first = channels.nb_meta_channels
  let first_ch = channels.info[first]
  let mut w = first_ch.width
  let mut h = first_ch.height
  if channels.info.length() - first >= 3 {
    let next_ch = channels.info[first + 1]
    if next_ch.width == w && next_ch.height == h {
      self.sp.push({
        horizontal: true,
        in_place: false,
        begin_c: first + 1,
        num_c: 2,
      })
      self.sp.push({
        horizontal: false,
        in_place: false,
        begin_c: first + 1,
        num_c: 2,
      })
    }
  }
  let num_c = channels.info.length() - first
  if h >= w && h > 8 {
    self.sp.push({ horizontal: false, in_place: true, begin_c: first, num_c, })
    h = div_ceil(h, 2)
  }
  while w > 8 || h > 8 {
    if w > 8 {
      self.sp.push({ horizontal: true, in_place: true, begin_c: first, num_c, })
      w = div_ceil(w, 2)
    }
    if h > 8 {
      self.sp.push({ horizontal: false, in_place: true, begin_c: first, num_c, })
      h = div_ceil(h, 2)
    }
  }
}

///|
fn Squeeze::transform_channel_info(
  self : Squeeze,
  channels : ModularChannels,
  grids : Array[TransformedGrid]?,
) -> Unit raise @bitstream.JxlError {
  for sp in self.sp {
    let { horizontal, in_place, begin_c: begin, num_c, } = sp
    let end = begin + num_c
    if end > channels.info.length() {
      raise modular_error("InvalidSqueezeParams")
    }
    if begin < channels.nb_meta_channels {
      if !in_place || end > channels.nb_meta_channels {
        raise modular_error("InvalidSqueezeParams")
      }
      channels.nb_meta_channels += num_c
    }
    let residu_channels : Array[ModularChannelInfo] = []
    let residu_grids : Array[TransformedGrid] = []
    for idx in 0..<num_c {
      let ch = channels.info[begin + idx]
      if ch.width == 0 || ch.height == 0 {
        raise modular_error("InvalidSqueezeParams")
      }
      if ch.hshift > 30 || ch.vshift > 30 {
        raise modular_error("InvalidSqueezeParams")
      }
      if horizontal {
        let len = ch.width
        let shift_inc = if ch.hshift >= 0 { 1 } else { 0 }
        channels.info[begin + idx] = {
          ..ch,
          width: div_ceil(len, 2),
          hshift: ch.hshift + shift_inc,
        }
        residu_channels.push({
          ..ch,
          width: len / 2,
          hshift: ch.hshift + shift_inc,
        })
      } else {
        let len = ch.height
        let shift_inc = if ch.vshift >= 0 { 1 } else { 0 }
        channels.info[begin + idx] = {
          ..ch,
          height: div_ceil(len, 2),
          vshift: ch.vshift + shift_inc,
        }
        residu_channels.push({
          ..ch,
          height: len / 2,
          vshift: ch.vshift + shift_inc,
        })
      }
      if grids is Some(grids) {
        let g = grids[begin + idx]
        let gg = g.grid()
        let (kept, residu_grid) = if horizontal {
          gg.split_horizontal(div_ceil(gg.width, 2))
        } else {
          gg.split_vertical(div_ceil(gg.height, 2))
        }
        grids[begin + idx] = g.with_grid(kept)
        residu_grids.push(TransformedGrid::from(residu_grid))
      }
    }
    if in_place {
      residu_channels.append(channels.info.drain(end, channels.info.length()))
    }
    channels.info.append(residu_channels)
    if grids is Some(grids) {
      if in_place {
        residu_grids.append(grids.drain(end, grids.length()))
      }
      grids.append(residu_grids)
    }
  }
}

///|
fn Squeeze::inverse(
  self : Squeeze,
  grids : Array[TransformedGrid],
  pool : @threadpool.JxlThreadPool,
  sample : Sample,
) -> Unit {
  for i = self.sp.length() - 1; i >= 0; i = i - 1 {
    let sp = self.sp[i]
    let begin = sp.begin_c
    let channel_count = sp.num_c
    let end = begin + channel_count
    let residual_channels = if sp.in_place {
      grids.drain(end, end + channel_count)
    } else {
      grids.drain(grids.length() - channel_count, grids.length())
    }
    for j in 0..<channel_count {
      grids[begin + j] = sp.inverse(
        grids[begin + j],
        residual_channels[j],
        pool,
        sample,
      )
    }
  }
}

///|
/// Merges the residual into `i0` and runs the inverse squeeze; returns the
/// new value of `i0`.
fn SqueezeParams::inverse(
  self : SqueezeParams,
  i0 : TransformedGrid,
  i1 : TransformedGrid,
  pool : @threadpool.JxlThreadPool,
  sample : Sample,
) -> TransformedGrid {
  guard i1 is Single(b) else {
    abort("residual channel should be Single channel")
  }
  let a = i0.grid()
  let narrow = sample is I16
  if self.horizontal {
    // merge_horizontal_in_place
    guard a.stride == b.stride &&
      a.height == b.height &&
      a.stride >= a.width + b.width &&
      a.offset + a.width == b.offset else {
      abort("cannot merge subgrids")
    }
    let merged = @grid.SubGrid::from_buf(
      a.buf,
      a.offset,
      a.width + b.width,
      a.height,
      a.stride,
    )
    let width = merged.width
    let height = merged.height
    if height > 16 {
      pool.for_each_vec(merged.into_groups(width, 16), fn(group) {
        inverse_h(group, narrow)
      })
    } else {
      inverse_h(merged, narrow)
    }
    i0.with_grid(merged)
  } else {
    // merge_vertical_in_place
    guard a.stride == b.stride &&
      a.width == b.width &&
      a.offset + a.height * a.stride == b.offset else {
      abort("cannot merge subgrids")
    }
    let merged = @grid.SubGrid::from_buf(
      a.buf,
      a.offset,
      a.width,
      a.height + b.height,
      a.stride,
    )
    let width = merged.width
    let height = merged.height
    if width > 16 {
      pool.for_each_vec(merged.into_groups(16, height), fn(group) {
        inverse_v(group, narrow)
      })
    } else {
      inverse_v(merged, narrow)
    }
    i0.with_grid(merged)
  }
}
