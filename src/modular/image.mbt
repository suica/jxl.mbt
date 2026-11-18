///|
/// A channel grid view after transforms.
pub(all) enum TransformedGrid {
  Single(@grid.SubGrid[Int32])
  Merged(leader~ : @grid.SubGrid[Int32], members~ : Array[TransformedGrid])
}

///|
/// `From<MutableSubgrid>`.
pub fn TransformedGrid::from(grid : @grid.SubGrid[Int32]) -> TransformedGrid {
  Single(grid)
}

///|
fn TransformedGrid::reborrow(self : TransformedGrid) -> TransformedGrid {
  Single(self.grid())
}

///|
/// `grid()` / `grid_mut()`: the single grid or the leader.
fn TransformedGrid::grid(self : TransformedGrid) -> @grid.SubGrid[Int32] {
  match self {
    Single(g) => g
    Merged(leader~, ..) => leader
  }
}

///|
/// Replaces the grid returned by `grid_mut()` (the leader), keeping members.
fn TransformedGrid::with_grid(
  self : TransformedGrid,
  g : @grid.SubGrid[Int32],
) -> TransformedGrid {
  match self {
    Single(_) => Single(g)
    Merged(members~, ..) => Merged(leader=g, members~)
  }
}

///|
/// `merge(&mut self, members)`; returns the new value of `self`.
fn TransformedGrid::merge(
  self : TransformedGrid,
  members : Array[TransformedGrid],
) -> TransformedGrid {
  if members.is_empty() {
    return self
  }
  match self {
    Single(leader) => Merged(leader~, members~)
    Merged(members=original_members, ..) => {
      original_members.append(members)
      self
    }
  }
}

///|
/// `unmerge(&mut self, count)`; returns the new value of `self` and the
/// removed members.
fn TransformedGrid::unmerge(
  self : TransformedGrid,
  count : Int32,
) -> (TransformedGrid, Array[TransformedGrid]) {
  if count == 0 {
    return (self, [])
  }
  match self {
    Single(_) => abort("cannot unmerge TransformedGrid::Single")
    Merged(leader~, members~) => {
      let len = members.length()
      let drained = members.drain(len - count, len)
      if len == count {
        (Single(leader), drained)
      } else {
        (self, drained)
      }
    }
  }
}

///|
pub struct ModularImageDestination {
  priv header : ModularHeader
  priv ma_ctx : MaConfig
  priv group_dim : Int32
  priv bit_depth : Int32
  priv channels : ModularChannels
  priv meta_channels : Array[@grid.Grid[Int32]]
  priv image_channels : Array[@grid.Grid[Int32]]
  priv sample : Sample
  /// The tracker the grids were allocated with (`AlignedGrid::tracker`).
  priv tracker : @grid.AllocTracker?
}

///|
fn ModularImageDestination::new(
  header : ModularHeader,
  ma_ctx : MaConfig,
  group_dim : Int32,
  bit_depth : Int32,
  channels : ModularChannels,
  tracker : @grid.AllocTracker?,
  sample : Sample,
) -> ModularImageDestination raise @bitstream.JxlError {
  let meta_channels = []
  for tr in header.transform {
    tr.prepare_meta_channels(meta_channels, tracker, sample)
  }
  let image_channels = []
  for ch in channels.info {
    image_channels.push(
      @grid.Grid::with_alloc_tracker(
        ch.width,
        ch.height,
        0,
        tracker,
        elem_size=sample.size(),
      ),
    )
  }
  {
    header,
    ma_ctx,
    group_dim,
    bit_depth,
    channels,
    meta_channels,
    image_channels,
    sample,
    tracker,
  }
}

///|
/// `AlignedGrid::try_clone`: allocates through the grid's tracker.
fn try_clone_grid(
  g : @grid.Grid[Int32],
  tracker : @grid.AllocTracker?,
  sample : Sample,
) -> @grid.Grid[Int32] raise @bitstream.JxlError {
  let out = @grid.Grid::with_alloc_tracker(
    g.width,
    g.height,
    0,
    tracker,
    elem_size=sample.size(),
  )
  let n = g.width * g.height
  if n > 0 {
    FixedArray::blit_to(g.buf, out.buf, len=n)
  }
  out
}

