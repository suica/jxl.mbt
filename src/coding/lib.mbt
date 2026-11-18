// Port of jxl-coding/src/lib.rs
//
// This package provides [Decoder], an entropy decoder, implemented as
// specified in the JPEG XL specification.
//
// This also provides [read_permutation] and [read_clusters], which are used in
// some parts of the specification.

///|
/// An entropy decoder.
///
/// Integer types: contexts and clusters are `Int`; decoded values are `UInt`
/// (Rust `u32`), so they can be passed to `@bitstream.unpack_signed`.
struct Decoder {
  lz77 : Lz77
  inner : DecoderInner
}

///|
/// Create a decoder by reading symbol distribution, integer configurations and
/// LZ77 configuration from the bitstream.
pub fn Decoder::parse(
  bitstream : @bitstream.Bitstream,
  num_dist : Int32,
) -> Decoder raise @bitstream.JxlError {
  let lz77 = Lz77::parse(bitstream)
  let num_dist = if lz77 is Disabled { num_dist } else { num_dist + 1 }
  let inner = DecoderInner::parse(bitstream, num_dist)
  { lz77, inner, }
}

///|
fn Decoder::parse_assume_no_lz77(
  bitstream : @bitstream.Bitstream,
  num_dist : Int32,
) -> Decoder raise @bitstream.JxlError {
  let lz77_enabled = bitstream.read_bool()
  if lz77_enabled {
    raise coding_error("Lz77NotAllowed")
  }
  let inner = DecoderInner::parse(bitstream, num_dist)
  { lz77: Disabled, inner, }
}

///|
/// An independent copy of the decoder (Rust `Clone`): distributions are
/// shared, the ANS state and the LZ77 window are copied.
pub fn Decoder::clone(self : Decoder) -> Decoder {
  { lz77: self.lz77.clone(), inner: self.inner.clone(), }
}

///|
/// Read an integer from the bitstream with the given context.
#inline
pub fn Decoder::read_varint(
  self : Decoder,
  bitstream : @bitstream.Bitstream,
  ctx : Int32,
) -> UInt32 raise @bitstream.JxlError {
  self.read_varint_with_multiplier(bitstream, ctx, 0)
}

///|
/// Read an integer from the bitstream with the given context and LZ77 distance
/// multiplier.
#inline
pub fn Decoder::read_varint_with_multiplier(
  self : Decoder,
  bitstream : @bitstream.Bitstream,
  ctx : Int32,
  dist_multiplier : Int32,
) -> UInt32 raise @bitstream.JxlError {
  let cluster = self.inner.clusters[ctx]
  self.read_varint_with_multiplier_clustered(
    bitstream, cluster, dist_multiplier,
  )
}

///|
/// Read an integer from the bitstream with the given *cluster* and LZ77
/// distance multiplier.
///
/// Contexts can be converted to clusters using [the cluster map][Decoder::cluster_map].
#inline
pub fn Decoder::read_varint_with_multiplier_clustered(
  self : Decoder,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
  dist_multiplier : Int32,
) -> UInt32 raise @bitstream.JxlError {
  match self.lz77 {
    Enabled(min_symbol~, min_length~, state~) =>
      self.inner.read_varint_with_multiplier_clustered_lz77(
        bitstream, cluster, dist_multiplier, state, min_symbol, min_length,
      )
    Disabled =>
      self.inner.read_varint_with_multiplier_clustered(bitstream, cluster)
  }
}

///|
/// Converts the decoder to one in RLE mode.
pub fn Decoder::as_rle(self : Decoder) -> DecoderRleMode? {
  guard self.lz77 is Enabled(state~, min_symbol~, min_length~) else {
    return None
  }
  let lz_cluster = self.inner.lz_dist_cluster()
  let lz_conf = self.inner.configs[lz_cluster]
  let sym = self.inner.code.single_symbol(lz_cluster)
  if sym < 0 {
    return None
  }
  if sym == 1 && lz_conf.split_exponent == 0 {
    Some({
      inner: self.inner,
      min_symbol,
      min_length,
      len_config: state.lz_len_conf,
    })
  } else {
    None
  }
}

///|
/// Converts the decoder to LZ77-enabled one.
pub fn Decoder::as_with_lz77(self : Decoder) -> DecoderWithLz77? {
  match self.lz77 {
    Enabled(state~, min_symbol~, min_length~) =>
      Some({ inner: self.inner, state, min_symbol, min_length, })
    Disabled => None
  }
}

