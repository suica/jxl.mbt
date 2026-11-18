///|
/// Tracks the bytes of sample buffers allocated, to fail decoding of
/// images that would use too much memory (jxl-grid `AllocTracker`).
/// Shared by reference: copies of the value share the counter.
pub struct AllocTracker {
  mut bytes_left : Int64
}

///|
pub fn AllocTracker::with_limit(bytes : Int64) -> AllocTracker {
  { bytes_left: bytes, }
}

///|
/// Reserves `count` elements of `elem_size` bytes, raising `OutOfMemory`.
pub fn AllocTracker::alloc(
  self : AllocTracker,
  count : Int32,
  elem_size : Int32,
) -> Unit raise @bitstream.JxlError {
  let bytes = count.to_int64() * elem_size.to_int64()
  if bytes > self.bytes_left {
    raise @bitstream.OutOfMemory(
      if bytes > 0x7fffffffL {
        0x7fffffff
      } else {
        bytes.to_int()
      },
    )
  }
  self.bytes_left -= bytes
}

///|
/// Returns `count * elem_size` bytes to the tracker.
pub fn AllocTracker::free(
  self : AllocTracker,
  count : Int32,
  elem_size : Int32,
) -> Unit {
  self.bytes_left += count.to_int64() * elem_size.to_int64()
}

///|
/// Expands the current limit by `by_bytes` bytes (wrapping, like
/// `AtomicUsize::fetch_add`).
pub fn AllocTracker::expand_limit(self : AllocTracker, by_bytes : Int64) -> Unit {
  self.bytes_left += by_bytes
}

///|
/// Shrinks the current limit by `by_bytes` bytes.
///
/// Raises `OutOfMemory` if the total amount of current allocation doesn't
/// allow shrinking the limit.
pub fn AllocTracker::shrink_limit(
  self : AllocTracker,
  by_bytes : Int64,
) -> Unit raise @bitstream.JxlError {
  if by_bytes > self.bytes_left {
    raise @bitstream.OutOfMemory(
      if by_bytes > 0x7fffffffL {
        0x7fffffff
      } else {
        by_bytes.to_int()
      },
    )
  }
  self.bytes_left -= by_bytes
}

///|
/// A row-major 2D buffer (jxl-grid `AlignedGrid`); stride is the width.
pub struct Grid[T] {
  width : Int32
  height : Int32
  buf : FixedArray[T]
}

///|
pub fn[T] Grid::new(width : Int32, height : Int32, init : T) -> Grid[T] {
  { width, height, buf: FixedArray::make(width * height, init), }
}

///|
/// Allocates through `tracker` when one is given.
pub fn[T] Grid::with_alloc_tracker(
  width : Int32,
  height : Int32,
  init : T,
  tracker : AllocTracker?,
  elem_size~ : Int32 = 4,
) -> Grid[T] raise @bitstream.JxlError {
  let count = width.to_int64() * height.to_int64()
  if count > 0x7fffffffL {
    raise @bitstream.OutOfMemory(0x7fffffff)
  }
  if tracker is Some(t) {
    t.alloc(count.to_int(), elem_size)
  }
  Grid::new(width, height, init)
}

///|
pub fn[T] Grid::from_buf(
  width : Int32,
  height : Int32,
  buf : FixedArray[T],
) -> Grid[T] {
  guard! buf.length() >= width * height
  { width, height, buf, }
}

///|
pub fn[T] Grid::empty(init : T) -> Grid[T] {
  { width: 0, height: 0, buf: FixedArray::make(0, init), }
}

///|
pub fn[T] Grid::width(self : Grid[T]) -> Int32 {
  self.width
}

///|
pub fn[T] Grid::height(self : Grid[T]) -> Int32 {
  self.height
}

///|
pub fn[T] Grid::buf(self : Grid[T]) -> FixedArray[T] {
  self.buf
}

///|
pub fn[T] Grid::get(self : Grid[T], x : Int32, y : Int32) -> T {
  self.buf[y * self.width + x]
}

///|
pub fn[T] Grid::set(self : Grid[T], x : Int32, y : Int32, v : T) -> Unit {
  self.buf[y * self.width + x] = v
}

