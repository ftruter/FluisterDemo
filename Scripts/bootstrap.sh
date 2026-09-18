#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SRC="${1:-}"
ICON_DST="${ROOT}/FluisterDemo/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if [[ -n "${ICON_SRC}" && -f "${ICON_SRC}" ]]; then
  sips -s format png -z 1024 1024 "${ICON_SRC}" --out "${ICON_DST}" >/dev/null
  echo "Wrote ${ICON_DST}"
fi
if [[ ! -f "${ICON_DST}" ]]; then
  echo "warning: no AppIcon.png yet; Xcode will use a placeholder" >&2
fi
chmod +x "${ROOT}/Scripts/link-model.sh" "${ROOT}/Scripts/generate_xcodeproj.rb" "${ROOT}/Scripts/select-afrikaans-clips.py"
ruby "${ROOT}/Scripts/generate_xcodeproj.rb" --force
echo "Open ${ROOT}/FluisterDemo.xcodeproj"
