///|
/// Meta-adaptive tree configuration.
///
/// Meta-adaptive (MA) tree is a decision tree that controls how the sample is
/// decoded in the given context. The configuration consists of two
/// components: the MA tree itself, and the distribution information of an
/// entropy decoder. These components are read from the bitstream.
pub struct MaConfig {
  priv num_tree_nodes : Int32
  priv tree_depth : Int32
  priv tree : MaTreeNode
  priv decoder : @coding.Decoder
}

///|
/// Returns the entropy decoder.
///
/// The decoder should be cloned to be used for decoding.
pub fn MaConfig::decoder(self : MaConfig) -> @coding.Decoder {
  self.decoder
}

///|
/// Creates a simplified MA tree with given channel index and stream index,
/// which then can be used to decode samples.
///
/// The method will evaluate the tree with the given information and prune
/// branches which are always not taken.
pub fn MaConfig::make_flat_tree(
  self : MaConfig,
  channel : Int32,
  stream_idx : Int32,
  prev_channels : Int32,
) -> FlatMaTree {
  let nodes = self.tree.flatten(channel, stream_idx, prev_channels)
  FlatMaTree::new(nodes)
}

///|
/// Returns the number of MA tree nodes.
pub fn MaConfig::num_tree_nodes(self : MaConfig) -> Int32 {
  self.num_tree_nodes
}

///|
/// Returns the maximum distance from root to any leaf node.
pub fn MaConfig::tree_depth(self : MaConfig) -> Int32 {
  self.tree_depth
}

///|
/// Parameters for decoding `MaConfig`.
pub(all) struct MaConfigParams {
  /// Allocation tracker.
  tracker : @grid.AllocTracker?
  /// Maximum number of meta-adaptive tree nodes.
  node_limit : Int32
  depth_limit : Int32
}

///|
priv enum FoldingTree {
  Decision(Int32, Int32)
  Leaf(Int32, Predictor, Int32, Int32)
}

///|
/// Size of a `FoldingTree` in upstream, used for allocation tracking.
const FOLDING_TREE_SIZE = 16

///|
/// Saturates a `u32` to `Int`; property ids above `i32::MAX` behave the same
/// as `i32::MAX` (a previous-channel property that is always pruned).
fn u32_to_property(v : UInt32) -> Int32 {
  if v > 0x7fffffffU {
    0x7fffffff
  } else {
    v.reinterpret_as_int()
  }
}

///|
pub fn MaConfig::parse(
  bs : @bitstream.Bitstream,
  params : MaConfigParams,
) -> MaConfig raise @bitstream.JxlError {
  let { tracker, node_limit, depth_limit, } = params
  let tree_decoder = @coding.Decoder::parse(bs, 6)
  if is_infinite_tree_dist(tree_decoder) {
    raise modular_error("InvalidMaTree")
  }
  let mut ctx = 0
  let mut nodes_left = 1
  // Allocation tracking mirrors upstream's growing temporary buffer.
  let mut tmp_alloc = 0
  if tracker is Some(t) {
    t.alloc(16, FOLDING_TREE_SIZE)
    tmp_alloc = 16
  }
  let mut capacity = 16
  let nodes : Array[FoldingTree] = Array(capacity=16)
  let mut max_depth = 1
  defer (if tracker is Some(t) { t.free(tmp_alloc, FOLDING_TREE_SIZE) })
  tree_decoder.begin(bs)
  while nodes_left > 0 {
    if nodes.length() >= 1 << 26 {
      raise modular_error("InvalidMaTree")
    }
    if nodes.length() > node_limit {
      raise @bitstream.ProfileConformance("MA tree limit exceeded")
    }
    if nodes.length() == capacity && tracker is Some(t) {
      let current_len = nodes.length()
      t.free(tmp_alloc, FOLDING_TREE_SIZE)
      tmp_alloc = 0
      let new_cap = if current_len <= 16 {
        256
      } else if current_len <= 256 {
        1024
      } else {
        current_len * 2
      }
      t.alloc(new_cap, FOLDING_TREE_SIZE)
      tmp_alloc = new_cap
      capacity = new_cap
    }
    nodes_left -= 1
    let property = tree_decoder.read_varint(bs, 1)
    let node = if property != 0 {
      let value = @bitstream.unpack_signed(tree_decoder.read_varint(bs, 0))
      nodes_left += 2
      FoldingTree::Decision(u32_to_property(property - 1), value)
    } else {
      let predictor = Predictor::try_from(tree_decoder.read_varint(bs, 2))
      let offset = @bitstream.unpack_signed(tree_decoder.read_varint(bs, 3))
      let mul_log = tree_decoder.read_varint(bs, 4)
      if mul_log > 30 {
        raise modular_error("InvalidMaTree")
      }
      let mul_log = mul_log.reinterpret_as_int()
      let mul_bits = tree_decoder.read_varint(bs, 5)
      if mul_bits > (1U << (31 - mul_log)) - 2 {
        raise modular_error("InvalidMaTree")
      }
      let multiplier = ((mul_bits + 1) << mul_log).reinterpret_as_int()
      let node = FoldingTree::Leaf(ctx, predictor, offset, multiplier)
      ctx += 1
      node
    }
    nodes.push(node)
    if nodes_left > max_depth {
      max_depth = nodes_left
    }
  }
  tree_decoder.finalize()
  let num_tree_nodes = nodes.length()
  let decoder = @coding.Decoder::parse(bs, ctx)
  let cluster_map = decoder.cluster_map()
  if tracker is Some(t) {
    t.alloc(nodes.length(), FOLDING_TREE_SIZE)
  }
  // A queue: push to the back, pop from the front.
  let tmp : Array[(MaTreeNode, Int32)] = Array(capacity=nodes.length())
  let mut head = 0
  for i = nodes.length() - 1; i >= 0; i = i - 1 {
    match nodes[i] {
      Decision(property, value) => {
        let (right, dr) = tmp[head]
        let (left, dl) = tmp[head + 1]
        head += 2
        let node = MaTreeNode::Decision(property~, value~, left~, right~)
        let depth = (if dr > dl { dr } else { dl }) + 1
        if depth > depth_limit {
          raise @bitstream.ProfileConformance("decoded MA tree is too deep")
        }
        tmp.push((node, depth))
      }
      Leaf(ctx, predictor, offset, multiplier) => {
        let cluster = cluster_map[ctx]
        let leaf = { cluster, predictor, offset, multiplier, }
        tmp.push((MaTreeNode::Leaf(leaf), 0))
      }
    }
  }
  guard tmp.length() - head == 1 else { abort("assertion failed") }
  let (tree, tree_depth) = tmp[head]
  { num_tree_nodes, tree_depth, tree, decoder, }
}

