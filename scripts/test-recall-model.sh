#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$PROJECT_DIR/scripts/swiftc-local.sh" -parse-as-library \
  "$PROJECT_DIR/apps/recall/Core.swift" "$PROJECT_DIR/apps/recall/ClipboardDiscovery.swift" "$PROJECT_DIR/apps/recall/Model.swift" \
  "$PROJECT_DIR/apps/recall/ModelTests.swift" -o "$PROJECT_DIR/.build/recall-model-tests"
exec "$PROJECT_DIR/.build/recall-model-tests"
