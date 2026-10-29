#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-harem-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/codex-harem-swift-cache"
swift build -c release --disable-sandbox -debug-info-format none
app="dist/Codex Harem.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/codex-harem "$app/Contents/MacOS/codex-harem"
./scripts/build-icon.sh
cp .build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Optional local artwork copies, imported explicitly before packaging.
# Recreate only our own generated seed directory; avoid carrying obsolete assets.
if test -d "$app/Contents/Resources/Pets"; then
    rm -r "$app/Contents/Resources/Pets"
fi
if test -d pets; then
    mkdir -p "$app/Contents/Resources"
    ditto pets "$app/Contents/Resources/Pets"
fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>codex-harem</string>
<key>CFBundleIdentifier</key><string>dev.codex-harem.companion</string>
<key>CFBundleName</key><string>Codex Harem</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" 'dist/Codex-Harem-macOS.zip'
printf 'Built %s\n' "$app"