///|
pub fn ModularImageDestination::try_clone(
  self : ModularImageDestination,
) -> ModularImageDestination raise @bitstream.JxlError {
  let meta_channels = []
  for g in self.meta_channels {
    meta_channels.push(try_clone_grid(g, self.tracker, self.sample))
  }
  let image_channels = []
  for g in self.image_channels {
    image_channels.push(try_clone_grid(g, self.tracker, self.sample))
  }
  {
    header: self.header,
    ma_ctx: self.ma_ctx,
    group_dim: self.group_dim,
    bit_depth: self.bit_depth,
    channels: self.channels.clone(),
    meta_channels,
    image_channels,
    sample: self.sample,
    tracker: self.tracker,
  }
}

///|
pub fn ModularImageDestination::image_channels(
  self : ModularImageDestination,
) -> Array[@grid.Grid[Int32]] {
  self.image_channels
}

///|
pub fn ModularImageDestination::into_image_channels(
  self : ModularImageDestination,
) -> Array[@grid.Grid[Int32]] {
  self.image_channels
}

///|
pub fn ModularImageDestination::into_image_channels_with_info(
  self : ModularImageDestination,
) -> Array[(@grid.Grid[Int32], ModularChannelInfo)] {
  let out = []
  let n = @cmp.minimum(
    self.image_channels.length(),
    self.channels.info.length(),
  )
  for i in 0..<n {
    out.push((self.image_channels[i], self.channels.info[i]))
  }
  out
}

///|
pub fn ModularImageDestination::has_palette(
  self : ModularImageDestination,
) -> Bool {
  self.header.transform.iter().any(fn(tr) { tr.is_palette() })
}

///|
pub fn ModularImageDestination::has_squeeze(
  self : ModularImageDestination,
) -> Bool {
  self.header.transform.iter().any(fn(tr) { tr.is_squeeze() })
}

///|
/// The subimage of channels decoded in the GlobalModular section: meta
/// channels and channels not larger than a group.
pub fn ModularImageDestination::prepare_gmodular(
  self : ModularImageDestination,
) -> TransformedModularSubimage raise @bitstream.JxlError {
  guard self.group_dim != 0 else { abort("assertion failed: group_dim != 0") }
  let group_dim = self.group_dim
  let subimage = self.prepare_subimage()
  let channel_info = []
  let grids = []
  for i, info in subimage.channel_info {
    if i < subimage.nb_meta_channels ||
      (info.width <= group_dim && info.height <= group_dim) {
      channel_info.push(info)
      grids.push(subimage.grid[i])
    } else {
      break
    }
  }
  let channel_indices = Array::makei(channel_info.length(), fn(i) { i })
  {
    header: subimage.header,
    ma_ctx: subimage.ma_ctx,
    bit_depth: subimage.bit_depth,
    sample: subimage.sample,
    nb_meta_channels: subimage.nb_meta_channels,
    channel_info,
    channel_indices,
    grid: grids,
    partial: subimage.partial,
  }
}

///|
/// `MutableSubgrid::into_groups_with_fixed_count`.
fn into_groups_with_fixed_count(
  g : @grid.SubGrid[Int32],
  group_width : Int32,
  group_height : Int32,
  num_cols : Int32,
  num_rows : Int32,
) -> Array[@grid.SubGrid[Int32]] {
  let { buf, offset, width, height, stride, } = g
  let groups = Array(capacity=num_cols * num_rows)
  for gy in 0..<num_rows {
    let y = @cmp.minimum(
      gy.to_int64() * group_height.to_int64(),
      height.to_int64(),
    ).to_int()
    let gh = @cmp.minimum(height - y, group_height)
    for gx in 0..<num_cols {
      let x = @cmp.minimum(
        gx.to_int64() * group_width.to_int64(),
        width.to_int64(),
      ).to_int()
      let gw = @cmp.minimum(width - x, group_width)
      let off = if gh > 0 && width > 0 { y * stride + x } else { 0 }
      groups.push(@grid.SubGrid::from_buf(buf, offset + off, gw, gh, stride))
    }
  }
  groups
}

