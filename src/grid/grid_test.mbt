///|
test "subgrid views share the buffer" {
  let g = @grid.Grid::new(4, 3, 0)
  let s = g.as_subgrid().subgrid(1, 1, 2, 2)
  s.set(1, 1, 7)
  assert_eq(g.get(2, 2), 7)
  let groups = g.as_subgrid().into_groups(3, 2)
  assert_eq(groups.length(), 4)
  assert_eq(groups[3].width(), 1)
  assert_eq(groups[3].height(), 1)
  let t = @grid.AllocTracker::with_limit(100)
  let r : Result[@grid.Grid[Int32], @bitstream.JxlError] = Ok(
    @grid.Grid::with_alloc_tracker(10, 10, 0, Some(t)),
  ) catch {
    e => Err(e)
  }
  assert_true(r is Err(@bitstream.OutOfMemory(_)))
}
