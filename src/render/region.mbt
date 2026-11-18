///|
/// A rectangular region (jxl-render `Region`).
///
/// `left`/`top` are signed (`i32` upstream); `width`/`height` are `u32`
/// upstream and are kept non-negative here.
#derive(Eq, Debug, Default, Hash)
pub(all) struct Region {
  left : Int
  top : Int
  width : Int
  height : Int
}

///|
const I32_MAX : Int64 = 0x7fffffffL

///|
const I32_MIN : Int64 = -0x80000000L

///|
/// `i32::saturating_add_unsigned`.
fn sat_add_unsigned(a : Int, b : Int) -> Int {
  let r = a.to_int64() + b.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
  if r > I32_MAX {
    I32_MAX.to_int()
  } else {
    r.to_int()
  }
}

///|
/// `i32::saturating_sub_unsigned`.
fn sat_sub_unsigned(a : Int, b : Int) -> Int {
  let r = a.to_int64() - b.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
  if r < I32_MIN {
    I32_MIN.to_int()
  } else {
    r.to_int()
  }
}

///|
/// `i32::abs_diff` (result fits in `u32`, returned as `Int`).
fn abs_diff(a : Int, b : Int) -> Int {
  let d = a.to_int64() - b.to_int64()
  (if d < 0L { -d } else { d }).to_int()
}

///|
pub fn Region::empty() -> Region {
  { left: 0, top: 0, width: 0, height: 0 }
}

///|
pub fn Region::with_size(width : Int, height : Int) -> Region {
  { left: 0, top: 0, width, height }
}

///|
pub fn Region::is_empty(self : Region) -> Bool {
  self.width == 0 || self.height == 0
}

///|
pub fn Region::right(self : Region) -> Int {
  sat_add_unsigned(self.left, self.width)
}

///|
pub fn Region::bottom(self : Region) -> Int {
  sat_add_unsigned(self.top, self.height)
}

///|
pub fn Region::contains(self : Region, target : Region) -> Bool {
  if target.is_empty() {
    return true
  }
  self.left <= target.left &&
  self.top <= target.top &&
  self.right() >= target.right() &&
  self.bottom() >= target.bottom()
}

///|
pub fn Region::translate(self : Region, x : Int, y : Int) -> Region {
  { ..self, left: self.left + x, top: self.top + y }
}

///|
pub fn Region::intersection(self : Region, rhs : Region) -> Region {
  if self.width == 0 || rhs.width == 0 || self.height == 0 || rhs.height == 0 {
    return Region::empty()
  }
  let mut ax = (self.left, self.right())
  let mut ay = (self.top, self.bottom())
  let mut bx = (rhs.left, rhs.right())
  let mut by = (rhs.top, rhs.bottom())
  if ax.0 > bx.0 {
    let t = ax
    ax = bx
    bx = t
  }
  if ay.0 > by.0 {
    let t = ay
    ay = by
    by = t
  }
  if ax.1 <= bx.0 || ay.1 <= by.0 {
    Region::empty()
  } else {
    {
      left: bx.0,
      top: by.0,
      width: abs_diff(min_int(ax.1, bx.1), bx.0),
      height: abs_diff(min_int(ay.1, by.1), by.0),
    }
  }
}

