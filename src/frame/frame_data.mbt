// Group data access of `Frame` (the second half of upstream jxl-frame/src/lib.rs).
// `Option<Result<T>>` is mirrored as `Result[T, JxlError]?`: `None` means the data
// is not available (yet).

///|
pub fn Frame::try_parse_lf_global(
  self : Frame,
) -> Result[LfGlobal, @bitstream.JxlError]? {
  if self.toc.is_single_entry() {
    if self.all_group_offsets.has_error != 0 {
      return Some(Err(had_error))
    }
    guard self.data.get(0) is Some(group) else { return None }
    let loaded = self.reading_data_index != 0
    let bs = bitstream_of(group.view)
    let lf_global = Ok(
      LfGlobal::parse(
        bs,
        LfGlobalParams::new(
          self.image_header,
          self.header,
          self.tracker,
          !loaded,
        ),
      ),
    ) catch {
      e => Err(e)
    }
    match lf_global {
      Ok(lf_global) => {
        self.all_group_offsets.lf_group = bs.num_read_bits()
        Some(Ok(lf_global))
      }
      Err(e) if !loaded && e.unexpected_eof() => Some(Err(e))
      Err(e) => {
        self.all_group_offsets.has_error = 1
        Some(Err(e))
      }
    }
  } else {
    let idx = self.toc.group_index_bitstream_order(LfGlobal)
    guard self.data.get(idx) is Some(group) else { return None }
    let allow_partial = group.len() < group.toc_group.size
    let bs = bitstream_of(group.view)
    Some(
      Ok(
        LfGlobal::parse(
          bs,
          LfGlobalParams::new(
            self.image_header,
            self.header,
            self.tracker,
            allow_partial,
          ),
        ),
      ) catch {
        e => Err(e)
      },
    )
  }
}

///|
pub fn Frame::try_parse_lf_group(
  self : Frame,
  lf_global_vardct : LfGlobalVarDct?,
  global_ma_config : @modular.MaConfig?,
  mlf_group : @modular.TransformedModularSubimage?,
  lf_group_idx : Int32,
) -> Result[LfGroup, @bitstream.JxlError]? {
  let quantizer = lf_global_vardct.map(x => x.quantizer)
  if self.toc.is_single_entry() {
    if self.all_group_offsets.has_error != 0 {
      return Some(Err(had_error))
    }
    if lf_group_idx != 0 {
      return None
    }
    guard self.data.get(0) is Some(group) else { return None }
    let loaded = self.reading_data_index != 0
    let bs = bitstream_of(group.view)
    let offset = self.all_group_offsets.lf_group
    if offset == 0 {
      let lf_global = self.try_parse_lf_global().unwrap()
      if lf_global is Err(e) {
        return Some(Err(e))
      }
    }
    let offset = self.all_group_offsets.lf_group
    bs.skip_bits(offset) catch {
      _ => abort("skip_bits")
    }
    let result = Ok(
      LfGroup::parse(bs, {
        frame_header: self.header,
        quantizer,
        global_ma_config,
        mlf_group,
        lf_group_idx,
        allow_partial: !loaded,
        tracker: self.tracker,
        pool: self.pool,
      }),
    ) catch {
      e => Err(e)
    }
    match result {
      Ok(result) => {
        self.all_group_offsets.hf_global = bs.num_read_bits()
        Some(Ok(result))
      }
      Err(e) if !loaded && e.unexpected_eof() => None
      Err(e) => {
        self.all_group_offsets.has_error = 2
        Some(Err(e))
      }
    }
  } else {
    let idx = self.toc.group_index_bitstream_order(LfGroup(lf_group_idx))
    guard self.data.get(idx) is Some(group) else { return None }
    let allow_partial = group.len() < group.toc_group.size
    let bs = bitstream_of(group.view)
    let result = Ok(
      LfGroup::parse(bs, {
        frame_header: self.header,
        quantizer,
        global_ma_config,
        mlf_group,
        lf_group_idx,
        allow_partial,
        tracker: self.tracker,
        pool: self.pool,
      }),
    ) catch {
      e => Err(e)
    }
    if allow_partial && result is Err(_) {
      return None
    }
    Some(result)
  }
}