///|
/// Converts the decoder to one without LZ77.
pub fn Decoder::as_no_lz77(self : Decoder) -> DecoderNoLz77? {
  match self.lz77 {
    Disabled => Some({ inner: self.inner, })
    Enabled(..) => None
  }
}

///|
/// Returns the token to be decoded if the decoder always emits single token
/// repeatedly.
#inline
pub fn Decoder::single_token(self : Decoder, cluster : Int32) -> UInt32? {
  if self.lz77 is Enabled(..) {
    return None
  }
  self.inner.single_token(cluster)
}

///|
/// Explicitly start reading an entropy encoded stream.
///
/// This involves reading an initial state for the ANS stream. It's okay to skip
/// this method, as the state will be initialized on the first read.
pub fn Decoder::begin(
  self : Decoder,
  bitstream : @bitstream.Bitstream,
) -> Unit raise @bitstream.JxlError {
  self.inner.code.begin(bitstream)
}

///|
/// Finalizes the stream, and check whether the stream was valid.
///
/// For prefix code stream, this method will always succeed. For ANS streams,
/// this method checks if the final state matches expected state, which is
/// specified in the specification.
pub fn Decoder::finalize(self : Decoder) -> Unit raise @bitstream.JxlError {
  self.inner.code.finalize()
}

///|
/// Returns the cluster mapping of distributions (context -> cluster). Do not
/// modify the returned array.
#inline
pub fn Decoder::cluster_map(self : Decoder) -> FixedArray[Int32] {
  self.inner.clusters
}

///|
/// An entropy decoder in RLE mode. It shares the state of the [Decoder] it
/// was created from.
struct DecoderRleMode {
  inner : DecoderInner
  min_symbol : Int32
  min_length : Int32
  len_config : IntegerConfig
}

///|
/// Decoded token from an entropy decoder in RLE mode.
#derive(Eq, Debug)
pub(all) enum RleToken {
  /// Emit the given value once.
  Value(UInt32)
  /// Repeat previously decoded value by the given number of times.
  Repeat(UInt32)
}

///|
/// Read an integer from the bitstream with the given *cluster*.
///
/// Contexts can be converted to clusters using [the cluster map][DecoderRleMode::cluster_map].
pub fn DecoderRleMode::read_varint_clustered(
  self : DecoderRleMode,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
) -> RleToken raise @bitstream.JxlError {
  let packed = self.read_varint_clustered_packed(bitstream, cluster)
  if packed < 0L {
    Repeat((-1L - packed).to_uint())
  } else {
    Value(packed.to_uint())
  }
}

///|
/// Allocation-free variant of [DecoderRleMode::read_varint_clustered]:
/// returns `v` (>= 0) for `Value(v)` and `-1 - n` (< 0) for `Repeat(n)`.
#inline
pub fn DecoderRleMode::read_varint_clustered_packed(
  self : DecoderRleMode,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
) -> Int64 raise @bitstream.JxlError {
  let token = self.inner.code.read_symbol(bitstream, cluster)
  if token >= self.min_symbol {
    let n = self.inner.read_uint_prefilled(
        bitstream,
        self.len_config,
        token - self.min_symbol,
      ) +
      self.min_length.reinterpret_as_uint()
    -1L - n.to_uint64().reinterpret_as_int64()
  } else {
    self.inner
    .read_uint_prefilled(bitstream, self.inner.configs[cluster], token)
    .to_uint64()
    .reinterpret_as_int64()
  }
}

///|
/// Returns the cluster mapping of distributions.
pub fn DecoderRleMode::cluster_map(self : DecoderRleMode) -> FixedArray[Int32] {
  self.inner.clusters
}

///|
/// A LZ77-enabled entropy decoder. It shares the state of the [Decoder] it was
/// created from.
struct DecoderWithLz77 {
  inner : DecoderInner
  state : Lz77State
  min_symbol : Int32
  min_length : Int32
}

///|
/// Read an integer from the bitstream with the given *cluster* and LZ77
/// distance multiplier.
#inline
pub fn DecoderWithLz77::read_varint_with_multiplier_clustered(
  self : DecoderWithLz77,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
  dist_multiplier : Int32,
) -> UInt32 raise @bitstream.JxlError {
  self.inner.read_varint_with_multiplier_clustered_lz77(
    bitstream,
    cluster,
    dist_multiplier,
    self.state,
    self.min_symbol,
    self.min_length,
  )
}