///|
fn is_infinite_tree_dist(decoder : @coding.Decoder) -> Bool {
  let cluster_map = decoder.cluster_map()
  // Distribution #1 decides whether it's decision node or leaf node; if it
  // reads 0 it's a leaf node. Therefore, the tree is infinitely large if the
  // dist always reads token other than 0.
  let cluster = cluster_map[1]
  match decoder.single_token(cluster) {
    None => false
    Some(token) => token != 0
  }
}

///|
/// A "flat" meta-adaptive tree, constructed with `MaConfig::make_flat_tree`.
pub struct FlatMaTree {
  priv nodes : Array[FlatMaTreeNode]
  priv need_self_correcting : Bool
  priv max_prev_channel_depth : Int32
}

///|
priv enum FlatMaTreeNode {
  FusedDecision(
    prop_level0~ : Int32,
    value_level0~ : Int32,
    prop_l~ : Int32,
    prop_r~ : Int32,
    value_l~ : Int32,
    value_r~ : Int32,
    index_base~ : Int32,
  )
  Table(prop~ : Int32, value_base~ : Int32, indices~ : FixedArray[Int32])
  Leaf(MaTreeLeafClustered)
}

///|
#derive(Debug, Eq)
pub(all) struct MaTreeLeafClustered {
  cluster : Int32
  predictor : Predictor
  offset : Int32
  /// `u32` in upstream; always below `2^31`.
  multiplier : Int32
}

///|
fn prev_channel_depth(p : Int32) -> Int32 {
  if p >= 16 {
    (p - 16) / 4 + 1
  } else {
    0
  }
}

///|
fn FlatMaTree::new(nodes : Array[FlatMaTreeNode]) -> FlatMaTree {
  let mut need_self_correcting = false
  let mut max_prev_channel_depth = 0
  for node in nodes {
    match node {
      FusedDecision(prop_level0=p, prop_l=pl, prop_r=pr, ..) => {
        if p == 15 || pl == 15 || pr == 15 {
          need_self_correcting = true
        }
        for q in [p, pl, pr] {
          let d = prev_channel_depth(q)
          if d > max_prev_channel_depth {
            max_prev_channel_depth = d
          }
        }
      }
      Table(prop~, ..) => {
        if prop == 15 {
          need_self_correcting = true
        }
        let d = prev_channel_depth(prop)
        if d > max_prev_channel_depth {
          max_prev_channel_depth = d
        }
      }
      Leaf(leaf) =>
        if leaf.predictor == SelfCorrecting {
          need_self_correcting = true
        }
    }
  }
  { nodes, need_self_correcting, max_prev_channel_depth, }
}

