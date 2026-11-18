// Port of c/dec/decode.c (Google brotli v1.1.0, MIT License).
//
// The C decoder is a resumable streaming state machine. This port decodes a
// whole input buffer in one pass (the streaming wrapper `DecompressorWriter`
// buffers its input), keeping the same algorithms, tables and validity checks.
// The whole output is kept in memory, so the ring buffer is the output itself.

///|
const NUM_LITERAL_SYMBOLS = 256

///|
const NUM_COMMAND_SYMBOLS = 704

///|
const NUM_BLOCK_LEN_SYMBOLS = 26

///|
const NUM_DISTANCE_SHORT_CODES = 16

///|
const MAX_DISTANCE_BITS = 24

///|
const LITERAL_CONTEXT_BITS = 6

///|
const DISTANCE_CONTEXT_BITS = 2

///|
const BLOCK_SIZE_CAP : Int32 = 1 << 24

///|
const WINDOW_GAP = 16

///|
const MAX_ALLOWED_DISTANCE = 0x7FFFFFFC

///|
const INITIAL_REPEATED_CODE_LENGTH = 8

///|
const REPEAT_PREVIOUS_CODE_LENGTH = 16

///|
const MIN_DICTIONARY_WORD_LENGTH = 4

///|
const MAX_DICTIONARY_WORD_LENGTH = 31

///|
let code_length_code_order : FixedArray[Int32] = [
  1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]

///|
/// Static prefix code for the complex code length code lengths.
let code_length_prefix_length : FixedArray[Int32] = [
  2, 2, 2, 3, 2, 2, 2, 4, 2, 2, 2, 3, 2, 2, 2, 4,
]

///|
let code_length_prefix_value : FixedArray[Int32] = [
  0, 4, 3, 2, 0, 4, 3, 1, 0, 4, 3, 2, 0, 4, 3, 5,
]

///|
fn brotli_error(name : String) -> @bitstream.JxlError {
  @bitstream.JxlError::Brotli(name)
}

///|
/// Growable output buffer; doubles as the LZ77 history.
priv struct OutBuf {
  mut data : FixedArray[Byte]
  mut len : Int32
}

///|
fn OutBuf::reserve(self : OutBuf, extra : Int32) -> Unit {
  let need = self.len + extra
  if need > self.data.length() {
    let mut cap = if self.data.length() < 1024 {
      1024
    } else {
      self.data.length()
    }
    while cap < need {
      cap = cap * 2
    }
    let nd = FixedArray::make(cap, b'\x00')
    nd.unsafe_blit(0, self.data, 0, self.len)
    self.data = nd
  }
}

///|
fn OutBuf::to_bytes(self : OutBuf) -> Bytes {
  Bytes::makei(self.len, fn(i) { self.data[i] })
}

///|
priv struct Decoder {
  br : BitReader
  out : OutBuf
  dict : Bytes
  mut window_bits : Int32
  mut max_backward_distance : Int32
  mut max_distance : Int32
  dist_rb : FixedArray[Int32]
  mut dist_rb_idx : Int32
  // Metablock state
  mut is_last_metablock : Bool
  mut is_uncompressed : Bool
  mut is_metadata : Bool
  mut meta_block_remaining_len : Int32
  num_block_types : FixedArray[Int32]
  block_length : FixedArray[Int32]
  block_type_rb : FixedArray[Int32]
  block_type_trees : Array[FixedArray[Int32]]
  block_len_trees : Array[FixedArray[Int32]]
  mut distance_postfix_bits : Int32
  mut num_direct_distance_codes : Int32
  mut context_modes : FixedArray[Int32]
  mut context_map : FixedArray[Int32]
  mut dist_context_map : FixedArray[Int32]
  mut literal_htrees : Array[FixedArray[Int32]]
  mut insert_copy_htrees : Array[FixedArray[Int32]]
  mut distance_htrees : Array[FixedArray[Int32]]
  mut context_map_slice : Int32
  mut dist_context_map_slice : Int32
  mut context_lookup : Int32
  mut htree_command : FixedArray[Int32]
  mut dist_htree_index : Int32
  mut distance_code : Int32
  mut distance_context : Int32
  mut copy_length : Int32
  mut dist_extra_bits : FixedArray[Int32]
  mut dist_offset : FixedArray[Int32]
  // Scratch space for Huffman table construction.
  scratch_table : FixedArray[Int32]
  symbol_lists : FixedArray[Int32]
  code_length_histo : FixedArray[Int32]
  next_symbol : FixedArray[Int32]
  code_length_code_lengths : FixedArray[Int32]
  cl_table : FixedArray[Int32]
  simple_symbols : FixedArray[Int32]
  mtf : FixedArray[Int32]
  word_buf : FixedArray[Byte]
}