///|
/// Returns the cluster mapping of distributions.
pub fn DecoderWithLz77::cluster_map(
  self : DecoderWithLz77,
) -> FixedArray[Int32] {
  self.inner.clusters
}

///|
/// An entropy decoder without LZ77. It shares the state of the [Decoder] it
/// was created from.
struct DecoderNoLz77 {
  inner : DecoderInner
}

///|
/// Read an integer from the bitstream with the given *cluster*.
#inline
pub fn DecoderNoLz77::read_varint_clustered(
  self : DecoderNoLz77,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
) -> UInt32 raise @bitstream.JxlError {
  self.inner.read_varint_with_multiplier_clustered(bitstream, cluster)
}

///|
/// Returns the token to be decoded if the decoder always emits single token
/// repeatedly.
#inline
pub fn DecoderNoLz77::single_token(
  self : DecoderNoLz77,
  cluster : Int32,
) -> UInt32? {
  self.inner.single_token(cluster)
}

///|
/// Returns the cluster mapping of distributions.
pub fn DecoderNoLz77::cluster_map(self : DecoderNoLz77) -> FixedArray[Int32] {
  self.inner.clusters
}

///|
priv enum Lz77 {
  Disabled
  Enabled(min_symbol~ : Int32, min_length~ : Int32, state~ : Lz77State)
}

///|
fn Lz77::parse(
  bitstream : @bitstream.Bitstream,
) -> Lz77 raise @bitstream.JxlError {
  if bitstream.read_bool() {
    // enabled
    let min_symbol = bitstream
      .read_u32(
        @bitstream.c(224),
        @bitstream.c(512),
        @bitstream.c(4096),
        @bitstream.cu(8, 15),
      )
      .reinterpret_as_int()
    let min_length = bitstream
      .read_u32(
        @bitstream.c(3),
        @bitstream.c(4),
        @bitstream.cu(5, 2),
        @bitstream.cu(9, 8),
      )
      .reinterpret_as_int()
    let lz_len_conf = IntegerConfig::parse(bitstream, 8)
    Enabled(min_symbol~, min_length~, state=Lz77State::new(lz_len_conf))
  } else {
    Disabled
  }
}

///|
fn Lz77::clone(self : Lz77) -> Lz77 {
  match self {
    Disabled => Disabled
    Enabled(min_symbol~, min_length~, state~) =>
      Enabled(min_symbol~, min_length~, state=state.clone())
  }
}

///|
priv struct Lz77State {
  lz_len_conf : IntegerConfig
  window : Array[UInt32]
  mut num_to_copy : UInt32
  mut copy_pos : UInt32
  mut num_decoded : UInt32
}

///|
fn Lz77State::new(lz_len_conf : IntegerConfig) -> Lz77State {
  { lz_len_conf, window: [], num_to_copy: 0, copy_pos: 0, num_decoded: 0, }
}

///|
fn Lz77State::clone(self : Lz77State) -> Lz77State {
  {
    lz_len_conf: self.lz_len_conf,
    window: self.window.copy(),
    num_to_copy: self.num_to_copy,
    copy_pos: self.copy_pos,
    num_decoded: self.num_decoded,
  }
}

///|
/// Hybrid integer configuration.
priv struct IntegerConfig {
  split_exponent : Int32
  split : Int32
  msb_in_token : Int32
  lsb_in_token : Int32
}

///|
fn IntegerConfig::parse(
  bitstream : @bitstream.Bitstream,
  log_alphabet_size : Int32,
) -> IntegerConfig raise @bitstream.JxlError {
  let split_exponent_bits = add_log2_ceil(
    log_alphabet_size.reinterpret_as_uint(),
  )
  let split_exponent = bitstream.read_bits_int(split_exponent_bits)
  let mut msb_in_token = 0
  let mut lsb_in_token = 0
  if split_exponent != log_alphabet_size {
    let msb_bits = add_log2_ceil(split_exponent.reinterpret_as_uint())
    msb_in_token = bitstream.read_bits_int(msb_bits)
    if msb_in_token > split_exponent {
      raise coding_error("InvalidIntegerConfig")
    }
    let lsb_bits = add_log2_ceil(
      (split_exponent - msb_in_token).reinterpret_as_uint(),
    )
    lsb_in_token = bitstream.read_bits_int(lsb_bits)
  }
  if lsb_in_token + msb_in_token > split_exponent {
    raise coding_error("InvalidIntegerConfig")
  }
  { split_exponent, split: 1 << split_exponent, msb_in_token, lsb_in_token, }
}

