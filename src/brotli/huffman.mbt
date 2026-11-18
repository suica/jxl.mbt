// Port of c/dec/huffman.c (Google brotli, MIT License).
//
// A table entry (`HuffmanCode`) is packed into an `Int` as
// `(value << 8) | bits`.

///|
const HUFFMAN_MAX_CODE_LENGTH = 15

///|
const HUFFMAN_MAX_CODE_LENGTH_CODE_LENGTH = 5

///|
const CODE_LENGTH_CODES = 18

///|
const REVERSE_BITS_MAX = 8

///|
const REVERSE_BITS_LOWEST : Int32 = 1 << (REVERSE_BITS_MAX - 1)

///|
/// Root table bits (`HUFFMAN_TABLE_BITS`).
const HUFFMAN_TABLE_BITS = 8

///|
let reverse_bits_table : FixedArray[Int32] = {
  let t = FixedArray::make(256, 0)
  for i in 0..<256 {
    let mut r = 0
    for b in 0..<8 {
      if (i & (1 << b)) != 0 {
        r = r | (1 << (7 - b))
      }
    }
    t[i] = r
  }
  t
}

///|
fn reverse_bits(num : Int32) -> Int32 {
  reverse_bits_table[num]
}

///|
fn construct_huffman_code(bits : Int32, value : Int32) -> Int32 {
  (value << 8) | bits
}

///|
fn hc_bits(code : Int32) -> Int32 {
  code & 0xff
}

///|
fn hc_value(code : Int32) -> Int32 {
  code >> 8
}

///|
/// Stores code in table[0], table[step], table[2*step], ..., table[end]
/// (relative to `base`). Assumes that end is an integer multiple of step.
fn replicate_value(
  table : FixedArray[Int32],
  base : Int32,
  step : Int32,
  end : Int32,
  code : Int32,
) -> Unit {
  let mut end = end
  while true {
    end -= step
    table[base + end] = code
    if end <= 0 {
      break
    }
  }
}

///|
/// Returns the table width of the next 2nd level table. `count` is the
/// histogram of bit lengths for the remaining symbols, `len` is the code
/// length of the next processed symbol.
fn next_table_bit_size(
  count : FixedArray[Int32],
  len : Int32,
  root_bits : Int32,
) -> Int32 {
  let mut len = len
  let mut left = 1 << (len - root_bits)
  while len < HUFFMAN_MAX_CODE_LENGTH {
    left -= count[len]
    if left <= 0 {
      break
    }
    len += 1
    left = left << 1
  }
  len - root_bits
}

///|
/// `BrotliBuildCodeLengthsHuffmanTable`. `table` must hold 32 entries.
fn build_code_lengths_huffman_table(
  table : FixedArray[Int32],
  code_lengths : FixedArray[Int32],
  count : FixedArray[Int32],
) -> Unit {
  let sorted = FixedArray::make(CODE_LENGTH_CODES, 0)
  let offset = FixedArray::make(HUFFMAN_MAX_CODE_LENGTH_CODE_LENGTH + 1, 0)
  // Generate offsets into sorted symbol table by code length.
  let mut symbol = -1
  for bits in 1..<=HUFFMAN_MAX_CODE_LENGTH_CODE_LENGTH {
    symbol += count[bits]
    offset[bits] = symbol
  }
  // Symbols with code length 0 are placed after all other symbols.
  offset[0] = CODE_LENGTH_CODES - 1
  // Sort symbols by length, by symbol order within each length.
  symbol = CODE_LENGTH_CODES
  while symbol != 0 {
    symbol -= 1
    let l = code_lengths[symbol]
    sorted[offset[l]] = symbol
    offset[l] -= 1
  }
  let table_size = 1 << HUFFMAN_MAX_CODE_LENGTH_CODE_LENGTH
  // Special case: all symbols but one have 0 code length.
  if offset[0] == 0 {
    let code = construct_huffman_code(0, sorted[0])
    for key in 0..<table_size {
      table[key] = code
    }
    return
  }
  // Fill in table.
  let mut key = 0
  let mut key_step = REVERSE_BITS_LOWEST
  symbol = 0
  let mut step = 2
  for bits in 1..<=HUFFMAN_MAX_CODE_LENGTH_CODE_LENGTH {
    for _ in 0..<count[bits] {
      let code = construct_huffman_code(bits, sorted[symbol])
      symbol += 1
      replicate_value(table, reverse_bits(key), step, table_size, code)
      key += key_step
    }
    step = step << 1
    key_step = key_step >> 1
  }
}

///|
/// Offset of index 0 of `symbol_lists` inside its backing array (C uses
/// negative indices down to -(HUFFMAN_MAX_CODE_LENGTH + 1)).
const SYMBOL_LISTS_BASE = 16

