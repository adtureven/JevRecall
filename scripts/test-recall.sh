#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/.build/module-cache"
bash "$PROJECT_DIR/scripts/swiftc-local.sh" -parse-as-library \
  "$PROJECT_DIR/apps/recall/Core.swift" "$PROJECT_DIR/apps/recall/Tests.swift" \
  -o "$PROJECT_DIR/.build/recall-tests"
cd "$PROJECT_DIR"
exec "$PROJECT_DIR/.build/recall-tests" "$@"