///|
fn Decoder::new(data : Bytes) -> Decoder {
  {
    br: BitReader::new(data),
    out: { data: FixedArray::make(0, b'\x00'), len: 0, },
    dict: dictionary_data(),
    window_bits: 0,
    max_backward_distance: 0,
    max_distance: 0,
    dist_rb: [16, 15, 11, 4],
    dist_rb_idx: 0,
    is_last_metablock: false,
    is_uncompressed: false,
    is_metadata: false,
    meta_block_remaining_len: 0,
    num_block_types: [1, 1, 1],
    block_length: [BLOCK_SIZE_CAP, BLOCK_SIZE_CAP, BLOCK_SIZE_CAP],
    block_type_rb: [1, 0, 1, 0, 1, 0],
    block_type_trees: [[], [], []],
    block_len_trees: [[], [], []],
    distance_postfix_bits: 0,
    num_direct_distance_codes: 0,
    context_modes: [],
    context_map: [],
    dist_context_map: [],
    literal_htrees: [],
    insert_copy_htrees: [],
    distance_htrees: [],
    context_map_slice: 0,
    dist_context_map_slice: 0,
    context_lookup: 0,
    htree_command: [],
    dist_htree_index: 0,
    distance_code: 0,
    distance_context: 0,
    copy_length: 0,
    dist_extra_bits: [],
    dist_offset: [],
    scratch_table: FixedArray::make(256 + 32768, 0),
    symbol_lists: FixedArray::make(SYMBOL_LISTS_BASE + 1128, 0),
    code_length_histo: FixedArray::make(16, 0),
    next_symbol: FixedArray::make(16, 0),
    code_length_code_lengths: FixedArray::make(CODE_LENGTH_CODES, 0),
    cl_table: FixedArray::make(32, 0),
    simple_symbols: FixedArray::make(4, 0),
    mtf: FixedArray::make(256, 0),
    word_buf: FixedArray::make(600, b'\x00'),
  }
}

///|
/// `DecodeWindowBits` (large windows are not enabled, as in the default C
/// decoder).
fn Decoder::decode_window_bits(
  self : Decoder,
) -> Unit raise @bitstream.JxlError {
  let br = self.br
  let mut n = br.read(1)
  if n == 0 {
    self.window_bits = 16
    return
  }
  n = br.read(3)
  if n != 0 {
    self.window_bits = (17 + n) & 63
    return
  }
  n = br.read(3)
  if n == 1 {
    raise brotli_error("FORMAT_WINDOW_BITS")
  }
  if n != 0 {
    self.window_bits = (8 + n) & 63
    return
  }
  self.window_bits = 17
}

///|
/// `DecodeVarLenUint8`: decodes a number in the range [0..255], by reading
/// 1 - 11 bits.
fn Decoder::decode_var_len_uint8(
  self : Decoder,
) -> Int32 raise @bitstream.JxlError {
  let br = self.br
  if br.read(1) == 0 {
    return 0
  }
  let n = br.read(3)
  if n == 0 {
    return 1
  }
  (1 << n) + br.read(n)
}

///|
/// `DecodeMetaBlockLength`: decodes a metablock length and flags by reading
/// 2 - 31 bits.
fn Decoder::decode_meta_block_length(
  self : Decoder,
) -> Unit raise @bitstream.JxlError {
  let br = self.br
  self.is_last_metablock = br.read(1) != 0
  self.meta_block_remaining_len = 0
  self.is_uncompressed = false
  self.is_metadata = false
  if self.is_last_metablock {
    // ISLASTEMPTY
    if br.read(1) != 0 {
      return
    }
  }
  let bits = br.read(2)
  let size_nibbles = bits + 4
  if bits == 3 {
    self.is_metadata = true
    if br.read(1) != 0 {
      raise brotli_error("FORMAT_RESERVED")
    }
    let size_bytes = br.read(2)
    if size_bytes == 0 {
      return
    }
    for i in 0..<size_bytes {
      let b = br.read(8)
      if i + 1 == size_bytes && size_bytes > 1 && b == 0 {
        raise brotli_error("FORMAT_EXUBERANT_META_NIBBLE")
      }
      self.meta_block_remaining_len = self.meta_block_remaining_len |
        (b << (i * 8))
    }
    self.meta_block_remaining_len += 1
    return
  }
  for i in 0..<size_nibbles {
    let b = br.read(4)
    if i + 1 == size_nibbles && size_nibbles > 4 && b == 0 {
      raise brotli_error("FORMAT_EXUBERANT_NIBBLE")
    }
    self.meta_block_remaining_len = self.meta_block_remaining_len |
      (b << (i * 4))
  }
  if !self.is_last_metablock {
    self.is_uncompressed = br.read(1) != 0
  }
  self.meta_block_remaining_len += 1
}

