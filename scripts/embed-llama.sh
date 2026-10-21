#!/bin/sh
# Xcode build phase: copies and signs llama.framework into the app, for
# iPhone (device) builds only. The prebuilt xcframework has no Simulator
# slice, so Simulator builds skip it and run in Classic Mode (DECISIONS.md D-016).
set -eu
if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  echo "Not a device build (${PLATFORM_NAME:-unknown}); llama.framework not embedded."
  exit 0
fi
SRC="$PROJECT_DIR/Vendor/llama.xcframework/ios-arm64/llama.framework"
if [ ! -d "$SRC" ]; then
  echo "error: $SRC is missing. Run scripts/fetch-llama.sh first." >&2
  exit 1
fi
DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$DEST"
rm -rf "$DEST/llama.framework"
cp -R "$SRC" "$DEST/"
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$DEST/llama.framework"
fi
echo "Embedded llama.framework"
