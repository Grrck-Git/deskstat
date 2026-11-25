# DeskStat 0.3.7 build snapshot

Local visual refresh: consistent headings, thin meters, prominent weather temperature, aligned market quotes and quiet status text. The eight-widget reset layout uses 20-point gaps, green text, charcoal blocks at 50% opacity and 14-point corners.

The shared weather default is Washington DC (ZIP 20001). Git-ignored deskstat.local.conf supplies the personal reset layout when building locally. Both builds read active settings from ~/Library/Application Support/DeskStat/deskstat.conf.

Build with ./build.sh. README.md describes installation and configuration. The published release link in README.md continues to point to the latest published release, v0.3.5.

## Rollback

The local tag rollback/pre-visual-refresh-0.3.6 preserves source commit 7c26d73 before this refresh. A separate private DeskStat-rollback-0.3.6.zip archive preserves the previous application, source and personal active/reset configuration, with restoration instructions. Keep the archive local because it contains personal configuration.

## Validation

Compiled on macOS; packaged application signature verified. Shared and personal configurations validated. Native production views rendered at configured sizes. Compatibility and desktop panel checks cover old configuration files, click-through behavior, inability to take focus, negative window level and single-Space placement.