///|
/// `v.saturating_sub(base).clamp(0, len - 1)`.
#inline
fn table_index(v : Int32, base : Int32, len : Int32) -> Int32 {
  let d = v.to_int64() - base.to_int64()
  if d < 0L {
    0
  } else if d > (len - 1).to_int64() {
    len - 1
  } else {
    d.to_int()
  }
}

///|
/// Walks the tree with the properties computed in `properties`.
pub fn FlatMaTree::get_leaf(
  self : FlatMaTree,
  properties : PredictorState,
) -> MaTreeLeafClustered {
  let nodes = self.nodes
  let mut current_node = nodes[0]
  while true {
    match current_node {
      FusedDecision(
        prop_level0=p,
        value_level0=v,
        prop_l=pl,
        prop_r=pr,
        value_l=vl,
        value_r=vr,
        index_base~,
      ) => {
        let next_node = if properties.get_property(p) <= v {
          index_base + (if properties.get_property(pr) <= vr { 3 } else { 2 })
        } else {
          index_base + (if properties.get_property(pl) <= vl { 1 } else { 0 })
        }
        current_node = nodes[next_node]
      }
      Table(prop~, value_base~, indices~) => {
        let v = properties.get_property(prop)
        let idx = table_index(v, value_base, indices.length())
        current_node = nodes[indices[idx]]
      }
      Leaf(leaf) => return leaf
    }
  }
  panic()
}

///|
/// Returns whether self-correcting predictor should be initialized.
pub fn FlatMaTree::need_self_correcting(self : FlatMaTree) -> Bool {
  self.need_self_correcting
}

///|
/// Returns the number of previously decoded channels needed in order to
/// traverse the MA tree.
pub fn FlatMaTree::max_prev_channel_depth(self : FlatMaTree) -> Int32 {
  self.max_prev_channel_depth
}

///|
/// Decode a sample with the given state.
pub fn FlatMaTree::decode_sample(
  self : FlatMaTree,
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  properties : PredictorState,
  dist_multiplier : Int32,
) -> (Int32, Predictor) raise @bitstream.JxlError {
  let leaf = self.get_leaf(properties)
  let diff = decoder.read_varint_with_multiplier_clustered(
    bs,
    leaf.cluster,
    dist_multiplier,
  )
  let diff = wrapping_muladd_i32(
    unpack_signed_u32(diff),
    leaf.multiplier,
    leaf.offset,
  )
  (diff, leaf.predictor)
}

///|
fn FlatMaTree::single_node(self : FlatMaTree) -> MaTreeLeafClustered? {
  match self.nodes {
    [Leaf(node), ..] => Some(node)
    _ => None
  }
}

///|
priv struct SimpleMaTable {
  decision_prop : Int32
  value_base : Int32
  predictor : Predictor
  offset : Int32
  multiplier : Int32
  cluster_table : FixedArray[Int32]
}

///|
fn FlatMaTree::simple_table(self : FlatMaTree) -> SimpleMaTable? {
  guard self.nodes is [Table(prop=decision_prop, value_base~, indices~), ..] else {
    return None
  }
  let mut state : (Predictor, Int32, Int32)? = None
  let cluster_table = FixedArray::make(indices.length(), 0)
  for i, index in indices {
    guard self.nodes[index] is Leaf(leaf) else { return None }
    let leaf_props = (leaf.predictor, leaf.offset, leaf.multiplier)
    match state {
      None => state = Some(leaf_props)
      Some(s) => if s != leaf_props { return None }
    }
    cluster_table[i] = leaf.cluster
  }
  let (predictor, offset, multiplier) = state.unwrap()
  Some({
    decision_prop,
    value_base,
    predictor,
    offset,
    multiplier,
    cluster_table,
  })
}

///|
priv enum MaTreeNode {
  Decision(
    property~ : Int32,
    value~ : Int32,
    left~ : MaTreeNode,
    right~ : MaTreeNode,
  )
  Leaf(MaTreeLeafClustered)
}

///|
fn MaTreeNode::next_decision_node(
  self : MaTreeNode,
  channel : Int32,
  stream_idx : Int32,
  prev_channels : Int32,
) -> MaTreeNode {
  let mut node = self
  while true {
    match node {
      Decision(property~, value~, left~, right~) if property == 0 ||
        property == 1 => {
        let target = if property == 0 { channel } else { stream_idx }
        node = if target > value { left } else { right }
      }
      Decision(property~, value~, left~, right~) if property >= 16 => {
        let prev_channel_idx = (property - 16) / 4
        if prev_channel_idx >= prev_channels {
          node = if value < 0 { left } else { right }
        } else {
          return node
        }
      }
      _ => return node
    }
  }
  panic()
}