///|
fn min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn max_int(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
pub fn Region::merge(self : Region, other : Region) -> Region {
  if other.is_empty() {
    return self
  }
  if self.is_empty() {
    return other
  }
  let left = min_int(self.left, other.left)
  let top = min_int(self.top, other.top)
  // wrapping_add_unsigned
  let right = max_int(self.left + self.width, other.left + other.width)
  let bottom = max_int(self.top + self.height, other.top + other.height)
  {
    left,
    top,
    width: abs_diff(right, left),
    height: abs_diff(bottom, top),
  }
}

///|
pub fn Region::pad(self : Region, size : Int) -> Region {
  {
    left: sat_sub_unsigned(self.left, size),
    top: sat_sub_unsigned(self.top, size),
    width: self.width + size * 2,
    height: self.height + size * 2,
  }
}

///|
pub fn Region::downsample(self : Region, factor : Int) -> Region {
  if factor == 0 {
    return self
  }
  let add = (1 << factor) - 1
  let new_left = self.left >> factor
  let new_top = self.top >> factor
  let adj_width = self.width + abs_diff(self.left, new_left << factor)
  let adj_height = self.height + abs_diff(self.top, new_top << factor)
  {
    left: new_left,
    top: new_top,
    width: ((adj_width + add).reinterpret_as_uint() >> factor).reinterpret_as_int(),
    height: ((adj_height + add).reinterpret_as_uint() >> factor).reinterpret_as_int(),
  }
}

///|
pub fn Region::downsample_separate(
  self : Region,
  factor_x : Int,
  factor_y : Int,
) -> Region {
  if factor_x == 0 && factor_y == 0 {
    return self
  }
  let add_x = (1 << factor_x) - 1
  let new_left = self.left >> factor_x
  let adj_width = self.width + abs_diff(self.left, new_left << factor_x)
  let add_y = (1 << factor_y) - 1
  let new_top = self.top >> factor_y
  let adj_height = self.height + abs_diff(self.top, new_top << factor_y)
  {
    left: new_left,
    top: new_top,
    width: ((adj_width + add_x).reinterpret_as_uint() >> factor_x).reinterpret_as_int(),
    height: ((adj_height + add_y).reinterpret_as_uint() >> factor_y).reinterpret_as_int(),
  }
}

///|
pub fn Region::downsample_with_shift(
  self : Region,
  shift : @modular.ChannelShift,
) -> Region {
  let factor_x = shift.hshift()
  let factor_y = shift.vshift()
  let left = self.left >> factor_x
  let top = self.top >> factor_y
  let (width, height) = shift.shift_size((self.width, self.height))
  { left, top, width, height }
}

///|
pub fn Region::upsample(self : Region, factor : Int) -> Region {
  self.upsample_separate(factor, factor)
}

///|
pub fn Region::upsample_separate(
  self : Region,
  factor_x : Int,
  factor_y : Int,
) -> Region {
  {
    left: self.left << factor_x,
    top: self.top << factor_y,
    width: self.width << factor_x,
    height: self.height << factor_y,
  }
}

///|
/// Aligns the region to a multiple of `grid_dim` (a power of two).
pub fn Region::container_aligned(self : Region, grid_dim : Int) -> Region {
  let add = grid_dim - 1
  let mask = add.lnot()
  let new_left = self.left & mask
  let new_top = self.top & mask
  let x_diff = abs_diff(self.left, new_left)
  let y_diff = abs_diff(self.top, new_top)
  {
    left: new_left,
    top: new_top,
    width: (self.width + x_diff + add) & mask,
    height: (self.height + y_diff + add) & mask,
  }
}

///|
pub fn Region::apply_orientation(
  self : Region,
  image_header : @image.ImageHeader,
) -> Region {
  let image_width = image_header.width_with_orientation()
  let image_height = image_header.height_with_orientation()
  let (_, _, left0, top0) = image_header.metadata.apply_orientation(
    image_width,
    image_height,
    self.left,
    self.top,
    true,
  )
  let (_, _, right0, bottom0) = image_header.metadata.apply_orientation(
    image_width,
    image_height,
    self.left + self.width - 1,
    self.top + self.height - 1,
    true,
  )
  let (left, right) = if left0 > right0 {
    (right0, left0)
  } else {
    (left0, right0)
  }
  let (top, bottom) = if top0 > bottom0 {
    (bottom0, top0)
  } else {
    (top0, bottom0)
  }
  {
    left,
    top,
    width: abs_diff(right, left) + 1,
    height: abs_diff(bottom, top) + 1,
  }
}
