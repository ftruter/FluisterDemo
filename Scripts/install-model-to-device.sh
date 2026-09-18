#!/usr/bin/env bash
# Copy the local Fluister-turbo WhisperKit folder into the app's Documents on a
# connected iPhone or iPad. The app looks for Documents/fluister-turbo-v2 on launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="truter.com.fluister.demo"
DEST_NAME="fluister-turbo-v2"
CANDIDATES=(
  "${FLUISTER_MODEL_FOLDER:-}"
  "$(cd "$ROOT/.." && pwd)/FluisterTV/Tools/convert/out/fluister-turbo-v2"
  "$ROOT/Models/fluister-turbo-v2"
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

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected|available \(paired\)/ && /iPhone|iPad/ { print $1; exit }')"
fi
if [[ -z "$DEVICE" ]]; then
  echo "No iPhone/iPad connected. Unlock it, trust this Mac, then pass the device name:" >&2
  echo "  $0 'iPhoneJFT'" >&2
  xcrun devicectl list devices >&2
  exit 1
fi

echo "Copying $SRC"
echo "  -> $DEVICE Documents/$DEST_NAME  (~1.5 GB, can take a few minutes)"
xcrun devicectl device copy to \
  --device "$DEVICE" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "$SRC" \
  --destination "Documents/$DEST_NAME" \
  --remove-existing-content true
echo "Done. Force-quit Fluister on the device and open it again."
