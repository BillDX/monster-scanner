#!/bin/sh
# Downloads the pinned Qwen3-VL-2B model files to Models/ (git-ignored) for
# Mac-side testing and copying to a development iPhone. The app downloads
# its own copy; these are the same files and hashes. Pins: DECISIONS.md D-015.
set -eu
REPO="Qwen/Qwen3-VL-2B-Instruct-GGUF"
REVISION="52d6c8ffea26cc873ac5ad116f8631268d7eb503"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Models"
mkdir -p "$DEST"

fetch() {
  NAME="$1"; SHA256="$2"
  URL="https://huggingface.co/${REPO}/resolve/${REVISION}/${NAME}"
  if [ -f "$DEST/$NAME" ] && [ "$(shasum -a 256 "$DEST/$NAME" | cut -d' ' -f1)" = "$SHA256" ]; then
    echo "$NAME already present and verified"; return
  fi
  echo "Downloading $NAME"
  curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error -C - -o "$DEST/$NAME.part" "$URL"
  ACTUAL="$(shasum -a 256 "$DEST/$NAME.part" | cut -d' ' -f1)"
  if [ "$ACTUAL" != "$SHA256" ]; then
    echo "SHA-256 mismatch for $NAME: expected $SHA256, got $ACTUAL" >&2
    exit 1
  fi
  mv "$DEST/$NAME.part" "$DEST/$NAME"
  echo "$NAME verified"
}

fetch "Qwen3VL-2B-Instruct-Q4_K_M.gguf" "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae"
fetch "mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf" "f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82"