///|
/// `ReadSymbol`: reads and decodes the next Huffman code from the bitstream.
fn read_symbol(
  table : FixedArray[Int32],
  br : BitReader,
) -> Int32 raise @bitstream.JxlError {
  let bits = br.peek(HUFFMAN_MAX_CODE_LENGTH)
  let mut idx = bits & 0xff
  let mut code = table[idx]
  let nb = hc_bits(code)
  if nb > HUFFMAN_TABLE_BITS {
    let nbits = nb - HUFFMAN_TABLE_BITS
    br.drop_bits(HUFFMAN_TABLE_BITS)
    idx = idx +
      hc_value(code) +
      ((bits >> HUFFMAN_TABLE_BITS) & ((1 << nbits) - 1))
    code = table[idx]
  }
  br.drop_bits(hc_bits(code))
  hc_value(code)
}

///|
fn log2_floor(x : Int32) -> Int32 {
  let mut x = x
  let mut result = 0
  while x != 0 {
    x = x >> 1
    result += 1
  }
  result
}

///|
/// `ProcessSingleCodeLength`.
fn Decoder::process_single_code_length(
  self : Decoder,
  code_len : Int32,
  st : FixedArray[Int32],
) -> Unit {
  // st: [symbol, repeat, space, prev_code_len, repeat_code_len]
  st[1] = 0
  if code_len != 0 {
    self.symbol_lists[SYMBOL_LISTS_BASE + self.next_symbol[code_len]] = st[0]
    self.next_symbol[code_len] = st[0]
    st[3] = code_len
    st[2] -= 32768 >> code_len
    self.code_length_histo[code_len] += 1
  }
  st[0] += 1
}

///|
/// `ProcessRepeatedCodeLength`.
fn Decoder::process_repeated_code_length(
  self : Decoder,
  code_len : Int32,
  repeat_delta : Int32,
  alphabet_size : Int32,
  st : FixedArray[Int32],
) -> Unit {
  let mut extra_bits = 3
  let mut new_len = 0
  if code_len == REPEAT_PREVIOUS_CODE_LENGTH {
    new_len = st[3]
    extra_bits = 2
  }
  if st[4] != new_len {
    st[1] = 0
    st[4] = new_len
  }
  let old_repeat = st[1]
  if st[1] > 0 {
    st[1] -= 2
    st[1] = st[1] << extra_bits
  }
  st[1] += repeat_delta + 3
  let repeat_delta = st[1] - old_repeat
  if st[0] + repeat_delta > alphabet_size {
    st[0] = alphabet_size
    st[2] = 0xFFFFF
    return
  }
  let repeat_code_len = st[4]
  if repeat_code_len != 0 {
    let last = st[0] + repeat_delta
    let mut next = self.next_symbol[repeat_code_len]
    while true {
      self.symbol_lists[SYMBOL_LISTS_BASE + next] = st[0]
      next = st[0]
      st[0] += 1
      if st[0] == last {
        break
      }
    }
    self.next_symbol[repeat_code_len] = next
    st[2] -= repeat_delta << (15 - repeat_code_len)
    self.code_length_histo[repeat_code_len] += repeat_delta
  } else {
    st[0] += repeat_delta
  }
}

