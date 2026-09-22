#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
APP="${TEACHINGFOCUS_APP_PATH:-.build/artifacts/TeachingFocus.app}/Contents/MacOS/TeachingFocus"
"$APP" --render-checks
"$APP" --interaction-checks
if [[ "${1:-}" == "--live" ]]; then
  "$APP" --diagnostics
  "$APP" --capture-checks
fi
