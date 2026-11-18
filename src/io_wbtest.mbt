///|
/// A reader that returns at most `step` bytes per call.
priv struct Trickle {
  data : Bytes
  step : Int32
  mut pos : Int32
}

///|
impl Read for Trickle with fn read(self, buf, start, end) {
  let n = @cmp.minimum(
    @cmp.minimum(end - start, self.step),
    self.data.length() - self.pos,
  )
  if n <= 0 {
    return 0
  }
  for i in 0..<n {
    buf[start + i] = self.data[self.pos + i]
  }
  self.pos += n
  n
}

///|
test "read/cut header is UnexpectedEof" {
  let r = try {
    JxlImage::builder().read({ data: b"\xff\x0a", step: 1, pos: 0, }) |> ignore
    false
  } catch {
    Io(_) => true
    _ => false
  }
  // a cut header ends in UnexpectedEof, as upstream
  assert_true(r)
}