///|
/// Splits the channels not decoded in GlobalModular into LF groups and pass
/// groups. `pass_shifts` maps pass index to its `(minshift, maxshift)`.
pub fn ModularImageDestination::prepare_groups(
  self : ModularImageDestination,
  pass_shifts : @sorted_map.SortedMap[Int32, (Int32, Int32)],
) -> TransformedGlobalModular raise @bitstream.JxlError {
  guard self.group_dim != 0 else { abort("assertion failed: group_dim != 0") }
  let num_passes = pass_shifts.last().unwrap().0 + 1
  let group_dim = self.group_dim
  let group_dim_shift = group_dim.ctz()
  let bit_depth = self.bit_depth
  let subimage = self.prepare_subimage()
  let lf_groups : Array[TransformedModularSubimage] = []
  let pass_groups : Array[Array[TransformedModularSubimage]] = Array::makei(
    num_passes,
    fn(_) { [] },
  )
  let mut skipping = true
  for i, info in subimage.channel_info {
    if skipping &&
      (
        i < subimage.nb_meta_channels ||
        (info.width <= group_dim && info.height <= group_dim)
      ) {
      continue
    }
    skipping = false
    let { original_width, original_height, hshift, vshift, original_shift, .. } = info
    guard hshift >= 0 && vshift >= 0 else {
      abort("assertion failed: hshift >= 0 && vshift >= 0")
    }
    let grid = subimage.grid[i].grid()
    let (groups, grids) = if hshift < 3 || vshift < 3 {
      let shift = @cmp.minimum(hshift, vshift)
      let mut pass_idx = -1
      for item in pass_shifts.iter() {
        let (idx, (minshift, maxshift)) = item
        if minshift <= shift && shift < maxshift {
          pass_idx = idx
          break
        }
      }
      guard pass_idx >= 0 else { abort("no pass for channel shift") }
      let group_width = group_dim >> hshift
      let group_height = group_dim >> vshift
      if group_width == 0 || group_height == 0 {
        raise modular_error("InvalidSqueezeParams")
      }
      let grids = into_groups_with_fixed_count(
        grid,
        group_width,
        group_height,
        shr_u(original_width + group_dim - 1, group_dim_shift),
        shr_u(original_height + group_dim - 1, group_dim_shift),
      )
      (pass_groups[pass_idx], grids)
    } else {
      // hshift >= 3 && vshift >= 3
      let lf_group_width = group_dim >> (hshift - 3)
      let lf_group_height = group_dim >> (vshift - 3)
      if lf_group_width == 0 || lf_group_height == 0 {
        raise modular_error("InvalidSqueezeParams")
      }
      let grids = into_groups_with_fixed_count(
        grid,
        lf_group_width,
        lf_group_height,
        shr_u(original_width + (group_dim << 3) - 1, group_dim_shift + 3),
        shr_u(original_height + (group_dim << 3) - 1, group_dim_shift + 3),
      )
      (lf_groups, grids)
    }
    if groups.is_empty() {
      for _ in 0..<grids.length() {
        groups.push(
          TransformedModularSubimage::empty(
            subimage.header,
            subimage.ma_ctx,
            bit_depth,
            subimage.sample,
          ),
        )
      }
    } else if groups.length() != grids.length() {
      abort("group count mismatch")
    }
    for j, grid in grids {
      let sub = groups[j]
      let width = grid.width
      let height = grid.height
      if width == 0 || height == 0 {
        continue
      }
      sub.channel_info.push({
        width,
        height,
        original_width: width << hshift,
        original_height: height << vshift,
        hshift,
        vshift,
        original_shift,
      })
      sub.channel_indices.push(i)
      sub.grid.push(TransformedGrid::from(grid))
      sub.partial = true
    }
  }
  { lf_groups, pass_groups, }
}

///|
pub fn ModularImageDestination::prepare_subimage(
  self : ModularImageDestination,
) -> TransformedModularSubimage raise @bitstream.JxlError {
  let channels = self.channels.clone()
  let meta_channel_grids = self.meta_channels.map(fn(g) { g.as_subgrid() })
  let grids = self.image_channels.map(fn(g) {
    TransformedGrid::from(g.as_subgrid())
  })
  for tr in self.header.transform {
    tr.transform_channels(channels, meta_channel_grids, grids)
  }
  let channel_info = channels.info
  let channel_indices = Array::makei(channel_info.length(), fn(i) { i })
  {
    header: self.header,
    ma_ctx: self.ma_ctx,
    bit_depth: self.bit_depth,
    sample: self.sample,
    nb_meta_channels: channels.nb_meta_channels,
    channel_info,
    channel_indices,
    grid: grids,
    partial: true,
  }
}

