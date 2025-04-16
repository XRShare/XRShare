#!/usr/bin/env bash
# SwiftLint autocorrect helper script
set -euo pipefail

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: SwiftLint not found. Please install via 'brew install swiftlint'." >&2
  exit 1
fi

echo "Running SwiftLint autocorrect..."
swiftlint autocorrect --format
echo "Autocorrect complete."