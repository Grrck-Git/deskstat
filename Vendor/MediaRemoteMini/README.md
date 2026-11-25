# MediaRemote Mini

BSD-3-Clause subset of Jonas van den Berg's mediaremote-adapter:
https://github.com/ungive/mediaremote-adapter

Imported from the BSD-licensed src/mediaremote-mini directory of:
https://github.com/kirtan-shah/nowplaying-cli
Commit: 8c8c1fa4820681fd4bbd6a17ce0a5655e1f4ebe7

Only this BSD subset is included; the GPL nowplaying-cli executable and source are not bundled.
See LICENSE and the original file notices. Private framework use may require changes after macOS updates.

DeskStat changes: filter output to the title, artist, app identifiers, playing state and timing fields used by the widget. Artwork is not serialized. Fail cleanly if the framework cannot initialize. The read-only adapter is loaded for each query by /usr/bin/perl using Helpers/read-now-playing.pl; it does not install a service.
