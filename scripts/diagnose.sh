#!/bin/bash
set -euo pipefail
mousepilot_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mousepilot_app="$mousepilot_root/build/MousePilot-Gestures.app"
mousepilot_report="$HOME/Library/Application Support/MousePilot/last-diagnostic.txt"
mousepilot_request_id="$(uuidgen)"
if [ ! -d "$mousepilot_app" ]; then
  printf '%s\n' 'Build MousePilot first with scripts/build-app.sh.' >&2
  exit 1
fi
# LaunchServices attributes TCC checks to the signed app. Direct shell execution
# can attribute them to Terminal/Codex instead. --diagnose exits before any window
# or mapping engine starts and never posts mouse or keyboard events.
open -g -n "$mousepilot_app" --args --diagnose --request-id "$mousepilot_request_id"
for mousepilot_attempt in {1..30}; do
  if [ -f "$mousepilot_report" ] && /usr/bin/grep -Fq "requestID: $mousepilot_request_id" "$mousepilot_report"; then
    cat "$mousepilot_report"
    exit 0
  fi
  sleep 0.2
done
printf '%s\n' 'No fresh diagnostic report. Check the app signature and try Settings → 진단 복사.' >&2
exit 1
