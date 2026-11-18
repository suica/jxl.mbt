// Port of jxl-threadpool 1.0.0 (jxl-oxide 0.12.6) built without the `rayon`
// feature. MoonBit has no shared-memory threads on either target, so only the
// `None` implementation exists: every spawn runs the closure in place, exactly
// like upstream when `rayon` is disabled. The `rayon*` constructors are not
// provided, as upstream does not provide them without the feature.

///|
/// Thread pool wrapper.
///
/// Without multithreading support this struct has no multithreading
/// capability, and every spawn operation runs the given closure in place.
#derive(Debug)
pub struct JxlThreadPool {
  priv _private : Unit
}

///|
/// Fork-join scope created by a thread pool.
#derive(Debug)
pub struct JxlScope {
  priv _private : Unit
}

///|
/// Creates a "fake" thread pool without any multithreading capability.
///
/// Every spawn operation on this thread pool just runs the closure in the
/// current thread.
pub fn JxlThreadPool::none() -> JxlThreadPool {
  { _private: (), }
}

///|
pub impl Default for JxlThreadPool with fn default() {
  JxlThreadPool::none()
}

///|
/// Returns if the thread pool is capable of multithreading.
pub fn JxlThreadPool::is_multithreaded(self : JxlThreadPool) -> Bool {
  ignore(self)
  false
}

///|
/// Runs the given closure on the thread pool.
pub fn JxlThreadPool::spawn(self : JxlThreadPool, op : () -> Unit) -> Unit {
  ignore(self)
  op()
}

///|
/// Creates a fork-join scope of tasks.
pub fn[R] JxlThreadPool::scope(
  self : JxlThreadPool,
  op : (JxlScope) -> R raise?,
) -> R raise? {
  ignore(self)
  op({ _private: (), })
}

///|
/// Consumes the array, and runs a job for each element of it.
pub fn[T] JxlThreadPool::for_each_vec(
  self : JxlThreadPool,
  v : Array[T],
  op : (T) -> Unit raise?,
) -> Unit raise? {
  ignore(self)
  for item in v {
    op(item)
  }
}

///|
/// Consumes the array, and runs a job for each element of it, threading a
/// per-worker state initialised from `init`.
pub fn[T, U] JxlThreadPool::for_each_vec_with(
  self : JxlThreadPool,
  v : Array[T],
  init : U,
  op : (Ref[U], T) -> Unit raise?,
) -> Unit raise? {
  ignore(self)
  let state = Ref(init)
  for item in v {
    op(state, item)
  }
}

///|
/// Spawns the given closure in the current fork-join scope.
pub fn JxlScope::spawn(
  self : JxlScope,
  op : (JxlScope) -> Unit raise?,
) -> Unit raise? {
  ignore(self)
  op({ _private: (), })
}

///|
test "none pool runs in place" {
  let pool = JxlThreadPool::none()
  assert_false(pool.is_multithreaded())
  let log = []
  pool.spawn(() => log.push(1))
  pool.scope(s => s.spawn(_ => log.push(2)))
  pool.for_each_vec([3, 4], x => log.push(x))
  pool.for_each_vec_with([5, 6], 10, (st, x) => {
    st.val += 1
    log.push(x + st.val)
  })
  assert_eq(log, [1, 2, 3, 4, 16, 18])
}
