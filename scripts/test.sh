#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
APP="../TeachingFocus.app/Contents/MacOS/TeachingFocus"
"$APP" --render-checks
if [[ "${1:-}" == "--live" ]]; then
  "$APP" --diagnostics
  "$APP" --capture-checks
fi
