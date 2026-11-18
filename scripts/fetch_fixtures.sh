#!/usr/bin/env bash
# Prepare the test data of the `suica/jxl_tests` module (tests/) in the layout
# of jxl-oxide-tests, using only system tools (git, curl, zstd):
#
#   tests/conformance/            the libjxl conformance repository (a git
#                                 submodule of jxl-oxide-tests upstream)
#   tests/decode/                 jxl-oxide-testdata (submodule upstream)
#   tests/tests/cache/            the cache of `download_object_with_cache` /
#                                 `download_url_with_cache` ($JXL_OXIDE_CACHE
#                                 if set), with upstream's file names:
#     {hash}.npy, {hash}.icc      conformance objects, from
#                                 https://storage.googleapis.com/storage/v1/b/jxl-conformance/o/objects%2F{hash}?alt=media
#                                 (every hash named in tests/tests/conformance
#                                 and in the testcases' test.json)
#     {name}.buf.zst              decode fixtures given by output.buf.zst.url
#     {name}.buf                  every decode fixture decompressed (read by
#                                 the interim decode test until src/zstd lands)
#     cmyk_layers.{lcms2,moxcms}.npy   step `cms`: jxl-oxide's renders of
#                                 tests/tests/cms/cmyk_layers.jxl to linear sRGB
#                                 (interim cms test until src/moxcms lands)
#     oxide/alpha_premultiplied.npy    step `oxide-ref`: jxl-oxide's render of
#                                 that conformance case (render_conformance)
#
# The MoonBit tests have no HTTP client (jxl-oxide-tests without its `net`
# feature): a file missing here fails the test with upstream's message.
#
# Sources (override with environment variables):
#   CONFORMANCE_DIR   existing checkout of https://github.com/libjxl/conformance;
#                     linked, not copied. Its .objects/ (from its
#                     scripts/download_and_symlink*.sh) is used instead of
#                     downloading where present. If unset, the repository is
#                     cloned into tests/conformance and its download script runs
#                     (render_conformance reads the testcases' symlinked objects).
#   DECODE_DIR        existing checkout of https://github.com/tirr-c/jxl-oxide-testdata;
#                     if unset, it is cloned into tests/decode.
#   JXL_OXIDE_CLI / JXL_OXIDE_SRC   the jxl-oxide CLI, or a checkout to build it
#                     with cargo (steps `cms` and `oxide-ref`).
#
# Usage: scripts/fetch_fixtures.sh [conformance|decode|cms|oxide-ref|all]
#   (default: all = conformance and decode)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTS="$ROOT/tests"
CACHE="${JXL_OXIDE_CACHE:-$TESTS/tests/cache}"
mkdir -p "$CACHE"
what="${1:-all}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not found" >&2; exit 1; }; }

object_url() {
  echo "https://storage.googleapis.com/storage/v1/b/jxl-conformance/o/objects%2F$1?alt=media"
}

# cache_object <hash> <ext>
cache_object() {
  local hash="$1" ext="$2" out="$CACHE/$1.$2"
  [ -s "$out" ] && return 0
  local local_obj="$TESTS/conformance/.objects/$hash"
  if [ -s "$local_obj" ]; then
    cp "$local_obj" "$out.part"
  else
    need curl
    echo "downloading $hash.$ext"
    curl -fsSL -o "$out.part" "$(object_url "$hash")"
  fi
  mv "$out.part" "$out"
}

fetch_conformance() {
  if [ -n "${CONFORMANCE_DIR:-}" ]; then
    ln -sfn "$(cd "$CONFORMANCE_DIR" && pwd)" "$TESTS/conformance"
  elif [ ! -d "$TESTS/conformance/.git" ]; then
    need git; need curl
    rm -f "$TESTS/conformance"
    git clone --depth 1 https://github.com/libjxl/conformance.git "$TESTS/conformance"
    (cd "$TESTS/conformance" && bash scripts/download_and_symlink_using_curl.sh)
  fi
  [ -d "$TESTS/conformance/testcases" ] || { echo "error: no testcases in $TESTS/conformance" >&2; exit 1; }
  # npy_hash= / icc_hash= of the conformance tests (pending files too)
  local f
  for f in "$TESTS"/tests/conformance/*.mbt*; do
    { grep -oE 'npy_hash="[0-9a-f]{64}"' "$f" || true; } | cut -d'"' -f2 | while read -r h; do cache_object "$h" npy; done
    { grep -oE 'icc_hash="[0-9a-f]{64}"' "$f" || true; } | cut -d'"' -f2 | while read -r h; do cache_object "$h" icc; done
  done
  # objects named in test.json (reference images and ICC profiles)
  for f in "$TESTS"/conformance/testcases/*/test.json; do
    python3 -I - "$f" <<'EOF' | while read -r h ext; do cache_object "$h" "$ext"; done
import json, sys
sums = json.load(open(sys.argv[1])).get("sha256sums", {})
for name, h in sums.items():
    if name == "reference_image.npy":
        print(h, "npy")
    elif name.endswith(".icc"):
        print(h, "icc")
EOF
  done
  echo "conformance: $TESTS/conformance, objects in $CACHE"
}