///|
pub(all) struct TransformedGlobalModular {
  lf_groups : Array[TransformedModularSubimage]
  pass_groups : Array[Array[TransformedModularSubimage]]
}

///|
pub struct TransformedModularSubimage {
  priv header : ModularHeader
  priv ma_ctx : MaConfig
  priv bit_depth : Int32
  priv sample : Sample
  priv nb_meta_channels : Int32
  priv channel_info : Array[ModularChannelInfo]
  priv channel_indices : Array[Int32]
  priv grid : Array[TransformedGrid]
  priv mut partial : Bool
}

///|
fn TransformedModularSubimage::empty(
  header : ModularHeader,
  ma_ctx : MaConfig,
  bit_depth : Int32,
  sample : Sample,
) -> TransformedModularSubimage {
  {
    header,
    ma_ctx,
    bit_depth,
    sample,
    nb_meta_channels: 0,
    channel_info: [],
    channel_indices: [],
    grid: [],
    partial: false,
  }
}

///|
pub fn TransformedModularSubimage::is_empty(
  self : TransformedModularSubimage,
) -> Bool {
  self.channel_info.is_empty()
}

///|
pub fn TransformedModularSubimage::is_partial(
  self : TransformedModularSubimage,
) -> Bool {
  self.partial
}

///|
/// Reads the local Modular header of a group and returns the group image.
pub fn TransformedModularSubimage::recursive(
  self : TransformedModularSubimage,
  bs : @bitstream.Bitstream,
  global_ma_config : MaConfig?,
  tracker : @grid.AllocTracker?,
) -> RecursiveModularImage raise @bitstream.JxlError {
  let channels : ModularChannels = {
    info: self.channel_info,
    nb_meta_channels: 0,
  }
  let (header, ma_ctx) = read_and_validate_local_modular_header(
    bs, channels, global_ma_config, tracker,
  )
  let meta_channels = []
  for tr in header.transform {
    tr.prepare_meta_channels(meta_channels, tracker, self.sample)
  }
  {
    header,
    ma_ctx,
    bit_depth: self.bit_depth,
    sample: self.sample,
    channels,
    meta_channels,
    image_channels: self.grid,
  }
}

///|
/// Applies inverse transforms. Returns whether the image was fully decoded.
pub fn TransformedModularSubimage::finish(
  self : TransformedModularSubimage,
  pool : @threadpool.JxlThreadPool,
) -> Bool {
  for i = self.header.transform.length() - 1; i >= 0; i = i - 1 {
    self.header.transform[i].inverse(
      self.grid,
      self.bit_depth,
      pool,
      self.sample,
    )
  }
  !self.partial
}