///|
/// `ReadHuffmanCode`: decodes a Huffman table and returns it.
fn Decoder::read_huffman_code(
  self : Decoder,
  alphabet_size_max : Int32,
  alphabet_size_limit : Int32,
) -> FixedArray[Int32] raise @bitstream.JxlError {
  let br = self.br
  let table = self.scratch_table
  // 1 for simple code; 0 for no skipping, 2 skips 2 code lengths,
  // 3 skips 3 code lengths
  let hskip = br.read(2)
  let table_size = if hskip == 1 {
    // Read symbols, codes & code lengths directly.
    let mut num_symbols = br.read(2)
    let max_bits = log2_floor(alphabet_size_max - 1)
    let syms = self.simple_symbols
    for i in 0..<=num_symbols {
      let v = br.read(max_bits)
      if v >= alphabet_size_limit {
        raise brotli_error("FORMAT_SIMPLE_HUFFMAN_ALPHABET")
      }
      syms[i] = v
    }
    for i in 0..<num_symbols {
      for k in (i + 1)..<=num_symbols {
        if syms[i] == syms[k] {
          raise brotli_error("FORMAT_SIMPLE_HUFFMAN_SAME")
        }
      }
    }
    if num_symbols == 3 {
      num_symbols += br.read(1)
    }
    build_simple_huffman_table(table, HUFFMAN_TABLE_BITS, syms, num_symbols)
  } else {
    // Decode Huffman-coded code lengths.
    let histo = self.code_length_histo
    let cl_lengths = self.code_length_code_lengths
    histo.fill(0)
    cl_lengths.fill(0)
    let mut space = 32
    let mut num_codes = 0
    for i in hskip..<CODE_LENGTH_CODES {
      let code_len_idx = code_length_code_order[i]
      let ix = br.peek(4)
      let v = code_length_prefix_value[ix]
      br.drop_bits(code_length_prefix_length[ix])
      cl_lengths[code_len_idx] = v
      if v != 0 {
        space = space - (32 >> v)
        num_codes += 1
        histo[v] += 1
        if space - 1 >= 32 || space - 1 < 0 {
          // space is 0 or wrapped around.
          break
        }
      }
    }
    if !(num_codes == 1 || space == 0) {
      raise brotli_error("FORMAT_CL_SPACE")
    }
    build_code_lengths_huffman_table(self.cl_table, cl_lengths, histo)
    histo.fill(0)
    for i in 0..<=HUFFMAN_MAX_CODE_LENGTH {
      self.next_symbol[i] = i - (HUFFMAN_MAX_CODE_LENGTH + 1)
      self.symbol_lists[SYMBOL_LISTS_BASE + self.next_symbol[i]] = 0xFFFF
    }
    // [symbol, repeat, space, prev_code_len, repeat_code_len]
    let st : FixedArray[Int32] = [0, 0, 32768, INITIAL_REPEATED_CODE_LENGTH, 0]
    let alphabet_size = alphabet_size_limit
    while st[0] < alphabet_size && st[2] > 0 {
      let p = self.cl_table[br.peek(HUFFMAN_MAX_CODE_LENGTH_CODE_LENGTH)]
      br.drop_bits(hc_bits(p)) // Use 1..5 bits.
      let code_len = hc_value(p) // code_len == 0..17
      if code_len < REPEAT_PREVIOUS_CODE_LENGTH {
        self.process_single_code_length(code_len, st)
      } else {
        // code_len == 16..17, extra_bits == 2..3
        let extra_bits = if code_len == REPEAT_PREVIOUS_CODE_LENGTH {
          2
        } else {
          3
        }
        let repeat_delta = br.read(extra_bits)
        self.process_repeated_code_length(
          code_len, repeat_delta, alphabet_size, st,
        )
      }
    }
    if st[2] != 0 {
      raise brotli_error("FORMAT_HUFFMAN_SPACE")
    }
    build_huffman_table(table, HUFFMAN_TABLE_BITS, self.symbol_lists, histo)
  }
  let t = FixedArray::make(table_size, 0)
  t.unsafe_blit(0, table, 0, table_size)
  t
}

///|
/// `ReadBlockLength`: decodes a block length by reading 3..39 bits.
fn read_block_length(
  table : FixedArray[Int32],
  br : BitReader,
) -> Int32 raise @bitstream.JxlError {
  let code = read_symbol(table, br)
  let nbits = block_len_nbits[code] // nbits == 2..24
  block_len_offset[code] + br.read(nbits)
}

///|
/// `InverseMoveToFrontTransform`.
fn Decoder::inverse_move_to_front_transform(
  self : Decoder,
  v : FixedArray[Int32],
) -> Unit {
  let mtf = self.mtf
  for i in 0..<256 {
    mtf[i] = i
  }
  for i in 0..<v.length() {
    let index = v[i]
    let value = mtf[index]
    v[i] = value
    let mut j = index
    while j > 0 {
      mtf[j] = mtf[j - 1]
      j -= 1
    }
    mtf[0] = value
  }
}

