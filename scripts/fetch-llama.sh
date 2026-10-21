#!/bin/sh
# Downloads the pinned llama.cpp xcframework and checks its SHA-256 before
# unpacking it into Vendor/ (git-ignored).
# Pin and hash: DECISIONS.md D-015.
set -eu
TAG="b11799"
SHA256="9fa07281f680fb38251b45e4e4fcc7cfc74288325461be1dcdc77311efef9809"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${TAG}/llama-${TAG}-xcframework.zip"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $URL"
curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error -o "$WORK/llama.zip" "$URL"
ACTUAL="$(shasum -a 256 "$WORK/llama.zip" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$SHA256" ]; then
  echo "SHA-256 mismatch: expected $SHA256, got $ACTUAL" >&2
  exit 1
fi
echo "SHA-256 OK"
mkdir -p "$WORK/unzipped"
unzip -q "$WORK/llama.zip" -d "$WORK/unzipped"
FRAMEWORK="$(find "$WORK/unzipped" -name 'llama.xcframework' -maxdepth 3 -type d | head -1)"
[ -n "$FRAMEWORK" ] || { echo "llama.xcframework not found in archive" >&2; exit 1; }
rm -rf "$VENDOR/llama.xcframework"
mkdir -p "$VENDOR"
cp -R "$FRAMEWORK" "$VENDOR/"
echo "$TAG $SHA256" > "$VENDOR/PINNED"
echo "Installed $VENDOR/llama.xcframework ($TAG)"