///|
fn TransformedModularSubimage::decode_inner(
  self : TransformedModularSubimage,
  bs : @bitstream.Bitstream,
  stream_index : Int32,
) -> Unit raise @bitstream.JxlError {
  let narrow = self.sample is I16
  let mut dist_multiplier = 0
  for info in self.channel_info {
    if info.width > dist_multiplier {
      dist_multiplier = info.width
    }
  }
  let decoder = self.ma_ctx.decoder().clone()
  decoder.begin(bs)
  let ma_tree_list : Array[FlatMaTree?] = []
  for i, info in self.channel_info {
    if info.width == 0 || info.height == 0 {
      ma_tree_list.push(None)
      continue
    }
    let mut filtered_prev_len = 0
    for j in 0..<i {
      let prev_info = self.channel_info[j]
      if info.width == prev_info.width &&
        info.height == prev_info.height &&
        info.hshift == prev_info.hshift &&
        info.vshift == prev_info.vshift {
        filtered_prev_len += 1
      }
    }
    ma_tree_list.push(
      Some(self.ma_ctx.make_flat_tree(i, stream_index, filtered_prev_len)),
    )
  }
  if decoder.as_rle() is Some(rle_decoder) {
    let is_fast_lossless = ma_tree_list
      .iter()
      .all(fn(ma_tree) {
        match ma_tree {
          Some(ma_tree) =>
            match ma_tree.single_node() {
              Some({ predictor: Gradient, offset: 0, multiplier: 1, .. }) =>
                true
              _ => false
            }
          None => true
        }
      })
    if is_fast_lossless {
      let rle_state = RleState::new(narrow)
      for i, ma_tree in ma_tree_list {
        guard ma_tree is Some(ma_tree) else { continue }
        let node = ma_tree.single_node().unwrap()
        decode_fast_lossless(
          narrow,
          bs,
          rle_decoder,
          rle_state,
          node.cluster,
          self.grid[i].grid(),
        )
      }
      rle_state.check_error()
      // Prefix code doesn't have checksum
      return
    }
  }
  let wp_header = self.header.wp_params
  let predictor = PredictorState::new()
  // key: (width, height, hshift, vshift); value: grids, most recent first
  let prev_keys : Array[(Int32, Int32, Int32, Int32)] = []
  let prev_lists : Array[Array[@grid.SubGrid[Int32]]] = []
  for i, info in self.channel_info {
    guard ma_tree_list[i] is Some(ma_tree) else { continue }
    let key = (info.width, info.height, info.hshift, info.vshift)
    let mut filtered_prev : Array[@grid.SubGrid[Int32]] = []
    let mut found = false
    for k, pk in prev_keys {
      if pk == key {
        filtered_prev = prev_lists[k]
        found = true
        break
      }
    }
    if !found {
      prev_keys.push(key)
      prev_lists.push(filtered_prev)
    }
    let grid = self.grid[i].grid()
    if ma_tree.single_node() is Some(node) {
      decode_single_node(
        narrow, bs, decoder, dist_multiplier, predictor, wp_header, grid, node,
      )
    } else if ma_tree.simple_table() is Some(table) {
      decode_simple_table(
        narrow, bs, decoder, dist_multiplier, predictor, wp_header, grid, table,
      )
    } else {
      let depth = ma_tree.max_prev_channel_depth()
      let wp_header = if ma_tree.need_self_correcting() {
        Some(wp_header)
      } else {
        None
      }
      predictor.reset(grid.width, filtered_prev[0:depth], wp_header)
      decode_slow(
        narrow, bs, decoder, dist_multiplier, ma_tree, predictor, grid,
      )
    }
    filtered_prev.insert(0, grid)
  }
  decoder.finalize()
}

///|
/// Decodes the channels of the subimage. With `allow_partial`, an
/// unexpected end of stream leaves the image partially decoded.
pub fn TransformedModularSubimage::decode(
  self : TransformedModularSubimage,
  bs : @bitstream.Bitstream,
  stream_index : Int32,
  allow_partial : Bool,
) -> Unit raise @bitstream.JxlError {
  try self.decode_inner(bs, stream_index) catch {
    e if e.unexpected_eof() && allow_partial => ()
    e => raise e
  } noraise {
    _ => self.partial = false
  }
}

///|
pub struct RecursiveModularImage {
  priv header : ModularHeader
  priv ma_ctx : MaConfig
  priv bit_depth : Int32
  priv sample : Sample
  priv channels : ModularChannels
  priv meta_channels : Array[@grid.Grid[Int32]]
  priv image_channels : Array[TransformedGrid]
}

///|
pub fn RecursiveModularImage::prepare_subimage(
  self : RecursiveModularImage,
) -> TransformedModularSubimage raise @bitstream.JxlError {
  let channels = self.channels.clone()
  let meta_channel_grids = self.meta_channels.map(fn(g) { g.as_subgrid() })
  let grids = self.image_channels.map(fn(g) { g.reborrow() })
  for tr in self.header.transform {
    tr.transform_channels(channels, meta_channel_grids, grids)
  }
  let channel_info = channels.info
  let channel_indices = Array::makei(channel_info.length(), fn(i) { i })
  {
    header: self.header,
    ma_ctx: self.ma_ctx,
    bit_depth: self.bit_depth,
    sample: self.sample,
    nb_meta_channels: channels.nb_meta_channels,
    channel_info,
    channel_indices,
    grid: grids,
    partial: true,
  }
}
