# DeskStat 0.3.4 build snapshot

This version includes the custom app icon and the updated six-widget reset layout. The clock sits above Fastfetch. The shared theme uses green text, charcoal blocks at 0.75 opacity, and 25-point corners.

The shared weather default is Washington DC, configured with ZIP 20001. Personal reset settings can be supplied locally through the Git-ignored deskstat.local.conf file.

## Restore or build

Download and extract the Apple silicon application from the v0.3.4 GitHub release, or build from source using ./build.sh. Installation, configuration, and widget instructions are in README.md.

The release application uses the shared reset layout. A local source build uses deskstat.local.conf when that file exists. Both builds read the user's active settings from ~/Library/Application Support/DeskStat/deskstat.conf.

## Build contents

- CPU, memory, disk, and uptime metrics
- Washington DC weather and example market watchlist
- Periodic command output with Fastfetch support
- ChatGPT copy-and-open input
- Styled world clock for San Francisco, Austin, Washington DC, and GMT
- Global text and block colors, opacity, and corner radius
- Matching monochrome menu-bar and charcoal app icons
- Single-desktop placement below normal application windows

The release includes application and source archives with a SHA256SUMS file for verification.