///|
/// `DecodeContextMap`. Returns (num_htrees, context_map).
fn Decoder::decode_context_map(
  self : Decoder,
  context_map_size : Int32,
) -> (Int32, FixedArray[Int32]) raise @bitstream.JxlError {
  let br = self.br
  let num_htrees = self.decode_var_len_uint8() + 1
  let context_map = FixedArray::make(context_map_size, 0)
  if num_htrees <= 1 {
    return (num_htrees, context_map)
  }
  let bits = br.peek(5)
  let max_run_length_prefix = if (bits & 1) != 0 {
    // Use RLE for zeros.
    br.drop_bits(5)
    (bits >> 1) + 1
  } else {
    br.drop_bits(1)
    0
  }
  let alphabet_size = num_htrees + max_run_length_prefix
  let table = self.read_huffman_code(alphabet_size, alphabet_size)
  let mut context_index = 0
  while context_index < context_map_size {
    let code = read_symbol(table, br)
    if code == 0 {
      context_map[context_index] = 0
      context_index += 1
      continue
    }
    if code > max_run_length_prefix {
      context_map[context_index] = code - max_run_length_prefix
      context_index += 1
      continue
    }
    // RLE sub-stage.
    let reps = br.read(code) + (1 << code)
    if context_index + reps > context_map_size {
      raise brotli_error("FORMAT_CONTEXT_MAP_REPEAT")
    }
    for _ in 0..<reps {
      context_map[context_index] = 0
      context_index += 1
    }
  }
  if br.read(1) != 0 {
    self.inverse_move_to_front_transform(context_map)
  }
  (num_htrees, context_map)
}

///|
/// `DecodeBlockTypeAndLength`: decodes a block type and length and updates
/// the block type ring-buffer. Returns false if there is only one block type.
fn Decoder::decode_block_type_and_length(
  self : Decoder,
  tree_type : Int32,
) -> Bool raise @bitstream.JxlError {
  let max_block_type = self.num_block_types[tree_type]
  if max_block_type <= 1 {
    return false
  }
  let br = self.br
  let mut block_type = read_symbol(self.block_type_trees[tree_type], br)
  self.block_length[tree_type] = read_block_length(
    self.block_len_trees[tree_type],
    br,
  )
  let rb = tree_type * 2
  if block_type == 1 {
    block_type = self.block_type_rb[rb + 1] + 1
  } else if block_type == 0 {
    block_type = self.block_type_rb[rb]
  } else {
    block_type -= 2
  }
  if block_type >= max_block_type {
    block_type -= max_block_type
  }
  self.block_type_rb[rb] = self.block_type_rb[rb + 1]
  self.block_type_rb[rb + 1] = block_type
  true
}

///|
/// `PrepareLiteralDecoding`.
fn Decoder::prepare_literal_decoding(self : Decoder) -> Unit {
  let block_type = self.block_type_rb[1]
  self.context_map_slice = block_type << LITERAL_CONTEXT_BITS
  let context_mode = self.context_modes[block_type] & 3
  self.context_lookup = context_mode << 9
}

///|
fn Decoder::decode_literal_block_switch(
  self : Decoder,
) -> Unit raise @bitstream.JxlError {
  if self.decode_block_type_and_length(0) {
    self.prepare_literal_decoding()
  }
}

///|
fn Decoder::decode_command_block_switch(
  self : Decoder,
) -> Unit raise @bitstream.JxlError {
  if self.decode_block_type_and_length(1) {
    self.htree_command = self.insert_copy_htrees[self.block_type_rb[3]]
  }
}

///|
fn Decoder::decode_distance_block_switch(
  self : Decoder,
) -> Unit raise @bitstream.JxlError {
  if self.decode_block_type_and_length(2) {
    self.dist_context_map_slice = self.block_type_rb[5] << DISTANCE_CONTEXT_BITS
    self.dist_htree_index = self.dist_context_map[self.dist_context_map_slice +
      self.distance_context]
  }
}

///|
/// `TakeDistanceFromRingBuffer`.
fn Decoder::take_distance_from_ring_buffer(self : Decoder) -> Unit {
  let offset = self.distance_code - 3
  if self.distance_code <= 3 {
    // Compensate double distance-ring-buffer roll for dictionary items.
    self.distance_context = 1 >> self.distance_code
    self.distance_code = self.dist_rb[(self.dist_rb_idx - offset) & 3]
    self.dist_rb_idx -= self.distance_context
  } else {
    let mut index_delta = 3
    let mut base = self.distance_code - 10
    if self.distance_code < 10 {
      base = self.distance_code - 4
    } else {
      index_delta = 2
    }
    // Unpack one of six 4-bit values.
    let delta = ((0x605142 >> (4 * base)) & 0xF) - 3
    self.distance_code = self.dist_rb[(self.dist_rb_idx + index_delta) & 0x3] +
      delta
    if self.distance_code <= 0 {
      // A huge distance will cause a failure soon.
      self.distance_code = 0x7FFFFFFF
    }
  }
}