///|
/// Index of the first sample of `row` in `buf`.
pub fn[T] Grid::row_offset(self : Grid[T], row : Int32) -> Int32 {
  row * self.width
}

///|
pub fn[T] Grid::clone(self : Grid[T]) -> Grid[T] {
  let n = self.buf.length()
  if n == 0 {
    return { width: self.width, height: self.height, buf: self.buf, }
  }
  let buf = FixedArray::make(n, self.buf[0])
  FixedArray::blit_to(self.buf, buf, len=n)
  { width: self.width, height: self.height, buf, }
}

///|
pub fn[T] Grid::as_subgrid(self : Grid[T]) -> SubGrid[T] {
  {
    buf: self.buf,
    offset: 0,
    width: self.width,
    height: self.height,
    stride: self.width,
  }
}

///|
/// A rectangular view into a shared buffer (jxl-grid `SharedSubgrid` and
/// `MutableSubgrid`; MoonBit buffers are shared, so one type serves both).
pub struct SubGrid[T] {
  buf : FixedArray[T]
  offset : Int32
  width : Int32
  height : Int32
  stride : Int32
}

///|
pub fn[T] SubGrid::from_buf(
  buf : FixedArray[T],
  offset : Int32,
  width : Int32,
  height : Int32,
  stride : Int32,
) -> SubGrid[T] {
  { buf, offset, width, height, stride, }
}

///|
pub fn[T] SubGrid::width(self : SubGrid[T]) -> Int32 {
  self.width
}

///|
pub fn[T] SubGrid::height(self : SubGrid[T]) -> Int32 {
  self.height
}

///|
pub fn[T] SubGrid::get(self : SubGrid[T], x : Int32, y : Int32) -> T {
  self.buf[self.offset + y * self.stride + x]
}

///|
pub fn[T] SubGrid::set(self : SubGrid[T], x : Int32, y : Int32, v : T) -> Unit {
  self.buf[self.offset + y * self.stride + x] = v
}

///|
/// Index in `buf` of sample (0, row).
pub fn[T] SubGrid::row_offset(self : SubGrid[T], row : Int32) -> Int32 {
  self.offset + row * self.stride
}

///|
pub fn[T] SubGrid::subgrid(
  self : SubGrid[T],
  left : Int32,
  top : Int32,
  width : Int32,
  height : Int32,
) -> SubGrid[T] {
  guard! left >= 0 &&
    top >= 0 &&
    width >= 0 &&
    height >= 0 &&
    left + width <= self.width &&
    top + height <= self.height
  {
    buf: self.buf,
    offset: self.offset + top * self.stride + left,
    width,
    height,
    stride: self.stride,
  }
}

///|
pub fn[T] SubGrid::split_horizontal(
  self : SubGrid[T],
  x : Int32,
) -> (SubGrid[T], SubGrid[T]) {
  (
    self.subgrid(0, 0, x, self.height),
    self.subgrid(x, 0, self.width - x, self.height),
  )
}

///|
pub fn[T] SubGrid::split_vertical(
  self : SubGrid[T],
  y : Int32,
) -> (SubGrid[T], SubGrid[T]) {
  (
    self.subgrid(0, 0, self.width, y),
    self.subgrid(0, y, self.width, self.height - y),
  )
}

///|
pub fn[T] SubGrid::swap(
  self : SubGrid[T],
  ax : Int32,
  ay : Int32,
  bx : Int32,
  by : Int32,
) -> Unit {
  let a = self.get(ax, ay)
  self.set(ax, ay, self.get(bx, by))
  self.set(bx, by, a)
}

///|
/// Splits into groups of `group_width` x `group_height`, row-major
/// (jxl-grid `into_groups`).
pub fn[T] SubGrid::into_groups(
  self : SubGrid[T],
  group_width : Int32,
  group_height : Int32,
) -> Array[SubGrid[T]] {
  let out = []
  let mut y = 0
  while y < self.height {
    let h = if self.height - y < group_height {
      self.height - y
    } else {
      group_height
    }
    let mut x = 0
    while x < self.width {
      let w = if self.width - x < group_width {
        self.width - x
      } else {
        group_width
      }
      out.push(self.subgrid(x, y, w, h))
      x += group_width
    }
    y += group_height
  }
  out
}
