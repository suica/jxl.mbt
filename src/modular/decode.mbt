// Sample decoding routines of `image.rs` (fast paths and the generic path).

///|
priv struct RleState {
  mut value : Int32
  mut repeat : UInt32
  mut error : @bitstream.JxlError?
}

///|
fn RleState::new() -> RleState {
  { value: 0, repeat: 0, error: None, }
}

///|
#inline
fn RleState::decode(
  self : RleState,
  bs : @bitstream.Bitstream,
  decoder : @coding.DecoderRleMode,
  cluster : Int32,
) -> Int32 {
  if self.repeat == 0 {
    try decoder.read_varint_clustered(bs, cluster) catch {
      e => if self.error is None { self.error = Some(e) }
    } noraise {
      Value(v) => {
        self.value = unpack_signed_u32(v)
        self.repeat = 1
      }
      Repeat(len) => self.repeat = len
    }
  }
  self.repeat = self.repeat - 1
  self.value
}

///|
fn RleState::check_error(self : RleState) -> Unit raise @bitstream.JxlError {
  let error = self.error
  self.error = None
  if error is Some(e) {
    raise e
  }
}

///|
fn decode_single_node(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  predictor_state : PredictorState,
  wp_header : WpHeader,
  grid : @grid.SubGrid[Int32],
  node : MaTreeLeafClustered,
) -> Unit raise @bitstream.JxlError {
  let { cluster, predictor, offset, multiplier, } = node
  let height = grid.height
  let width = grid.width
  let buf = grid.buf
  match (predictor, decoder.single_token(cluster)) {
    (Zero, Some(token)) => {
      // Single token in cluster, Zero predictor: hyper fast path
      let value = wrapping_muladd_i32(
        unpack_signed_u32(token),
        multiplier,
        offset,
      )
      for y in 0..<height {
        let off = grid.row_offset(y)
        for x in 0..<width {
          buf[off + x] = value
        }
      }
    }
    (Zero, None) =>
      // Zero predictor: fast path
      for y in 0..<height {
        let off = grid.row_offset(y)
        for x in 0..<width {
          let token = decoder.read_varint_with_multiplier_clustered(
            bs, cluster, dist_multiplier,
          )
          buf[off + x] = wrapping_muladd_i32(
            unpack_signed_u32(token),
            multiplier,
            offset,
          )
        }
      }
    (Gradient, _) if offset == 0 && multiplier == 1 =>
      // Simple gradient: quite fast path
      decode_simple_grad(bs, decoder, cluster, dist_multiplier, grid)
    _ => {
      let wp_header = if predictor == SelfCorrecting {
        Some(wp_header)
      } else {
        None
      }
      predictor_state.reset(grid.width, [], wp_header)
      decode_single_node_slow(
        bs, decoder, dist_multiplier, node, predictor_state, grid,
      )
    }
  }
}

///|
fn decode_fast_lossless(
  bs : @bitstream.Bitstream,
  decoder : @coding.DecoderRleMode,
  rle_state : RleState,
  cluster : Int32,
  grid : @grid.SubGrid[Int32],
) -> Unit {
  let height = grid.height
  let width = grid.width
  let buf = grid.buf
  if height == 0 {
    return
  }
  let mut w = 0
  let off = grid.row_offset(0)
  for x in 0..<width {
    let token = rle_state.decode(bs, decoder, cluster)
    w = w + token
    buf[off + x] = w
  }
  for y in 1..<height {
    let prev = grid.row_offset(y - 1)
    let out = grid.row_offset(y)
    if width == 0 {
      continue
    }
    let token = rle_state.decode(bs, decoder, cluster)
    let mut w = token + buf[prev]
    buf[out] = w
    for x in 1..<width {
      let nw = buf[prev + x - 1]
      let n = buf[prev + x]
      let pred = grad_clamped(n, w, nw)
      let token = rle_state.decode(bs, decoder, cluster)
      w = token + pred
      buf[out + x] = w
    }
  }
}

///|
fn decode_simple_grad(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  cluster : Int32,
  dist_multiplier : Int32,
  grid : @grid.SubGrid[Int32],
) -> Unit raise @bitstream.JxlError {
  let width = grid.width
  let height = grid.height
  let buf = grid.buf
  if height == 0 {
    return
  }
  let mut w = 0
  let off = grid.row_offset(0)
  for x in 0..<width {
    let token = decoder.read_varint_with_multiplier_clustered(
      bs, cluster, dist_multiplier,
    )
    w = unpack_signed_u32(token) + w
    buf[off + x] = w
  }
  for y in 1..<height {
    let prev = grid.row_offset(y - 1)
    let out = grid.row_offset(y)
    if width == 0 {
      continue
    }
    let token = decoder.read_varint_with_multiplier_clustered(
      bs, cluster, dist_multiplier,
    )
    let mut w = unpack_signed_u32(token) + buf[prev]
    buf[out] = w
    for x in 1..<width {
      let nw = buf[prev + x - 1]
      let n = buf[prev + x]
      let pred = grad_clamped(n, w, nw)
      let token = decoder.read_varint_with_multiplier_clustered(
        bs, cluster, dist_multiplier,
      )
      w = unpack_signed_u32(token) + pred
      buf[out + x] = w
    }
  }
}

