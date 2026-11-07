# DeskStat 0.3.5

A native macOS desktop monitor with independent text widgets, terminal-style meters, and a monochrome monitor icon in the menu bar. Requires macOS 13 or later. This build is for Apple silicon.

## What’s new in 0.3.5

- Battery & Power shows charge, power source, and estimated time remaining when available.
- Network Activity shows upload and download rates with sparklines.
- Now Playing shows track, artist, and progress from Apple Music. macOS may request Automation permission.
- The in-app settings editor validates edits and saves them to the same config file. The config comments list supported settings, ranges, and theme colors.

[Download v0.3.5 and view the release notes](https://github.com/Grrck-Git/deskstat/releases/tag/v0.3.5)

## Start and upgrade

Quit the previous DeskStat, then open DeskStat.app. Existing settings continue to work and gain a ChatGPT input widget. To enable the full layout, choose **Use New Widget Layout…** from the DeskStat menu. The app saves your existing settings in a uniquely named backup before replacing them.

The full layout contains system metrics, weather, an example market watchlist, ChatGPT input, Fastfetch, a four-zone world clock, Battery & Power, Network Activity, and Now Playing. The reset layout uses your saved positions and sizes from this version. The Fastfetch widget is enabled in the default layout. The shared weather default is Washington DC. Set your preferred location and market symbols with **Open Settings**, then choose **Save & Apply**.

**Open Settings** opens a plain-text editor inside DeskStat. **Save & Apply** validates the settings, writes the same config file, and refreshes the widgets. **Edit Config File…** opens the file in your external editor. After external edits, choose **Reload Settings** to refresh the widgets, or **Reload From File** in the panel to refresh the editor.

Settings live at `~/Library/Application Support/DeskStat/deskstat.conf`. An invalid file produces an error and leaves the active layout running. **Open Widget Guide** opens this guide.

## Configuration format

The config is an INI-style text file. Each `[widget.name]` section creates an independently placed widget. Names must be unique. Use simple text, quoted strings, comma-separated lists, or JSON arrays of quoted strings as shown in the bundled deskstat.conf. Use `#` for comments. A `#` inside a quoted string is preserved. This is a small configuration format, rather than a full TOML parser.

All widgets accept these settings.

| Setting | Meaning |
| --- | --- |
| `type` | `metrics`, `command`, `weather`, `markets`, `clock`, `chatgpt`, `battery`, `network`, or `now_playing` |
| `enabled` | `true` or `false`, default true |
| `left`, `top` | Offset in points from the primary display's usable top-left corner |
| `width`, `height` | Fixed widget size in points |
| `font_size` | Monospace font size, 10–32 points |
| `refresh_seconds` | Independent refresh interval, 1–86400 seconds |

The usable desktop excludes the menu bar and Dock. Widgets are clamped to fit the primary display. Fixed-size output is clipped if it exceeds the widget bounds, so increase width or height for longer content. Monitoring widgets allow clicks through to the desktop. The ChatGPT widget accepts clicks and typing. Widgets stay on the desktop Space where they are created and sit below normal application windows. The ChatGPT panel sits above desktop icons to accept clicks. Restart DeskStat on the desktop where you want the widgets.

Legacy single-widget settings remain supported. `right` is accepted as the older spelling of `left`. Existing files keep their offsets and metrics. The extra ChatGPT input appears below the original panel until you adopt a sectioned layout.

### System metrics

```ini
[widget.system]
type = metrics
left = 24
top = 24
width = 360
height = 150
refresh_seconds = 2
modules = cpu, memory, disk, uptime
```

Choose any order of `cpu`, `memory`, `disk`, and `uptime`. CPU samples aggregate tick deltas. RAM is an estimate based on internal, wired, compressed, and purgeable pages. Disk reports free space on the filesystem containing your home folder.

### Command output

```ini
[widget.machine]
type = command
left = 395
top = 194
width = 620
height = 200
command = fastfetch
arguments = []
refresh_seconds = 300
timeout_seconds = 10
```

Install the command separately. Commands are looked up in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and `/bin`, or use an absolute executable path. Arguments are passed directly to the executable. For a custom script, use its absolute path and an executable script with a shebang. Shell aliases, pipes, and shell substitutions are not interpreted in `command`.

Commands run asynchronously with a minimum five-second refresh, no overlapping runs per widget, a timeout of 1–60 seconds, and a 1 MB output limit. Reloading settings or quitting cancels a running command. Use commands that finish on their own. Output preserves spacing and interprets ANSI sequences. The global theme sets all widget text and logo colors, overriding foreground colors from commands. Interactive terminal applications require a terminal and are outside this widget's scope.

### Weather

```ini
[widget.weather]
type = weather
left = 24
top = 190
width = 360
height = 180
zip = "20001"
country = US
units = fahrenheit
refresh_seconds = 900
```

The example ZIP selects Washington DC. Replace it with your preferred ZIP/postal code. Keep it quoted to preserve leading zeros. `country` is a two-letter country code. `units` accepts `fahrenheit` or `celsius`. An empty ZIP shows a setup message and makes no request. The panel shows the resolved place so you can check the lookup.

Weather refreshes at most once every 15 minutes and shows current temperature and conditions, today's high/low, precipitation chance, and the source time in the location's timezone. It sends the configured postal code to Open-Meteo's geocoder, then requests weather for the returned coordinates. Location Services are a future addition.

Weather is supplied by [Open-Meteo](https://open-meteo.com/) under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The public endpoint is for non-commercial use. See the [forecast documentation](https://open-meteo.com/en/docs) and [geocoding documentation](https://open-meteo.com/en/docs/geocoding-api).

### Market watchlist

```ini
[widget.markets]
type = markets
left = 24
top = 566
width = 360
height = 220
symbols = ["^GSPC", "VTI"]
labels = ["S&P 500", "Total US market"]
refresh_seconds = 300
```

Use Yahoo Finance symbols for up to 12 items. `^GSPC` is the S&P 500 index. ETFs such as VTI and VOO and mutual fund symbols can also be requested. Labels match symbols by position and are optional. These are example watchlist entries, not a personalized selection.

The panel shows the latest regular-session quote or published NAV, currency, daily percentage change when available, and each quote's timestamp in your Mac's local timezone. Quotes may be delayed. Refreshes run at most once every five minutes. An unsupported symbol is marked unavailable and does not prevent other symbols from updating.

The prototype uses Yahoo Finance's unofficial chart endpoint with no API key. Service availability, symbol coverage, and response format can change. Weather and market widgets cache their last successful output under `~/Library/Caches/DeskStat`. Cached/stale readings and update failures are labeled. The quote timestamp is separate from the retrieval time.

### ChatGPT input

```ini
[widget.chatgpt]
type = chatgpt
left = 24
top = 390
width = 360
height = 160
```

Click the field, type a question, and click **Copy & Open ChatGPT** or press Return. DeskStat replaces the clipboard with your question and opens the current ChatGPT app at `/Applications/ChatGPT.app` (bundle identifier `com.openai.codex`), falling back to `https://chatgpt.com/`. Paste and send there. Your question remains in the field. This widget uses no API key, local server, API billing, or background service. Responses appear in ChatGPT.

## Global widget appearance

Add a theme section anywhere outside a widget section, then save and choose **Reload Settings**.

```ini
[theme]
text_color = green
background_color = charcoal
background_opacity = 0.75
corner_radius = 25
```

Named colors are `mint`, `white`, `black`, `green`, `cyan`, `blue`, `yellow`, `amber`, `orange`, `red`, `pink`, `purple`, and `gray` (`grey` also works), `charcoal`, `darkgray`, and `navy`. Names are case-insensitive. Use a quoted six-digit RGB hex code for an exact color.

```ini
[theme]
text_color = "#FFD600"
```

The color applies to all widget headings, content, command output, and ChatGPT input/button/status text. It also overrides ANSI foreground colors from commands such as Fastfetch. The menu-bar icon uses the system's monochrome appearance. Invalid colors leave the active layout in place and report an error. Old configs without a theme use mint.

The background settings apply to every widget, including the clock and ChatGPT panel. `background_color` accepts the same named colors or quoted six-digit hex codes as `text_color`.

| Setting | Values |
| --- | --- |
| `background_color` | Named color or a quoted hex value such as `"#182033"` |
| `background_opacity` | `0` for a fully transparent block through `1` for a solid block |
| `corner_radius` | Radius in points, from `0` for square corners to `2000` for maximum rounding |

Corner radii are capped at half the smaller widget dimension so large values produce rounded ends. Background opacity affects the surrounding block while text remains fully visible. ChatGPT's native input field and button retain their control surfaces. Old configs default to charcoal, 0.88 opacity, and an 8-point corner radius. Save and choose **Reload Settings** to apply changes.

### Work clock

```ini
[widget.clock]
type = clock
left = 395
top = 24
width = 620
height = 150
refresh_seconds = 1
time_zones = ["America/Los_Angeles", "America/Chicago", "America/New_York", "GMT"]
cities = ["San Francisco", "Austin, TX", "Washington, DC", "GMT"]
time_format = 24h
clock_style = cards
```

The default order is west to east. The `cards` style shows four columns with large digital times, uppercase city labels, smaller zone/date lines, and fine dividers. It fits the default 620 × 150 panel and follows the global color and background theme. Wider zone lists wrap into a grid. Small panels automatically use a compact text layout when cards would not fit. Use `clock_style = text` for the original text rows. Each location includes its time-zone abbreviation, weekday, and date. The US cities follow daylight saving time automatically, while GMT remains fixed. Dates are calculated for each location so a next-day GMT reading is clear. The clock uses your Mac's system clock and time-zone database and requires no network access.

Use `12h` or `24h` for `time_format`. Edit the cities and time_zones lists together to choose 1–8 locations. Time zones use standard identifiers, such as `America/Chicago`. Invalid identifiers or mismatched lists report an error before applying the new layout.

## Build and diagnostics

Install Apple's Command Line Tools, then run these commands from this folder.

```sh
./build.sh
open DeskStat.app
```

The build script stages and signs a fresh application before replacing the generated DeskStat.app. It includes the config, app icon, and this guide. It does not change your active settings.

### Local and shared reset defaults

The tracked deskstat.conf contains the shared reset layout, with green text, 0.75 background opacity, 25-point corners, the clock above Fastfetch, and Washington DC weather.

For a personal reset layout, place a deskstat.local.conf beside build.sh. This file is ignored by Git. When present, the build script bundles it as the application's reset configuration. Otherwise the script uses deskstat.conf. Both **Use New Widget Layout…** and first-launch settings creation use the configuration bundled in that build.

GitHub release packages are built from the committed source archive, which contains the shared configuration. The local build can use its personal reset defaults independently.

```sh
./DeskStat.app/Contents/MacOS/DeskStat --check-config deskstat.conf
./DeskStat.app/Contents/MacOS/DeskStat --sample deskstat.conf
```

`--check-config` validates the layout without opening windows or running commands. `--sample` also prints live system metrics and clock rows.

Each metric implements the `Metric` protocol and is registered in `metricFactories`. The widget controller owns one desktop panel, refresh timer, and asynchronous job per widget. Network providers and command execution are separated from display and config parsing.

## Activity widgets

Use `type = battery` for charge, power source, and the Mac's estimated time remaining. Use `type = network` for aggregate upload and download rates on active Ethernet and Wi-Fi interfaces. Each sparkline shows the last 16 samples, scaled to its own peak.

Use `type = now_playing` for track, artist, and playback progress in Apple Music. Open Music to see playback, and allow DeskStat to read Music if macOS prompts for Automation access.
