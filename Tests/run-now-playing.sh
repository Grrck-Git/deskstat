#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
swiftc Settings.swift Metrics.swift Providers.swift Activity.swift Tests/NowPlaying/main.swift -o "$staging/check"
"$staging/check"
