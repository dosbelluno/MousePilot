#!/bin/bash
set -euo pipefail
mousepilot_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -d "$mousepilot_root/build/MousePilot-Gestures.app" ]; then
  "$mousepilot_root/scripts/build-app.sh"
fi
open "$mousepilot_root/build/MousePilot-Gestures.app"