///|
/// `BrotliBuildHuffmanTable`. `symbol_lists` is indexed with
/// `SYMBOL_LISTS_BASE` added. Returns the total table size. `count` is
/// consumed (modified).
fn build_huffman_table(
  root_table : FixedArray[Int32],
  root_bits : Int32,
  symbol_lists : FixedArray[Int32],
  count : FixedArray[Int32],
) -> Int32 {
  let sl_base = SYMBOL_LISTS_BASE
  let mut max_length = -1
  while symbol_lists[sl_base + max_length] == 0xFFFF {
    max_length -= 1
  }
  max_length += HUFFMAN_MAX_CODE_LENGTH + 1
  let mut table = 0 // offset into root_table
  let mut table_bits = root_bits
  let mut table_size = 1 << table_bits
  let mut total_size = table_size
  // Fill in the root table. Reduce the table size to if possible, and create
  // the repetitions by memcpy.
  if table_bits > max_length {
    table_bits = max_length
    table_size = 1 << table_bits
  }
  let mut key = 0
  let mut key_step = REVERSE_BITS_LOWEST
  let mut bits = 1
  let mut step = 2
  while bits <= table_bits {
    let mut symbol = bits - (HUFFMAN_MAX_CODE_LENGTH + 1)
    for _ in 0..<count[bits] {
      symbol = symbol_lists[sl_base + symbol]
      let code = construct_huffman_code(bits, symbol)
      replicate_value(
        root_table,
        table + reverse_bits(key),
        step,
        table_size,
        code,
      )
      key += key_step
    }
    step = step << 1
    key_step = key_step >> 1
    bits += 1
  }
  // If root_bits != table_bits then replicate to fill the remaining slots.
  while total_size != table_size {
    for i in 0..<table_size {
      root_table[table + table_size + i] = root_table[table + i]
    }
    table_size = table_size << 1
  }
  // Fill in 2nd level tables and add pointers to root table.
  key_step = REVERSE_BITS_LOWEST >> (root_bits - 1)
  let mut sub_key = REVERSE_BITS_LOWEST << 1
  let mut sub_key_step = REVERSE_BITS_LOWEST
  let mut len = root_bits + 1
  step = 2
  while len <= max_length {
    let mut symbol = len - (HUFFMAN_MAX_CODE_LENGTH + 1)
    while count[len] != 0 {
      if sub_key == REVERSE_BITS_LOWEST << 1 {
        table += table_size
        table_bits = next_table_bit_size(count, len, root_bits)
        table_size = 1 << table_bits
        total_size += table_size
        sub_key = reverse_bits(key)
        key += key_step
        root_table[sub_key] = construct_huffman_code(
          table_bits + root_bits,
          table - sub_key,
        )
        sub_key = 0
      }
      symbol = symbol_lists[sl_base + symbol]
      let code = construct_huffman_code(len - root_bits, symbol)
      replicate_value(
        root_table,
        table + reverse_bits(sub_key),
        step,
        table_size,
        code,
      )
      sub_key += sub_key_step
      count[len] -= 1
    }
    step = step << 1
    sub_key_step = sub_key_step >> 1
    len += 1
  }
  total_size
}

///|
/// `BrotliBuildSimpleHuffmanTable`. `val` holds up to 4 symbols; `num_symbols`
/// is 0..=4 (number of symbols minus one, 4 meaning the 4-symbol tree with
/// lengths 1,2,3,3). Returns the table size.
fn build_simple_huffman_table(
  table : FixedArray[Int32],
  root_bits : Int32,
  val : FixedArray[Int32],
  num_symbols : Int32,
) -> Int32 {
  let mut table_size = 1
  let goal_size = 1 << root_bits
  match num_symbols {
    0 => table[0] = construct_huffman_code(0, val[0])
    1 => {
      if val[1] > val[0] {
        table[0] = construct_huffman_code(1, val[0])
        table[1] = construct_huffman_code(1, val[1])
      } else {
        table[0] = construct_huffman_code(1, val[1])
        table[1] = construct_huffman_code(1, val[0])
      }
      table_size = 2
    }
    2 => {
      table[0] = construct_huffman_code(1, val[0])
      table[2] = construct_huffman_code(1, val[0])
      if val[2] > val[1] {
        table[1] = construct_huffman_code(2, val[1])
        table[3] = construct_huffman_code(2, val[2])
      } else {
        table[1] = construct_huffman_code(2, val[2])
        table[3] = construct_huffman_code(2, val[1])
      }
      table_size = 4
    }
    3 => {
      for i in 0..<3 {
        for k in (i + 1)..<4 {
          if val[k] < val[i] {
            let t = val[k]
            val[k] = val[i]
            val[i] = t
          }
        }
      }
      table[0] = construct_huffman_code(2, val[0])
      table[2] = construct_huffman_code(2, val[1])
      table[1] = construct_huffman_code(2, val[2])
      table[3] = construct_huffman_code(2, val[3])
      table_size = 4
    }
    _ => {
      if val[3] < val[2] {
        let t = val[3]
        val[3] = val[2]
        val[2] = t
      }
      table[0] = construct_huffman_code(1, val[0])
      table[1] = construct_huffman_code(2, val[1])
      table[2] = construct_huffman_code(1, val[0])
      table[3] = construct_huffman_code(3, val[2])
      table[4] = construct_huffman_code(1, val[0])
      table[5] = construct_huffman_code(2, val[1])
      table[6] = construct_huffman_code(1, val[0])
      table[7] = construct_huffman_code(3, val[3])
      table_size = 8
    }
  }
  while table_size != goal_size {
    for i in 0..<table_size {
      table[table_size + i] = table[i]
    }
    table_size = table_size << 1
  }
  goal_size
}