///|
priv struct DecoderInner {
  /// num_dist, [0, num_clusters)
  clusters : FixedArray[Int32]
  /// num_clusters
  configs : FixedArray[IntegerConfig]
  code : Coder
}

///|
fn DecoderInner::clone(self : DecoderInner) -> DecoderInner {
  { clusters: self.clusters, configs: self.configs, code: self.code.clone(), }
}

///|
fn DecoderInner::parse(
  bitstream : @bitstream.Bitstream,
  num_dist : Int32,
) -> DecoderInner raise @bitstream.JxlError {
  let (num_clusters, clusters) = read_clusters(bitstream, num_dist)
  let use_prefix_code = bitstream.read_bool()
  let log_alphabet_size = if use_prefix_code {
    15
  } else {
    bitstream.read_bits_int(2) + 5
  }
  let configs_arr : Array[IntegerConfig] = Array(capacity=num_clusters)
  for _ in 0..<num_clusters {
    configs_arr.push(IntegerConfig::parse(bitstream, log_alphabet_size))
  }
  let configs = FixedArray::from_array(configs_arr)
  let code = if use_prefix_code {
    let counts = FixedArray::make(num_clusters, 0)
    for i in 0..<num_clusters {
      let count = if bitstream.read_bool() {
        let n = bitstream.read_bits_int(4)
        1 + (1 << n) + bitstream.read_bits_int(n)
      } else {
        1
      }
      if count > 1 << 15 {
        raise coding_error("InvalidPrefixHistogram")
      }
      counts[i] = count
    }
    let dist : Array[PrefixHistogram] = Array(capacity=num_clusters)
    for count in counts {
      dist.push(PrefixHistogram::parse(bitstream, count))
    }
    PrefixCode(FixedArray::from_array(dist))
  } else {
    let dist : Array[AnsHistogram] = Array(capacity=num_clusters)
    for _ in 0..<num_clusters {
      dist.push(AnsHistogram::parse(bitstream, log_alphabet_size))
    }
    Ans({ dist: FixedArray::from_array(dist), state: 0, initial: true, })
  }
  { clusters, configs, code, }
}

///|
#inline
fn DecoderInner::single_token(self : DecoderInner, cluster : Int32) -> UInt32? {
  let single_symbol = self.code.single_symbol(cluster)
  if single_symbol >= 0 && single_symbol < self.configs[cluster].split {
    Some(single_symbol.reinterpret_as_uint())
  } else {
    None
  }
}

///|
#inline
fn DecoderInner::read_varint_with_multiplier_clustered(
  self : DecoderInner,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
) -> UInt32 raise @bitstream.JxlError {
  let token = self.code.read_symbol(bitstream, cluster)
  self.read_uint_prefilled(bitstream, self.configs[cluster], token)
}

///|
/// `SPECIAL_DISTANCES: [[i8; 2]; 120]`, flattened.
let special_distances : FixedArray[Int32] = [
  0, 1, 1, 0, 1, 1, -1, 1, 0, 2, 2, 0, 1, 2, -1, 2, 2, 1, -2, 1, 2, 2, -2, 2, 0,
  3, 3, 0, 1, 3, -1, 3, 3, 1, -3, 1, 2, 3, -2, 3, 3, 2, -3, 2, 0, 4, 4, 0, 1, 4,
  -1, 4, 4, 1, -4, 1, 3, 3, -3, 3, 2, 4, -2, 4, 4, 2, -4, 2, 0, 5, 3, 4, -3, 4, 4,
  3, -4, 3, 5, 0, 1, 5, -1, 5, 5, 1, -5, 1, 2, 5, -2, 5, 5, 2, -5, 2, 4, 4, -4, 4,
  3, 5, -3, 5, 5, 3, -5, 3, 0, 6, 6, 0, 1, 6, -1, 6, 6, 1, -6, 1, 2, 6, -2, 6, 6,
  2, -6, 2, 4, 5, -4, 5, 5, 4, -5, 4, 3, 6, -3, 6, 6, 3, -6, 3, 0, 7, 7, 0, 1, 7,
  -1, 7, 5, 5, -5, 5, 7, 1, -7, 1, 4, 6, -4, 6, 6, 4, -6, 4, 2, 7, -2, 7, 7, 2, -7,
  2, 3, 7, -3, 7, 7, 3, -7, 3, 5, 6, -5, 6, 6, 5, -6, 5, 8, 0, 4, 7, -4, 7, 7, 4,
  -7, 4, 8, 1, 8, 2, 6, 6, -6, 6, 8, 3, 5, 7, -5, 7, 7, 5, -7, 5, 8, 4, 6, 7, -6,
  7, 7, 6, -7, 6, 8, 5, 7, 7, -7, 7, 8, 6, 8, 7,
]

