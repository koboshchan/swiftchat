#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v swiftformat >/dev/null 2>&1; then
  swiftformat --lint "$ROOT_DIR/App" "$ROOT_DIR/Packages"
fi

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --strict --config "$ROOT_DIR/.swiftlint.yml"
fi

if rg -n --hidden -g '!README.md' -g '!script/ci.sh' -g '!.git/**' '(Authorization:[[:space:]]*(Bot|Bearer)?[[:space:]]*[A-Za-z0-9._-]{24,}|mfa\.[A-Za-z0-9_-]{20,})' "$ROOT_DIR"; then
  echo "Potential credential material found." >&2
  exit 1
fi

swift test --package-path "$ROOT_DIR/App"
for package in SwiftchatModels DiscordProtocol SwiftchatPersistence MessageRendering SwiftchatPluginSDK MediaPipeline DaveKit; do
  swift test --package-path "$ROOT_DIR/Packages/$package"
done
