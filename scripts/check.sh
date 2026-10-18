#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run CoreChecks
if xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1; then
  swift test
else
  echo "Full XCTest requires Xcode. CoreChecks passed using the command-line tools."
fi
