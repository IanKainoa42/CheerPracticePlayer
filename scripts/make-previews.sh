#!/bin/bash
# Regenerate App Store preview variants from marketing/app_previews/source.mp4.
#
# source.mp4 must be:
#   - H.264, AAC stereo, 30fps
#   - <= 30 seconds (Apple's hard cap on App Previews)
#   - any square or portrait aspect (this script letterboxes to portrait)
#
# Outputs (committed):
#   marketing/app_previews/preview-iphone-6.9.mp4   886x1920  (covers 6.5/6.7/6.9 slots)
#   marketing/app_previews/preview-ipad-13.mp4      1200x1600 (covers iPad Pro 12.9/13)
#   marketing/app_previews/preview-*-poster.png     poster frame at ~15s
#
# Run from repo root: ./scripts/make-previews.sh
# Requires: ffmpeg (brew install ffmpeg).

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg not found. brew install ffmpeg"
  exit 1
fi

DIR="marketing/app_previews"
SRC="$DIR/source.mp4"
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

# Letterbox into 886x1920 (iPhone 6.5/6.7/6.9 slots).
ffmpeg -nostdin -y -i "$SRC" \
  -vf "scale=886:886:flags=lanczos,pad=886:1920:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
  -frames:v 900 \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -r 30 -crf 22 \
  -c:a aac -b:a 128k -ar 48000 -shortest \
  -movflags +faststart \
  "$DIR/preview-iphone-6.9.mp4"

# Letterbox into 1200x1600 (iPad Pro 12.9/13 slots).
ffmpeg -nostdin -y -i "$SRC" \
  -vf "scale=1200:1200:flags=lanczos,pad=1200:1600:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
  -frames:v 900 \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -r 30 -crf 22 \
  -c:a aac -b:a 128k -ar 48000 -shortest \
  -movflags +faststart \
  "$DIR/preview-ipad-13.mp4"

# Poster frames at ~15s into each variant.
ffmpeg -nostdin -y -ss 15 -i "$DIR/preview-iphone-6.9.mp4" -frames:v 1 -q:v 2 "$DIR/preview-iphone-6.9-poster.png"
ffmpeg -nostdin -y -ss 15 -i "$DIR/preview-ipad-13.mp4"    -frames:v 1 -q:v 2 "$DIR/preview-ipad-13-poster.png"

echo "Done. Variants:"
ls -lh "$DIR"/preview-*.mp4 "$DIR"/preview-*-poster.png