///|
fn DecoderInner::read_varint_with_multiplier_clustered_lz77(
  self : DecoderInner,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
  dist_multiplier : Int32,
  state : Lz77State,
  min_symbol : Int32,
  min_length : Int32,
) -> UInt32 raise @bitstream.JxlError {
  let r = if state.num_to_copy > 0 {
    let r = state.window[(state.copy_pos & 0xfffff).reinterpret_as_int()]
    state.copy_pos += 1
    state.num_to_copy -= 1
    r
  } else {
    let token = self.code.read_symbol(bitstream, cluster)
    if token >= min_symbol {
      if state.num_decoded == 0 {
        // LZ77 repeat symbol encountered without decoding any symbols
        raise coding_error("UnexpectedLz77Repeat")
      }
      let lz_dist_cluster = self.lz_dist_cluster()
      let num_to_copy = self.read_uint_prefilled(
        bitstream,
        state.lz_len_conf,
        token - min_symbol,
      )
      let sum = num_to_copy + min_length.reinterpret_as_uint()
      if sum < num_to_copy {
        // LZ77 num_to_copy overflow
        raise coding_error("InvalidLz77Symbol")
      }
      state.num_to_copy = sum
      let token = self.code.read_symbol(bitstream, lz_dist_cluster)
      let distance = self.read_uint_prefilled(
        bitstream,
        self.configs[lz_dist_cluster],
        token,
      )
      let distance : UInt32 = if dist_multiplier == 0 {
        distance
      } else if distance < 120 {
        let d = distance.reinterpret_as_int()
        let offset = special_distances[2 * d]
        let dist = special_distances[2 * d + 1]
        let dist = offset + dist_multiplier * dist
        let dist = dist - 1
        (if dist < 0 { 0 } else { dist }).reinterpret_as_uint()
      } else {
        distance - 120
      }
      let distance = if distance < 0xfffff { distance } else { 0xfffff }
      let distance = distance + 1
      let distance = if distance < state.num_decoded {
        distance
      } else {
        state.num_decoded
      }
      state.copy_pos = state.num_decoded - distance
      let r = state.window[(state.copy_pos & 0xfffff).reinterpret_as_int()]
      state.copy_pos += 1
      state.num_to_copy -= 1
      r
    } else {
      self.read_uint_prefilled(bitstream, self.configs[cluster], token)
    }
  }
  let offset = (state.num_decoded & 0xfffff).reinterpret_as_int()
  if state.window.length() <= offset {
    state.window.push(r)
  } else {
    state.window[offset] = r
  }
  state.num_decoded += 1
  r
}

///|
/// Decodes the rest of a hybrid integer whose token was just read; the bit
/// buffer has been refilled by the symbol read.
#inline
fn DecoderInner::read_uint_prefilled(
  self : DecoderInner,
  bitstream : @bitstream.Bitstream,
  config : IntegerConfig,
  token : Int32,
) -> UInt32 {
  ignore(self)
  if token < config.split {
    return token.reinterpret_as_uint()
  }
  let msb_in_token = config.msb_in_token
  let lsb_in_token = config.lsb_in_token
  let ml = msb_in_token + lsb_in_token
  let n = config.split_exponent - ml + ((token - config.split) >> ml)
  // n < 32.
  let n = n & 31
  let rest_bits = bitstream.peek_bits_prefilled(n)
  bitstream.consume_bits(n) catch {
    _ => ()
  }
  let low_bits = (token & ((1 << lsb_in_token) - 1)).reinterpret_as_uint()
  let token = token >> lsb_in_token
  let token = token & ((1 << msb_in_token) - 1)
  let token = (token | (1 << msb_in_token)).reinterpret_as_uint()
  // The result fits in u32 (computed as u64 upstream, then truncated).
  (((token << n) | rest_bits) << lsb_in_token) | low_bits
}

