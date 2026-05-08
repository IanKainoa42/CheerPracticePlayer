#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="CheerPracticePlayer.xcodeproj"
SCHEME="CheerPracticePlayer"
DESTINATION="${DESTINATION:-platform=macOS,variant=Mac Catalyst,name=My Mac}"
DERIVED_DATA="$PWD/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug-maccatalyst/CheerPracticePlayer.app"
# Local Mac Studio dogfood should launch even when no Mac Development cert is installed.
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep -Fq "variant:Mac Catalyst"; then
  echo "Mac Catalyst destination is not available for $SCHEME" >&2
  exit 1
fi

# Make relaunch visible and avoid stale simulator/device builds being mistaken for the active app.
killall CheerPracticePlayer 2>/dev/null || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -toolchain XcodeDefault \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
  build

test -d "$APP"
echo "Built Mac Catalyst app: $APP"
open -n "$APP"
echo "Launched Mac Catalyst app on this Mac."
