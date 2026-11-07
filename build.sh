#!/bin/sh
set -eu
cd "$(dirname "$0")"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
app="$staging/DeskStat.app"
config=deskstat.conf
if [ -f deskstat.local.conf ]; then
    config=deskstat.local.conf
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
MACOSX_DEPLOYMENT_TARGET=13.0 swiftc -module-cache-path "${TMPDIR:-/tmp}/deskstat-swift-cache" -O main.swift Settings.swift Clock.swift Metrics.swift Providers.swift DeskStat.swift -o "$app/Contents/MacOS/DeskStat"
cp Assets/AppIcon.icns "$app/Contents/Resources/"
cp README.md "$app/Contents/Resources/"
cp "$config" "$app/Contents/Resources/deskstat.conf"
cp Info.plist "$app/Contents/"

xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --norsrc --noextattr --keepParent "$app" DeskStat.zip
rm -rf DeskStat.app

ditto --noextattr "$app" DeskStat.app
xattr -dr com.apple.FinderInfo DeskStat.app 2>/dev/null || true