///|
#inline
fn DecoderInner::lz_dist_cluster(self : DecoderInner) -> Int32 {
  self.clusters[self.clusters.length() - 1]
}

///|
priv enum Coder {
  PrefixCode(FixedArray[PrefixHistogram])
  Ans(AnsCoder)
}

///|
priv struct AnsCoder {
  dist : FixedArray[AnsHistogram]
  mut state : UInt32
  mut initial : Bool
}

///|
fn Coder::clone(self : Coder) -> Coder {
  match self {
    PrefixCode(_) => self
    Ans(a) => Ans({ dist: a.dist, state: a.state, initial: a.initial, })
  }
}

///|
#inline
fn Coder::read_symbol(
  self : Coder,
  bitstream : @bitstream.Bitstream,
  cluster : Int32,
) -> Int32 raise @bitstream.JxlError {
  match self {
    PrefixCode(dist) => dist[cluster].read_symbol(bitstream)
    Ans(a) => {
      if a.initial {
        a.state = bitstream.read_bits(32)
        a.initial = false
      }
      a.read_symbol_from(a.dist[cluster], bitstream)
    }
  }
}

///|
/// The single symbol of the cluster, or -1.
fn Coder::single_symbol(self : Coder, cluster : Int32) -> Int32 {
  match self {
    PrefixCode(dist) => dist[cluster].single_symbol()
    Ans(a) => a.dist[cluster].single_symbol
  }
}

///|
fn Coder::begin(
  self : Coder,
  bitstream : @bitstream.Bitstream,
) -> Unit raise @bitstream.JxlError {
  match self {
    PrefixCode(_) => ()
    Ans(a) => {
      a.state = bitstream.read_bits(32)
      a.initial = false
    }
  }
}

///|
fn Coder::finalize(self : Coder) -> Unit raise @bitstream.JxlError {
  match self {
    PrefixCode(_) => ()
    Ans(a) => if a.state != 0x130000 { raise coding_error("InvalidAnsStream") }
  }
}

///|
/// `(x + 1).next_power_of_two().trailing_zeros()`, i.e. the bit length of x.
fn add_log2_ceil(x : UInt32) -> Int32 {
  if x >= 0x80000000 {
    32
  } else {
    32 - x.clz()
  }
}

///|
/// Read a distribution clustering from the bitstream.
///
/// Returns `(num_clusters, cluster map)`.
pub fn read_clusters(
  bitstream : @bitstream.Bitstream,
  num_dist : Int32,
) -> (Int32, FixedArray[Int32]) raise @bitstream.JxlError {
  if num_dist == 1 {
    return (1, [0])
  }
  let cluster = FixedArray::make(num_dist, 0)
  if bitstream.read_bool() {
    // simple dist
    let nbits = bitstream.read_bits_int(2)
    for i in 0..<num_dist {
      cluster[i] = bitstream.read_bits_int(nbits)
    }
  } else {
    let use_mtf = bitstream.read_bool()
    let decoder = if num_dist <= 2 {
      Decoder::parse_assume_no_lz77(bitstream, 1)
    } else {
      Decoder::parse(bitstream, 1)
    }
    decoder.begin(bitstream)
    for i in 0..<num_dist {
      let b = decoder.read_varint(bitstream, 0)
      if b > 255 {
        raise coding_error("InvalidCluster")
      }
      cluster[i] = b.reinterpret_as_int()
    }
    decoder.finalize()
    if use_mtf {
      let mtfmap = FixedArray::makei(256, i => i)
      for i in 0..<num_dist {
        let idx = cluster[i]
        let v = mtfmap[idx]
        cluster[i] = v
        for j = idx; j > 0; j = j - 1 {
          mtfmap[j] = mtfmap[j - 1]
        }
        mtfmap[0] = v
      }
    }
  }
  let mut max = 0
  let seen = FixedArray::make(256, false)
  let mut num_actual_clusters = 0
  for c in cluster {
    if c > max {
      max = c
    }
    if !seen[c] {
      seen[c] = true
      num_actual_clusters += 1
    }
  }
  let num_clusters = max + 1
  if num_actual_clusters != num_clusters {
    // distribution cluster has a hole
    raise coding_error("ClusterHole")
  }
  (num_clusters, cluster)
}
