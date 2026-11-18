#!/usr/bin/env bash
# Prepare test fixtures for the `suica/jxl_tests` module in fixtures/cache/
# (gitignored), using only system tools (git, curl, zstd).
#
#   fixtures/cache/conformance/<case>/{input.jxl,reference_image.npy,reference.icc,test.json}
#       libjxl conformance testcases (incl. the *_5 level-5 variants)
#   fixtures/cache/decode/<case>/{input.jxl,output.buf}
#       jxl-oxide decode test data; output.buf is the decompressed output.buf.zst
#   fixtures/cache/cms/cmyk_layers.{lcms2,moxcms}.npy   (step `cms`, not in `all`)
#       tests/data/cms/cmyk_layers.jxl rendered to linear sRGB by jxl-oxide with
#       Little CMS 2 and with moxcms: the references of the cms test (upstream
#       compares those two CMSs; here the MoonBit CMS is compared with both).
#       Needs the jxl-oxide CLI: JXL_OXIDE_CLI=<path to the jxl-oxide binary>,
#       or JXL_OXIDE_SRC=<jxl-oxide checkout> and cargo to build it.
#   fixtures/cache/oxide/alpha_premultiplied.npy   (step `oxide-ref`, not in `all`)
#       conformance case alpha_premultiplied decoded by jxl-oxide to its
#       reference.icc (f32 npy, 1x1024x1024x4, 16 MB): reference of the
#       render_conformance test "alpha_premultiplied vs jxl-oxide". Needs the
#       conformance step and the jxl-oxide CLI (as for `cms`).
#
# Sources (override with environment variables):
#   CONFORMANCE_DIR   existing checkout of https://github.com/libjxl/conformance
#                     whose reference objects are already downloaded and
#                     symlinked (scripts/download_and_symlink*.sh). It is linked,
#                     not copied. If unset, the repo is cloned into
#                     fixtures/cache/conformance-repo and its download script runs.
#   DECODE_DIR        existing checkout of https://github.com/tirr-c/jxl-oxide-testdata
#                     (jxl-oxide's crates/jxl-oxide-tests/decode). If unset, it is
#                     cloned into fixtures/cache/jxl-oxide-testdata.
#
# Usage: scripts/fetch_fixtures.sh [conformance|decode|cms|oxide-ref|all]   (default: all)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/fixtures/cache"
mkdir -p "$CACHE"
what="${1:-all}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not found" >&2; exit 1; }; }

fetch_conformance() {
  local src
  if [ -n "${CONFORMANCE_DIR:-}" ]; then
    src="$(cd "$CONFORMANCE_DIR" && pwd)"
  else
    need git; need curl
    src="$CACHE/conformance-repo"
    if [ ! -d "$src/.git" ]; then
      git clone --depth 1 https://github.com/libjxl/conformance.git "$src"
    fi
    (cd "$src" && bash scripts/download_and_symlink_using_curl.sh)
  fi
  [ -d "$src/testcases" ] || { echo "error: $src/testcases not found" >&2; exit 1; }
  ln -sfn "$src/testcases" "$CACHE/conformance"
  local missing=0
  for d in "$CACHE"/conformance/*/; do
    [ -f "$d/test.json" ] || continue
    for f in input.jxl reference_image.npy reference.icc; do
      if [ ! -e "$d/$f" ]; then
        echo "warning: missing $(basename "$d")/$f" >&2
        missing=1
      fi
    done
  done
  echo "conformance: $CACHE/conformance -> $src/testcases (missing files: $missing)"
}

fetch_decode() {
  need zstd
  local src
  if [ -n "${DECODE_DIR:-}" ]; then
    src="$(cd "$DECODE_DIR" && pwd)"
  else
    need git
    src="$CACHE/jxl-oxide-testdata"
    if [ ! -d "$src/.git" ]; then
      git clone --depth 1 https://github.com/tirr-c/jxl-oxide-testdata.git "$src"
    fi
  fi
  local out="$CACHE/decode"
  mkdir -p "$out" "$CACHE/downloads"
  for d in "$src"/*/; do
    local name
    name="$(basename "$d")"
    [ -f "$d/input.jxl" ] || continue
    mkdir -p "$out/$name"
    ln -sfn "$d/input.jxl" "$out/$name/input.jxl"
    local zst=""
    if [ -f "$d/output.buf.zst" ]; then
      zst="$d/output.buf.zst"
    elif [ -f "$d/output.buf.zst.url" ]; then
      need curl
      zst="$CACHE/downloads/$name.buf.zst"
      if [ ! -s "$zst" ]; then
        local url
        url="$(tr -d '[:space:]' < "$d/output.buf.zst.url")"
        echo "downloading $url"
        curl -fsSL -o "$zst.part" "$url"
        mv "$zst.part" "$zst"
      fi
    fi
    if [ -n "$zst" ] && { [ ! -s "$out/$name/output.buf" ] || [ "$zst" -nt "$out/$name/output.buf" ]; }; then
      zstd -q -d -f -o "$out/$name/output.buf" "$zst"
    fi
    echo "decode: $name$([ -s "$out/$name/output.buf" ] && echo ' (output.buf)')"
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

fetch_oxide_ref() {
  local cli case_dir
  cli="$(oxide_cli)"
  case_dir="$CACHE/conformance/alpha_premultiplied"
  [ -f "$case_dir/input.jxl" ] && [ -e "$case_dir/reference.icc" ] || {
    echo "error: $case_dir not found (run the conformance step first)" >&2; exit 1; }
  mkdir -p "$CACHE/oxide"
  "$cli" "$case_dir/input.jxl" --target-icc "$case_dir/reference.icc" \
    -f npy -o "$CACHE/oxide/alpha_premultiplied.npy"
  echo "oxide-ref: $CACHE/oxide/alpha_premultiplied.npy"
}

fetch_cms() {
  local cli
  cli="$(oxide_cli)"
  mkdir -p "$CACHE/cms"
  for cms in lcms2 moxcms; do
    "$cli" "$ROOT/tests/data/cms/cmyk_layers.jxl" --cms "$cms" \
      --target-colorspace "srgb,tf=linear" -f npy -o "$CACHE/cms/cmyk_layers.$cms.npy"
  done
  echo "cms: $CACHE/cms"
}

case "$what" in
  conformance) fetch_conformance ;;
  decode) fetch_decode ;;
  cms) fetch_cms ;;
  oxide-ref) fetch_oxide_ref ;;
  all) fetch_conformance; fetch_decode ;;
  *) echo "usage: $0 [conformance|decode|cms|oxide-ref|all]" >&2; exit 2 ;;
esac
