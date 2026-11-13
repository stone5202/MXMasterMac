#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
python3 -I tools/solaar-features-test/config_harness.py Sources/Config.swift "$OUT/settings.swift"
swiftc -module-cache-path "$OUT/mc" Sources/SolaarFeatures.swift "$OUT/settings.swift" tools/solaar-features-test/main.swift -o "$OUT/test"
"$OUT/test"