///|
#inline
fn decode_one(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  leaf : MaTreeLeafClustered,
  properties : PredictorState,
) -> Int32 raise @bitstream.JxlError {
  let diff = unpack_signed_u32(
    decoder.read_varint_with_multiplier_clustered(
      bs,
      leaf.cluster,
      dist_multiplier,
    ),
  )
  let diff = wrapping_muladd_i32(diff, leaf.multiplier, leaf.offset)
  diff + leaf.predictor.predict(properties)
}

///|
fn decode_single_node_slow(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  leaf : MaTreeLeafClustered,
  predictor : PredictorState,
  grid : @grid.SubGrid[Int32],
) -> Unit raise @bitstream.JxlError {
  let height = grid.height
  let width = grid.width
  let buf = grid.buf
  for y in 0..<height {
    let off = grid.row_offset(y)
    for x in 0..<width {
      predictor.properties()
      let true_value = decode_one(bs, decoder, dist_multiplier, leaf, predictor)
      buf[off + x] = true_value
      predictor.record(true_value)
    }
  }
}

///|
fn decode_simple_table(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  predictor_state : PredictorState,
  wp_header : WpHeader,
  grid : @grid.SubGrid[Int32],
  table : SimpleMaTable,
) -> Unit raise @bitstream.JxlError {
  if table.offset == 0 &&
    table.multiplier == 1 &&
    table.decision_prop == 9 &&
    table.predictor == Gradient {
    return decode_gradient_table(
      bs,
      decoder,
      dist_multiplier,
      grid,
      table.value_base,
      table.cluster_table,
    )
  }
  decode_simple_table_slow(
    bs, decoder, dist_multiplier, predictor_state, wp_header, grid, table,
  )
}

///|
#inline
fn cluster_from_table(
  sample : Int32,
  value_base : Int32,
  cluster_table : FixedArray[Int32],
) -> Int32 {
  cluster_table[table_index(sample, value_base, cluster_table.length())]
}

///|
fn decode_gradient_table(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  grid : @grid.SubGrid[Int32],
  value_base : Int32,
  cluster_table : FixedArray[Int32],
) -> Unit raise @bitstream.JxlError {
  let width = grid.width
  let height = grid.height
  let buf = grid.buf
  if height == 0 {
    return
  }
  let mut w = 0
  let off = grid.row_offset(0)
  for x in 0..<width {
    let cluster = cluster_from_table(w, value_base, cluster_table)
    let token = decoder.read_varint_with_multiplier_clustered(
      bs, cluster, dist_multiplier,
    )
    w = unpack_signed_u32(token) + w
    buf[off + x] = w
  }
  for y in 1..<height {
    let prev = grid.row_offset(y - 1)
    let out = grid.row_offset(y)
    if width == 0 {
      continue
    }
    let cluster = cluster_from_table(buf[prev], value_base, cluster_table)
    let token = decoder.read_varint_with_multiplier_clustered(
      bs, cluster, dist_multiplier,
    )
    let mut w = unpack_signed_u32(token) + buf[prev]
    buf[out] = w
    for x in 1..<width {
      let nw = buf[prev + x - 1]
      let n = buf[prev + x]
      let prop = n + w - nw
      let pred = grad_clamped(n, w, nw)
      let cluster = cluster_from_table(prop, value_base, cluster_table)
      let token = decoder.read_varint_with_multiplier_clustered(
        bs, cluster, dist_multiplier,
      )
      w = unpack_signed_u32(token) + pred
      buf[out + x] = w
    }
  }
}

///|
#inline
fn decode_table_one(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  table : SimpleMaTable,
  properties : PredictorState,
) -> Int32 raise @bitstream.JxlError {
  let prop_value = properties.get_property(table.decision_prop)
  let cluster = cluster_from_table(
    prop_value,
    table.value_base,
    table.cluster_table,
  )
  let diff = unpack_signed_u32(
    decoder.read_varint_with_multiplier_clustered(bs, cluster, dist_multiplier),
  )
  let diff = wrapping_muladd_i32(diff, table.multiplier, table.offset)
  diff + table.predictor.predict(properties)
}

///|
fn decode_simple_table_slow(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  predictor_state : PredictorState,
  wp_header : WpHeader,
  grid : @grid.SubGrid[Int32],
  table : SimpleMaTable,
) -> Unit raise @bitstream.JxlError {
  let need_wp_header = table.decision_prop == 15 ||
    table.predictor == SelfCorrecting
  let wp_header = if need_wp_header { Some(wp_header) } else { None }
  predictor_state.reset(grid.width, [], wp_header)
  let height = grid.height
  let width = grid.width
  let buf = grid.buf
  for y in 0..<height {
    let off = grid.row_offset(y)
    for x in 0..<width {
      predictor_state.properties()
      let true_value = decode_table_one(
        bs, decoder, dist_multiplier, table, predictor_state,
      )
      buf[off + x] = true_value
      predictor_state.record(true_value)
    }
  }
}

///|
fn decode_slow(
  bs : @bitstream.Bitstream,
  decoder : @coding.Decoder,
  dist_multiplier : Int32,
  ma_tree : FlatMaTree,
  predictor : PredictorState,
  grid : @grid.SubGrid[Int32],
) -> Unit raise @bitstream.JxlError {
  let height = grid.height
  let width = grid.width
  let buf = grid.buf
  for y in 0..<height {
    let off = grid.row_offset(y)
    for x in 0..<width {
      predictor.properties()
      let leaf = ma_tree.get_leaf(predictor)
      let true_value = decode_one(bs, decoder, dist_multiplier, leaf, predictor)
      buf[off + x] = true_value
      predictor.record(true_value)
    }
  }
}
