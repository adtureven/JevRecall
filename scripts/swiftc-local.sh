#!/bin/bash
# Work around stale duplicate SwiftBridging module maps left by some CLT upgrades.
# The VFS overlay changes only compiler input; no system files are modified.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_COMPILER="$(xcrun --find swiftc)"
mkdir -p "$PROJECT_DIR/.build/module-cache-local"
python3 - "$SWIFT_COMPILER" "$PROJECT_DIR/.build" <<'PY'
import json
from pathlib import Path
import sys
compiler = Path(sys.argv[1])
build = Path(sys.argv[2])
include = compiler.parent.parent / 'include' / 'swift'
old = include / 'module.modulemap'
current = include / 'bridging.modulemap'
roots = []
if old.exists() and current.exists() and 'module SwiftBridging {' in old.read_text() and 'module SwiftBridging {' in current.read_text():
    empty = build / 'empty-legacy.modulemap'
    empty.write_text('// Legacy duplicate hidden for this compilation only.\n')
    roots.append({'type': 'file', 'name': str(old), 'external-contents': str(empty)})
overlay = {'version': 0, 'case-sensitive': 'false', 'roots': roots}
(build / 'swift-overlay.json').write_text(json.dumps(overlay))
PY
exec "$SWIFT_COMPILER" -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$PROJECT_DIR/.build/module-cache-local" \
  -vfsoverlay "$PROJECT_DIR/.build/swift-overlay.json" "$@"
