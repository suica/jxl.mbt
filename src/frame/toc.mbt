///|
/// Table of contents of a frame.
///
/// Frame data are organized in groups. TOC specified the size and order of each group, and it is
/// decoded after the frame header.
#derive(Debug)
pub struct Toc {
  priv num_lf_groups : Int32
  priv num_groups : Int32
  priv groups : Array[TocGroup]
  priv bitstream_to_original : Array[Int32]
  priv original_to_bitstream : Array[Int32]
  /// `usize` upstream; Int64 so that sums of up to 65536 sizes cannot overflow.
  priv total_size : Int64
}

///|
pub impl Show for Toc with fn output(self, logger) {
  let n = self.groups.length()
  logger.write_string(
    "Toc { num_lf_groups: \{self.num_lf_groups}, num_groups: \{self.num_groups}, total_size: \{self.total_size}, groups: (\{n} \{if n == 1 { "entry" } else { "entries" }}), bitstream_order: (\{if self.bitstream_to_original.is_empty() { "empty" } else { "non-empty" }}), .. }",
  )
}

///|
/// Information about a group in TOC.
#derive(Debug, Eq)
pub(all) struct TocGroup {
  /// Kind of the group.
  kind : TocGroupKind
  /// Offset from the beginning of frame header.
  /// `usize` upstream.
  mut offset : Int64
  /// Size of the group.
  size : Int32
}

///|
/// Kind of a TOC group. The derived ordering matches upstream's `Ord`:
/// All < LfGlobal < LfGroup(idx) < HfGlobal < GroupPass(pass, group).
#derive(Debug, Eq, Hash, Compare)
pub(all) enum TocGroupKind {
  All
  LfGlobal
  LfGroup(Int32)
  HfGlobal
  GroupPass(pass_idx~ : Int32, group_idx~ : Int32)
}

///|
pub impl Show for TocGroupKind with fn output(self, logger) {
  match self {
    All => logger.write_string("All")
    LfGlobal => logger.write_string("LfGlobal")
    LfGroup(i) => logger.write_string("LfGroup(\{i})")
    HfGlobal => logger.write_string("HfGlobal")
    GroupPass(pass_idx~, group_idx~) =>
      logger.write_string(
        "GroupPass { pass_idx: \{pass_idx}, group_idx: \{group_idx} }",
      )
  }
}

///|
/// Returns the offset to the beginning of the data.
pub fn Toc::bookmark(self : Toc) -> Int64 {
  let idx = if self.bitstream_to_original.is_empty() {
    0
  } else {
    self.bitstream_to_original[0]
  }
  self.groups[idx].offset
}

///|
/// Returns whether the frame has only one group.
pub fn Toc::is_single_entry(self : Toc) -> Bool {
  self.groups.length() <= 1
}

///|
pub fn Toc::group_index_bitstream_order(
  self : Toc,
  kind : TocGroupKind,
) -> Int32 {
  let original_order = match kind {
    All if self.is_single_entry() => 0
    _ if self.is_single_entry() =>
      abort("Cannot request group type of \{kind} for single-group frame")
    All => abort("Cannot request group type of All for multi-group frame")
    LfGlobal => 0
    LfGroup(lf_group_idx) => 1 + lf_group_idx
    HfGlobal => 1 + self.num_lf_groups
    GroupPass(pass_idx~, group_idx~) =>
      1 + self.num_lf_groups + 1 + pass_idx * self.num_groups + group_idx
  }
  if self.original_to_bitstream.is_empty() {
    original_order
  } else {
    self.original_to_bitstream[original_order]
  }
}

///|
/// Returns the total size of the frame data in bytes.
pub fn Toc::total_byte_size(self : Toc) -> Int64 {
  self.total_size
}

///|
/// Groups in bitstream order (copies, like upstream's `TocGroup: Copy`).
pub fn Toc::iter_bitstream_order(self : Toc) -> Iter[TocGroup] {
  let groups = if self.bitstream_to_original.is_empty() {
    self.groups.map(g => { ..g, })
  } else {
    self.bitstream_to_original.map(idx => { ..self.groups[idx], })
  }
  groups.iter()
}

///|
fn Toc::adjust_offsets(self : Toc, global_frame_offset : Int64) -> Unit {
  if global_frame_offset == 0L {
    return
  }
  for group in self.groups {
    if group.offset < global_frame_offset {
      abort("group offset is smaller than global frame offset")
    }
    group.offset = group.offset - global_frame_offset
  }
}

///|
pub fn Toc::parse(
  bs : @bitstream.Bitstream,
  ctx : FrameHeader,
) -> Toc raise @bitstream.JxlError {
  let num_groups = ctx.num_groups()
  let num_passes = ctx.passes.num_passes
  let entry_count = if num_groups == 1 && num_passes == 1 {
    1
  } else {
    1 + ctx.num_lf_groups() + 1 + num_groups * num_passes
  }
  if entry_count > 65536 {
    raise ValidationFailed("Too many TOC entries")
  }
  let permutated_toc = bs.read_bool()
  let permutation = if permutated_toc {
    let decoder = @coding.Decoder::parse(bs, 8)
    decoder.begin(bs)
    let permutation = @coding.read_permutation(bs, decoder, entry_count, 0)
    decoder.finalize()
    permutation
  } else {
    []
  }
  bs.zero_pad_to_byte()
  let sizes = []
  for _ in 0..<entry_count {
    sizes.push(
      bs
      .read_u32(
        @bitstream.u(10),
        @bitstream.cu(1024, 14),
        @bitstream.cu(17408, 22),
        @bitstream.cu(4211712, 30),
      )
      .reinterpret_as_int(),
    )
  }
  bs.zero_pad_to_byte()
  let offsets : Array[Int64] = []
  let mut acc = (bs.num_read_bits() / 8).to_int64()
  let mut total_size = 0L
  for size in sizes {
    offsets.push(acc)
    acc += size.to_int64()
    total_size += size.to_int64()
  }
  let section_kinds : Array[TocGroupKind] = if entry_count == 1 {
    [All]
  } else {
    let out = [LfGlobal]
    for idx in 0..<ctx.num_lf_groups() {
      out.push(LfGroup(idx))
    }
    out.push(HfGlobal)
    for pass_idx in 0..<num_passes {
      for group_idx in 0..<num_groups {
        out.push(GroupPass(pass_idx~, group_idx~))
      }
    }
    out
  }
  let (offsets, sizes, bitstream_to_original, original_to_bitstream) = if permutated_toc {
    let bitstream_to_original = Array::make(permutation.length(), 0)
    let offsets_out = []
    let sizes_out = []
    for idx, perm in permutation {
      offsets_out.push(offsets[perm])
      sizes_out.push(sizes[perm])
      bitstream_to_original[perm] = idx
    }
    (offsets_out, sizes_out, bitstream_to_original, permutation)
  } else {
    (offsets, sizes, [], [])
  }
  let groups = []
  for i in 0..<sizes.length() {
    groups.push({ kind: section_kinds[i], offset: offsets[i], size: sizes[i], })
  }
  {
    num_lf_groups: ctx.num_lf_groups(),
    num_groups,
    groups,
    bitstream_to_original,
    original_to_bitstream,
    total_size,
  }
}