fetch_decode() {
  need zstd
  if [ -n "${DECODE_DIR:-}" ]; then
    ln -sfn "$(cd "$DECODE_DIR" && pwd)" "$TESTS/decode"
  elif [ ! -d "$TESTS/decode/.git" ]; then
    need git
    rm -f "$TESTS/decode"
    git clone --depth 1 https://github.com/tirr-c/jxl-oxide-testdata.git "$TESTS/decode"
  fi
  local d name zst
  for d in "$TESTS"/decode/*/; do
    name="$(basename "$d")"
    [ -f "$d/input.jxl" ] || continue
    zst=""
    if [ -f "$d/output.buf.zst" ]; then
      zst="$d/output.buf.zst"
    elif [ -f "$d/output.buf.zst.url" ]; then
      zst="$CACHE/$name.buf.zst"
      if [ ! -s "$zst" ]; then
        need curl
        local url
        url="$(tr -d '[:space:]' < "$d/output.buf.zst.url")"
        echo "downloading $url"
        curl -fsSL -o "$zst.part" "$url"
        mv "$zst.part" "$zst"
      fi
    fi
    if [ -n "$zst" ] && { [ ! -s "$CACHE/$name.buf" ] || [ "$zst" -nt "$CACHE/$name.buf" ]; }; then
      zstd -q -d -f -o "$CACHE/$name.buf" "$zst"
    fi
    echo "decode: $name"
  done
}

oxide_cli() {
  local cli="${JXL_OXIDE_CLI:-}"
  if [ -z "$cli" ]; then
    [ -n "${JXL_OXIDE_SRC:-}" ] || { echo "error: set JXL_OXIDE_CLI or JXL_OXIDE_SRC" >&2; exit 1; }
    need cargo
    (cd "$JXL_OXIDE_SRC" && CARGO_TARGET_DIR="$CACHE/cargo" cargo build --locked --release -p jxl-oxide-cli) >&2
    cli="$CACHE/cargo/release/jxl-oxide"
  fi
  echo "$cli"
}

fetch_cms() {
  local cli cms
  cli="$(oxide_cli)"
  for cms in lcms2 moxcms; do
    "$cli" "$TESTS/tests/cms/cmyk_layers.jxl" --cms "$cms" \
      --target-colorspace "srgb,tf=linear" -f npy -o "$CACHE/cmyk_layers.$cms.npy"
  done
  echo "cms: $CACHE/cmyk_layers.{lcms2,moxcms}.npy"
}

fetch_oxide_ref() {
  local cli case_dir
  cli="$(oxide_cli)"
  case_dir="$TESTS/conformance/testcases/alpha_premultiplied"
  [ -f "$case_dir/input.jxl" ] && [ -e "$case_dir/reference.icc" ] || {
    echo "error: $case_dir not found (run the conformance step first)" >&2; exit 1; }
  mkdir -p "$CACHE/oxide"
  "$cli" "$case_dir/input.jxl" --target-icc "$case_dir/reference.icc" \
    -f npy -o "$CACHE/oxide/alpha_premultiplied.npy"
  echo "oxide-ref: $CACHE/oxide/alpha_premultiplied.npy"
}

case "$what" in
  conformance) fetch_conformance ;;
  decode) fetch_decode ;;
  cms) fetch_cms ;;
  oxide-ref) fetch_oxide_ref ;;
  all) fetch_conformance; fetch_decode ;;
  *) echo "usage: $0 [conformance|decode|cms|oxide-ref|all]" >&2; exit 2 ;;
esac