///|
/// `CalculateDistanceLut`.
fn Decoder::calculate_distance_lut(
  self : Decoder,
  alphabet_size_limit : Int32,
) -> Unit {
  let npostfix = self.distance_postfix_bits
  let ndirect = self.num_direct_distance_codes
  let postfix = 1 << npostfix
  let extra = FixedArray::make(alphabet_size_limit, 0)
  let offs = FixedArray::make(alphabet_size_limit, 0)
  let mut bits = 1
  let mut half = 0
  // Skip short codes.
  let mut i = NUM_DISTANCE_SHORT_CODES
  // Fill direct codes.
  for j in 0..<ndirect {
    extra[i] = 0
    offs[i] = j + 1
    i += 1
  }
  // Fill regular distance codes.
  while i < alphabet_size_limit {
    let base = ndirect + ((((2 + half) << bits) - 4) << npostfix) + 1
    // Always fill the complete group.
    for j in 0..<postfix {
      extra[i] = bits
      offs[i] = base + j
      i += 1
    }
    bits = bits + half
    half = half ^ 1
  }
  self.dist_extra_bits = extra
  self.dist_offset = offs
}

///|
/// `ReadDistance`.
fn Decoder::read_distance(self : Decoder) -> Unit raise @bitstream.JxlError {
  let br = self.br
  let code = read_symbol(self.distance_htrees[self.dist_htree_index], br)
  self.block_length[2] -= 1
  // Convert the distance code to the actual distance by possibly looking up
  // past distances from the ring buffer.
  self.distance_context = 0
  if code < 16 {
    self.distance_code = code
    self.take_distance_from_ring_buffer()
    return
  }
  let bits = br.read(self.dist_extra_bits[code])
  self.distance_code = self.dist_offset[code] +
    (bits << self.distance_postfix_bits)
}

///|
/// `ReadCommand`. Returns the insert length.
fn Decoder::read_command(self : Decoder) -> Int32 raise @bitstream.JxlError {
  let br = self.br
  let cmd_code = read_symbol(self.htree_command, br)
  self.distance_code = cmd_distance_code[cmd_code]
  self.distance_context = cmd_context[cmd_code]
  self.dist_htree_index = self.dist_context_map[self.dist_context_map_slice +
    self.distance_context]
  let insert_len_extra = br.read(cmd_insert_len_extra_bits[cmd_code])
  let copy_length = br.read(cmd_copy_len_extra_bits[cmd_code])
  self.copy_length = copy_length + cmd_copy_len_offset[cmd_code]
  self.block_length[1] -= 1
  cmd_insert_len_offset[cmd_code] + insert_len_extra
}

///|
/// Reads the compressed metablock header (block types, context modes,
/// context maps and Huffman tree groups).
fn Decoder::read_compressed_metablock_header(
  self : Decoder,
) -> Unit raise @bitstream.JxlError {
  let br = self.br
  for i in 0..<3 {
    let n = self.decode_var_len_uint8() + 1
    self.num_block_types[i] = n
    if n < 2 {
      continue
    }
    self.block_type_trees[i] = self.read_huffman_code(n + 2, n + 2)
    self.block_len_trees[i] = self.read_huffman_code(
      NUM_BLOCK_LEN_SYMBOLS,
      NUM_BLOCK_LEN_SYMBOLS,
    )
    self.block_length[i] = read_block_length(self.block_len_trees[i], br)
  }
  let bits = br.read(6)
  self.distance_postfix_bits = bits & 3
  self.num_direct_distance_codes = bits >> 2 << self.distance_postfix_bits
  let context_modes = FixedArray::make(self.num_block_types[0], 0)
  for i in 0..<self.num_block_types[0] {
    context_modes[i] = br.read(2)
  }
  self.context_modes = context_modes
  let (num_literal_htrees, context_map) = self.decode_context_map(
    self.num_block_types[0] << LITERAL_CONTEXT_BITS,
  )
  self.context_map = context_map
  let npostfix = self.distance_postfix_bits
  let ndirect = self.num_direct_distance_codes
  let distance_alphabet_size = NUM_DISTANCE_SHORT_CODES +
    ndirect +
    (MAX_DISTANCE_BITS << (npostfix + 1))
  let (num_dist_htrees, dist_context_map) = self.decode_context_map(
    self.num_block_types[2] << DISTANCE_CONTEXT_BITS,
  )
  self.dist_context_map = dist_context_map
  let literal_htrees = []
  for _ in 0..<num_literal_htrees {
    literal_htrees.push(
      self.read_huffman_code(NUM_LITERAL_SYMBOLS, NUM_LITERAL_SYMBOLS),
    )
  }
  self.literal_htrees = literal_htrees
  let insert_copy_htrees = []
  for _ in 0..<self.num_block_types[1] {
    insert_copy_htrees.push(
      self.read_huffman_code(NUM_COMMAND_SYMBOLS, NUM_COMMAND_SYMBOLS),
    )
  }
  self.insert_copy_htrees = insert_copy_htrees
  let distance_htrees = []
  for _ in 0..<num_dist_htrees {
    distance_htrees.push(
      self.read_huffman_code(distance_alphabet_size, distance_alphabet_size),
    )
  }
  self.distance_htrees = distance_htrees
  // BROTLI_STATE_BEFORE_COMPRESSED_METABLOCK_BODY
  self.prepare_literal_decoding()
  self.dist_context_map_slice = 0
  self.htree_command = self.insert_copy_htrees[0]
  self.calculate_distance_lut(distance_alphabet_size)
}

