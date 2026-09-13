#!/usr/bin/env bash
# Symlink a local Fluister-turbo WhisperKit folder into Application Support.
set -euo pipefail
BUNDLE_ID="truter.com.fluister.demo"
DEST="${HOME}/Library/Application Support/${BUNDLE_ID}/fluister-turbo-v2"
CANDIDATES=(
  "${FLUISTER_MODEL_FOLDER:-}"
  "$(cd "$(dirname "$0")/../.." && pwd)/FluisterTV/Tools/convert/out/fluister-turbo-v2"
)
SRC=""
for path in "${CANDIDATES[@]}"; do
  [[ -n "$path" && -d "$path/AudioEncoder.mlmodelc" ]] || continue
  SRC="$path"
  break
done
if [[ -z "$SRC" ]]; then
  echo "No fluister-turbo-v2 folder found. Convert the model first, or set FLUISTER_MODEL_FOLDER." >&2
  exit 1
fi
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
# Same-volume APFS clone when possible; otherwise a real copy (sandbox cannot follow a symlink out).
cp -cR "$SRC" "$DEST"
echo "Copied $SRC -> $DEST"
