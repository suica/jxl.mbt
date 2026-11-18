// Port of jxl-oxide/src/aux_box/jbrd.rs.

///|
priv enum JbrdState {
  Uninit(Buffer)
  Init(@jbr.JpegBitstreamData)
}

///|
priv struct Jbrd {
  mut state : JbrdState
}

///|
fn Jbrd::new() -> Jbrd {
  { state: Uninit(Buffer()) }
}

///|
fn Jbrd::feed_bytes(self : Jbrd, bytes : BytesView) -> Unit raise @bitstream.JxlError {
  match self.state {
    Uninit(buf) => {
      buf.write_bytesview(bytes)
      if @jbr.JpegBitstreamData::try_parse(buf.to_bytes()) is Some(data) {
        self.state = Init(data)
      }
    }
    Init(data) => data.feed_bytes(bytes)
  }
}

///|
fn Jbrd::finalize(self : Jbrd) -> Unit raise @bitstream.JxlError {
  match self.state {
    Uninit(_) => raise @bitstream.Jbr("InvalidData")
    Init(data) => data.finalize()
  }
}

///|
fn Jbrd::data(self : Jbrd) -> @jbr.JpegBitstreamData? {
  match self.state {
    Init(data) => Some(data)
    _ => None
  }
}