///|
/// `ProcessCommandsInternal` for one compressed metablock body.
fn Decoder::process_commands(self : Decoder) -> Unit raise @bitstream.JxlError {
  let br = self.br
  let out = self.out
  while self.meta_block_remaining_len > 0 {
    // CommandBegin
    if self.block_length[1] == 0 {
      self.decode_command_block_switch()
    }
    // Read the insert/copy length in the command.
    let mut i = self.read_command()
    if i != 0 {
      self.meta_block_remaining_len -= i
      // CommandInner: read the literals in the command.
      out.reserve(i)
      let mut p1 = if out.len >= 1 { out.data[out.len - 1].to_int() } else { 0 }
      let mut p2 = if out.len >= 2 { out.data[out.len - 2].to_int() } else { 0 }
      while i != 0 {
        if self.block_length[0] == 0 {
          self.decode_literal_block_switch()
          continue
        }
        let lut = self.context_lookup
        let context = context_lookup_table[lut + p1] |
          context_lookup_table[lut + 256 + p2]
        let hc = self.literal_htrees[self.context_map[self.context_map_slice +
          context]]
        p2 = p1
        p1 = read_symbol(hc, br)
        out.data[out.len] = p1.to_byte()
        out.len += 1
        self.block_length[0] -= 1
        i -= 1
      }
      if self.meta_block_remaining_len <= 0 {
        break
      }
    }
    // CommandPostDecodeLiterals
    if self.distance_code >= 0 {
      // Implicit distance case.
      self.distance_context = if self.distance_code != 0 { 0 } else { 1 }
      self.dist_rb_idx -= 1
      self.distance_code = self.dist_rb[self.dist_rb_idx & 3]
    } else {
      // Read distance code in the command, unless it was implicitly zero.
      if self.block_length[2] == 0 {
        self.decode_distance_block_switch()
      }
      self.read_distance()
    }
    let pos = out.len
    if self.max_distance != self.max_backward_distance {
      self.max_distance = if pos < self.max_backward_distance {
        pos
      } else {
        self.max_backward_distance
      }
    }
    i = self.copy_length
    // Apply copy of LZ77 back-reference, or static dictionary reference if
    // the distance is larger than the max LZ77 distance.
    if self.distance_code > self.max_distance {
      if self.distance_code > MAX_ALLOWED_DISTANCE {
        raise brotli_error("FORMAT_DISTANCE")
      }
      if i >= MIN_DICTIONARY_WORD_LENGTH && i <= MAX_DICTIONARY_WORD_LENGTH {
        let shift = dictionary_size_bits_by_length[i]
        let mut offset = dictionary_offsets_by_length[i]
        let address = self.distance_code - self.max_distance - 1
        let mask = (1 << shift) - 1
        let word_idx = address & mask
        let transform_idx = address >> shift
        // Compensate double distance-ring-buffer roll.
        self.dist_rb_idx += self.distance_context
        offset += word_idx * i
        if shift == 0 {
          raise brotli_error("FORMAT_DICTIONARY")
        }
        if transform_idx < NUM_TRANSFORMS {
          let mut len = i
          if transform_idx == CUTOFF_TRANSFORM_0 {
            out.reserve(len)
            for k in 0..<len {
              out.data[out.len + k] = self.dict[offset + k]
            }
          } else {
            len = transform_dictionary_word(
              self.word_buf,
              self.dict,
              offset,
              len,
              transform_idx,
            )
            if len == 0 && self.distance_code <= 120 {
              raise brotli_error("FORMAT_TRANSFORM")
            }
            out.reserve(len)
            out.data.unsafe_blit(out.len, self.word_buf, 0, len)
          }
          out.len += len
          self.meta_block_remaining_len -= len
        } else {
          raise brotli_error("FORMAT_TRANSFORM")
        }
      } else {
        raise brotli_error("FORMAT_DICTIONARY")
      }
    } else {
      // Update the recent distances cache.
      self.dist_rb[self.dist_rb_idx & 3] = self.distance_code
      self.dist_rb_idx += 1
      self.meta_block_remaining_len -= i
      out.reserve(i)
      let data = out.data
      let src = pos - self.distance_code
      for k in 0..<i {
        data[pos + k] = data[src + k]
      }
      out.len = pos + i
    }
  }
}