///|
fn MaTreeNode::try_compile_to_table(
  self : MaTreeNode,
  channel : Int32,
  stream_idx : Int32,
  prev_channels : Int32,
  next_index_base : Int32,
) -> (FlatMaTreeNode, Array[MaTreeNode])? {
  guard self is Decision(property~, value~, left~, right~) else { return None }
  let mut lower_bound = value
  let mut upper_bound = value
  // (node, range start, range end), inclusive ranges
  let stack : Array[(MaTreeNode, Int32, Int32)] = [
    (left, value + 1, 0x7fffffff),
    (right, -0x80000000, value),
  ]
  let range_nodes : Array[(MaTreeNode, Int32)] = []
  while stack.pop() is Some((node, range_start, range_end)) {
    let node = node.next_decision_node(channel, stream_idx, prev_channels)
    guard node is Decision(property=target_property, value~, left~, right~) &&
      target_property == property else {
      range_nodes.push((node, range_end))
      continue
    }
    let new_lower_bound = if value < lower_bound { value } else { lower_bound }
    let new_upper_bound = if value > upper_bound { value } else { upper_bound }
    if new_upper_bound.to_int64() - new_lower_bound.to_int64() > 1024L - 2L {
      range_nodes.push((node, range_end))
      continue
    }
    lower_bound = new_lower_bound
    upper_bound = new_upper_bound
    let left_start = value + 1
    let left_end = range_end
    let right_start = range_start
    let right_end = value
    if left_start <= left_end {
      stack.push((left, left_start, left_end))
    }
    if right_start <= right_end {
      stack.push((right, right_start, right_end))
    }
  }
  if range_nodes.length() < 4 {
    return None
  }
  range_nodes.sort_by_key(fn(x) { x.1 })
  let index_count = (upper_bound.to_int64() - lower_bound.to_int64()).to_int() +
    2
  let indices = FixedArray::make(index_count, 0)
  let nodes = []
  let mut range_start = lower_bound - 1
  let mut next_index = 0
  for idx, item in range_nodes {
    let (node, range_end) = item
    if range_end == 0x7fffffff {
      indices[index_count - 1] = next_index_base + idx
      nodes.push(node)
      break
    }
    let len = abs_diff_i32(range_end, range_start).to_int()
    let end_index = next_index + len
    guard end_index <= index_count else { abort("index out of bounds") }
    for i in next_index..<end_index {
      indices[i] = next_index_base + idx
    }
    nodes.push(node)
    next_index = end_index
    range_start = range_end
  }
  let node = FlatMaTreeNode::Table(
    prop=property,
    value_base=lower_bound,
    indices~,
  )
  Some((node, nodes))
}

///|
fn MaTreeNode::flatten(
  self : MaTreeNode,
  channel : Int32,
  stream_idx : Int32,
  prev_channels : Int32,
) -> Array[FlatMaTreeNode] {
  let target = self.next_decision_node(channel, stream_idx, prev_channels)
  let q : Array[MaTreeNode] = [target]
  let mut head = 0
  let out = []
  let mut next_base = 1
  while head < q.length() {
    let target = q[head]
    head += 1
    let target = target.next_decision_node(channel, stream_idx, prev_channels)
    if target.try_compile_to_table(
        channel, stream_idx, prev_channels, next_base,
      )
      is Some((out_node, nodes)) {
      out.push(out_node)
      q.push_iter(nodes.iter())
      next_base += nodes.length()
      continue
    }
    match target {
      Decision(property~, value~, left~, right~) => {
        let left = left.next_decision_node(channel, stream_idx, prev_channels)
        let (lp, lv, ll, lr) = match left {
          Decision(property~, value~, left~, right~) =>
            (property, value, left, right)
          node => (0, 0, node, node)
        }
        let right = right.next_decision_node(channel, stream_idx, prev_channels)
        let (rp, rv, rl, rr) = match right {
          Decision(property~, value~, left~, right~) =>
            (property, value, left, right)
          node => (0, 0, node, node)
        }
        out.push(
          FlatMaTreeNode::FusedDecision(
            prop_level0=property,
            value_level0=value,
            prop_l=lp,
            prop_r=rp,
            value_l=lv,
            value_r=rv,
            index_base=next_base,
          ),
        )
        q.push(ll)
        q.push(lr)
        q.push(rl)
        q.push(rr)
        next_base += 4
      }
      Leaf(leaf) => out.push(FlatMaTreeNode::Leaf(leaf))
    }
  }
  out
}
