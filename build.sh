#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
build_dir="$project_dir/build"
arch="$(uname -m)"
sdk="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$build_dir/module-cache"
staging="$(mktemp -d "$build_dir/.app.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
app="$staging/Notchline.app"
framework="$app/Contents/Frameworks/MediaRemoteAdapter.framework"
adapter="$project_dir/Vendor/MediaRemoteAdapter"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$framework/Versions/A/Resources"

plutil -lint "$project_dir/Info.plist" >/dev/null
cp "$project_dir/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/Notchline.icns" "$app/Contents/Resources/Notchline.icns"
cp "$adapter/bin/mediaremote-adapter.pl" "$app/Contents/Resources/"
cp "$adapter/LICENSE" "$app/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"

cat > "$framework/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.notchline.MediaRemoteAdapter</string>
    <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
PLIST

ln -s A "$framework/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$framework/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$framework/Resources"
xcrun --sdk macosx clang -dynamiclib -fobjc-arc -O2 -arch "$arch" -isysroot "$sdk"     -mmacosx-version-min=14.0 -I"$adapter/include" -I"$adapter/src"     -framework Foundation -framework AppKit -framework UniformTypeIdentifiers     "$adapter"/src/{adapter,private,utility}/*.m     -o "$framework/Versions/A/MediaRemoteAdapter"
codesign --force --sign - "$framework"

xcrun --sdk macosx swiftc -swift-version 5 -O -whole-module-optimization     -target "$arch-apple-macosx14.0" -sdk "$sdk" -module-cache-path "$build_dir/module-cache"     -framework AppKit -framework SwiftUI -framework CoreAudio     -framework IOKit -framework IOBluetooth -framework AudioToolbox -framework Intents     "$project_dir"/Sources/*.swift -o "$app/Contents/MacOS/Notchline"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

if [[ -e "$build_dir/Notchline.app" ]]; then
    mv "$build_dir/Notchline.app" "$staging/Previous.app"
fi
mv "$app" "$build_dir/Notchline.app"
printf '%s\n' "$build_dir/Notchline.app"
