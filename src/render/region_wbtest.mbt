///|
test "region intersection" {
  let a : Region = { left: 0, top: 0, width: 10, height: 10, }
  let b : Region = { left: 5, top: -3, width: 10, height: 6, }
  debug_inspect(
    a.intersection(b),
    content="{ left: 5, top: 0, width: 5, height: 3 }",
  )
  debug_inspect(
    b.intersection(a),
    content="{ left: 5, top: 0, width: 5, height: 3 }",
  )
  let c : Region = { left: 10, top: 0, width: 1, height: 1, }
  inspect(a.intersection(c).is_empty(), content="true")
  inspect(a.intersection(Region::empty()).is_empty(), content="true")
}

///|
test "region downsample and upsample" {
  let r : Region = { left: -3, top: 5, width: 10, height: 7, }
  debug_inspect(
    r.downsample(1),
    content="{ left: -2, top: 2, width: 6, height: 4 }",
  )
  debug_inspect(
    r.downsample(3),
    content="{ left: -1, top: 0, width: 2, height: 2 }",
  )
  debug_inspect(
    r.downsample_separate(1, 0),
    content="{ left: -2, top: 5, width: 6, height: 7 }",
  )
  debug_inspect(
    r.upsample(2),
    content="{ left: -12, top: 20, width: 40, height: 28 }",
  )
  debug_inspect(
    r.downsample(0),
    content="{ left: -3, top: 5, width: 10, height: 7 }",
  )
}

///|
test "region pad merge contains" {
  let r : Region = { left: 1, top: 2, width: 3, height: 4, }
  debug_inspect(r.pad(2), content="{ left: -1, top: 0, width: 7, height: 8 }")
  let s : Region = { left: 10, top: -5, width: 1, height: 1, }
  debug_inspect(
    r.merge(s),
    content="{ left: 1, top: -5, width: 10, height: 11 }",
  )
  inspect(r.merge(s).contains(r), content="true")
  inspect(r.contains(s), content="false")
  inspect(r.contains(Region::empty()), content="true")
  debug_inspect(
    r.translate(-1, 3),
    content="{ left: 0, top: 5, width: 3, height: 4 }",
  )
}

///|
test "region container_aligned" {
  let r : Region = { left: 13, top: -3, width: 10, height: 3, }
  debug_inspect(
    r.container_aligned(8),
    content="{ left: 8, top: -8, width: 16, height: 8 }",
  )
}

///|
test "region saturating right" {
  let r : Region = { left: 0x7ffffff0, top: 0, width: 0x100, height: 1, }
  inspect(r.right(), content="2147483647")
}