///|
pub fn Frame::try_parse_hf_global(
  self : Frame,
  cached_lf_global : LfGlobal?,
) -> Result[HfGlobal, @bitstream.JxlError]? {
  let is_modular = self.header.encoding == Modular
  if self.toc.is_single_entry() {
    if self.all_group_offsets.has_error != 0 {
      return Some(Err(had_error))
    }
    guard self.data.get(0) is Some(group) else { return None }
    let loaded = self.reading_data_index != 0
    let bs = bitstream_of(group.view)
    let offset = self.all_group_offsets.hf_global
    let lf_global = if cached_lf_global is None && (offset == 0 || !is_modular) {
      match self.try_parse_lf_global() {
        None => return None
        Some(Ok(lf_global)) => Some(lf_global)
        Some(Err(e)) => return Some(Err(e))
      }
    } else {
      None
    }
    let lf_global = match cached_lf_global {
      Some(_) => cached_lf_global
      None => lf_global
    }
    if offset == 0 {
      let lf_global = lf_global.unwrap()
      let r = Ok(
        {
          let gmodular = lf_global.gmodular.try_clone()
          let groups = match gmodular.modular.image_mut() {
            Some(x) => Some(x.prepare_groups(self.pass_shifts))
            None => None
          }
          let mlf_group = match groups {
            Some(x) => x.lf_groups.pop()
            None => None
          }
          match
            self.try_parse_lf_group(
              lf_global.vardct,
              lf_global.gmodular.ma_config(),
              mlf_group,
              0,
            ) {
            None => raise @bitstream.Eof
            Some(Err(e)) => raise e
            Some(Ok(_)) => ()
          }
        },
      ) catch {
        e => Err(e)
      }
      if r is Err(e) {
        return Some(Err(e))
      }
    }
    let offset = self.all_group_offsets.hf_global
    if self.header.encoding == Modular {
      self.all_group_offsets.pass_group = offset
      return None
    }
    bs.skip_bits(offset) catch {
      _ => abort("skip_bits")
    }
    let lf_global = lf_global.unwrap()
    let result = Ok(
      HfGlobal::parse(
        bs,
        HfGlobalParams::new(
          self.image_header.metadata,
          self.header,
          lf_global,
          self.tracker,
          self.pool,
        ),
      ),
    ) catch {
      e => Err(e)
    }
    Some(
      match result {
        Ok(result) => {
          self.all_group_offsets.pass_group = bs.num_read_bits()
          Ok(result)
        }
        Err(e) if !loaded && e.unexpected_eof() => Err(e)
        Err(e) => {
          self.all_group_offsets.has_error = 3
          Err(e)
        }
      },
    )
  } else {
    if self.header.encoding == Modular {
      return None
    }
    let idx = self.toc.group_index_bitstream_order(HfGlobal)
    guard self.data.get(idx) is Some(group) else { return None }
    if group.len() < group.toc_group.size {
      return None
    }
    let bs = bitstream_of(group.view)
    let lf_global = match cached_lf_global {
      Some(lf_global) => lf_global
      None =>
        match self.try_parse_lf_global() {
          None => return None
          Some(Ok(lf_global)) => lf_global
          Some(Err(e)) => return Some(Err(e))
        }
    }
    let params = HfGlobalParams::new(
      self.image_header.metadata,
      self.header,
      lf_global,
      self.tracker,
      self.pool,
    )
    Some(Ok(HfGlobal::parse(bs, params)) catch { e => Err(e) })
  }
}

///|
pub(all) struct PassGroupBitstream {
  bitstream : @bitstream.Bitstream
  partial : Bool
}

///|
pub fn Frame::pass_group_bitstream(
  self : Frame,
  pass_idx : Int32,
  group_idx : Int32,
) -> Result[PassGroupBitstream, @bitstream.JxlError]? {
  if self.toc.is_single_entry() {
    if self.all_group_offsets.has_error != 0 {
      return Some(Err(had_error))
    }
    if pass_idx != 0 || group_idx != 0 {
      return None
    }
    guard self.data.get(0) is Some(group) else { return None }
    let loaded = self.reading_data_index != 0
    let bs = bitstream_of(group.view)
    let mut offset = self.all_group_offsets.pass_group
    if offset == 0 {
      match self.try_parse_hf_global(None) {
        None => return None
        Some(Err(e)) => return Some(Err(e))
        Some(Ok(_)) => ()
      }
      offset = self.all_group_offsets.pass_group
    }
    bs.skip_bits(offset) catch {
      _ => abort("skip_bits")
    }
    Some(Ok({ bitstream: bs, partial: !loaded, }))
  } else {
    let idx = self.toc.group_index_bitstream_order(
      GroupPass(pass_idx~, group_idx~),
    )
    guard self.data.get(idx) is Some(group) else { return None }
    let partial = group.len() < group.toc_group.size
    let bs = bitstream_of(group.view)
    Some(Ok({ bitstream: bs, partial, }))
  }
}
