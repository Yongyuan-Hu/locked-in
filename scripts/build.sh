#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="0.1.0"
engine_version="4.0.2"
engine_sha="15d8fd17839746c608d0c4e929b650d741e691ebee6f893320c783e86ac75926"
cache="$PWD/.engine-cache"
archive="$cache/SelfControl-$engine_version.zip"
mkdir -p "$cache" "$PWD/dist"

if [[ ! -f "$archive" ]]; then
  /usr/bin/curl --fail --location --output "$archive" "https://downloads.selfcontrolapp.com/SelfControl-$engine_version.zip"
fi
actual_sha=$(/usr/bin/shasum -a 256 "$archive")
if [[ "${actual_sha%% *}" != "$engine_sha" ]]; then
  echo "The upstream engine archive did not match its pinned checksum." >&2
  exit 1
fi
if [[ ! -d "$cache/SelfControl.app" ]]; then
  /usr/bin/ditto -x -k "$archive" "$cache"
fi
engine="$cache/SelfControl.app"
/usr/bin/codesign --verify --deep --strict "$engine"
signature=$(/usr/bin/codesign -dv --verbose=4 "$engine" 2>&1)
if [[ "$signature" != *"TeamIdentifier=EG6ZYP3AQH"* ]]; then
  echo "The engine is not signed by the expected SelfControl developer." >&2
  exit 1
fi

for architecture in arm64 x86_64; do
  /usr/bin/xcrun swift build --configuration release --arch "$architecture" --product LockedIn
done

app="$PWD/dist/LockedIn.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
/usr/bin/lipo -create .build/arm64-apple-macosx/release/LockedIn .build/x86_64-apple-macosx/release/LockedIn -output "$app/Contents/MacOS/LockedIn"
/bin/cp Resources/Info.plist "$app/Contents/Info.plist"
/bin/cp LICENSE "$app/Contents/Resources/LICENSE"
/bin/cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
/bin/cp engine-source.json "$app/Contents/Resources/engine-source.json"
/usr/bin/ditto "$engine" "$app/Contents/Resources/SelfControl.app"
/usr/bin/ditto -c -k --keepParent Vendor/SelfControl "$app/Contents/Resources/SelfControl-4.0.2-source.zip"

# Sign only the new outer app. Preserve the upstream engine's developer signature.
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
/usr/bin/codesign --verify --deep --strict "$app/Contents/Resources/SelfControl.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/dist/LockedIn-$version-macOS-universal.zip"
/usr/bin/shasum -a 256 "dist/LockedIn-$version-macOS-universal.zip" > dist/SHA256SUMS.txt
echo "Built $app"
