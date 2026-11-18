// Port of jxl-color `fastmath/rational_poly.rs` (generic implementation).

///|
/// Evaluates the rational polynomial `P(x) / Q(x)` with Horner's method.
/// Coefficients are in ascending order of degree.
fn rational_poly_eval_generic(
  x : Float,
  p : FixedArray[Float],
  q : FixedArray[Float],
) -> Float {
  let mut yp = p[p.length() - 1]
  for i = p.length() - 2; i >= 0; i = i - 1 {
    yp = yp * x + p[i]
  }
  let mut yq = q[q.length() - 1]
  for i = q.length() - 2; i >= 0; i = i - 1 {
    yq = yq * x + q[i]
  }
  yp / yq
}