///|
/// Runs the decoder over the whole input. With `allow_partial`, running out
/// of input returns the output produced so far instead of failing.
fn Decoder::run(
  self : Decoder,
  allow_partial : Bool,
) -> Unit raise @bitstream.JxlError {
  let br = self.br
  self.decode_window_bits() catch {
    @bitstream.JxlError::Eof =>
      if allow_partial {
        return
      } else {
        raise brotli_error("NEEDS_MORE_INPUT")
      }
    e => raise e
  }
  self.max_backward_distance = (1 << self.window_bits) - WINDOW_GAP
  while true {
    let done = self.decode_metablock() catch {
      @bitstream.JxlError::Eof =>
        if allow_partial {
          return
        } else {
          raise brotli_error("NEEDS_MORE_INPUT")
        }
      e => raise e
    }
    if done {
      break
    }
  }
  if br.remaining_bytes() != 0 {
    raise brotli_error("TrailingData")
  }
}

///|
/// Decodes one metablock; returns true after the last one.
fn Decoder::decode_metablock(self : Decoder) -> Bool raise @bitstream.JxlError {
  let br = self.br
  // BrotliDecoderStateMetablockBegin
  self.meta_block_remaining_len = 0
  self.block_length[0] = BLOCK_SIZE_CAP
  self.block_length[1] = BLOCK_SIZE_CAP
  self.block_length[2] = BLOCK_SIZE_CAP
  self.num_block_types[0] = 1
  self.num_block_types[1] = 1
  self.num_block_types[2] = 1
  self.block_type_rb[0] = 1
  self.block_type_rb[1] = 0
  self.block_type_rb[2] = 1
  self.block_type_rb[3] = 0
  self.block_type_rb[4] = 1
  self.block_type_rb[5] = 0
  self.dist_htree_index = 0
  self.decode_meta_block_length()
  if self.is_metadata || self.is_uncompressed {
    if !br.jump_to_byte_boundary() {
      raise brotli_error("FORMAT_PADDING_1")
    }
  }
  if self.is_metadata {
    br.skip_bytes(self.meta_block_remaining_len)
    self.meta_block_remaining_len = 0
  } else if self.meta_block_remaining_len == 0 {
    ()
  } else if self.is_uncompressed {
    let n = self.meta_block_remaining_len
    let out = self.out
    out.reserve(n)
    for k in 0..<n {
      out.data[out.len] = br.read_byte().to_byte()
      out.len += 1
      self.meta_block_remaining_len -= 1
      ignore(k)
    }
  } else {
    self.read_compressed_metablock_header()
    self.process_commands()
  }
  // BROTLI_STATE_METABLOCK_DONE
  if self.meta_block_remaining_len < 0 {
    raise brotli_error("FORMAT_BLOCK_LENGTH_2")
  }
  if !self.is_last_metablock {
    return false
  }
  if !br.jump_to_byte_boundary() {
    raise brotli_error("FORMAT_PADDING_2")
  }
  true
}

///|
/// Decompresses a complete Brotli stream (RFC 7932).
///
/// Raises `Brotli(..)` if the stream is invalid, truncated, or followed by
/// trailing data.
pub fn decompress(data : Bytes) -> Bytes raise @bitstream.JxlError {
  let d = Decoder::new(data)
  d.run(false)
  d.out.to_bytes()
}

///|
/// Decompresses as much of a possibly truncated Brotli stream as possible.
///
/// Invalid data still raises `Brotli(..)`; running out of input does not.
pub fn decompress_partial(data : Bytes) -> Bytes raise @bitstream.JxlError {
  let d = Decoder::new(data)
  d.run(true)
  d.out.to_bytes()
}
