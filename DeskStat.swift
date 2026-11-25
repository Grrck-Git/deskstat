import AppKit
import CryptoKit

@MainActor
final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct CachedReading: Codable {
    let text: String
    let date: Date
    var quotes: [String: String]?
}

@MainActor
final class WidgetController: NSObject {
    let settings: WidgetSettings
    private let panel: DesktopPanel
    private let text = NSTextView()
    private let scroll = NSScrollView()
    private let tint: NSColor
    private let clock: WorkClock?
    private let clockView: StyledClockView?
    private let styledView: StyledWidgetView?
    private let cornerRadius: CGFloat
    private var metrics: [any Metric] = []
    private var network = NetworkActivity()
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var reading: CachedReading?
    private var location: WeatherLocation?
    private var quotes: [String: String] = [:]
    private var stopped = false
    private var cacheURL: URL {
        let identity = [settings.type, settings.zip, settings.country, settings.units,
                        settings.symbols.joined(separator: ","), settings.labels.joined(separator: ",")].joined(separator: "|")
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/DeskStat/\(key).json")
    }

    init(_ settings: WidgetSettings, textColor: ThemeColor = .mint,
         backgroundColor: ThemeColor = ThemeColor(rgb: 0x121212),
         backgroundOpacity: Double = 0.88, cornerRadius: Double = 8) {
        self.settings = settings
        self.cornerRadius = CGFloat(cornerRadius)
        tint = NSColor(srgbRed: CGFloat((textColor.rgb >> 16) & 255) / 255,
                       green: CGFloat((textColor.rgb >> 8) & 255) / 255,
                       blue: CGFloat(textColor.rgb & 255) / 255, alpha: 1)
        clock = settings.type == "clock" ? WorkClock(settings) : nil
        clockView = settings.type == "clock" && settings.clockStyle == "cards"
            ? StyledClockView(settings: settings, tint: tint) : nil
        styledView = ["metrics", "weather", "markets", "battery", "network", "now_playing"].contains(settings.type)
            ? StyledWidgetView(settings: settings, tint: tint) : nil
        panel = DesktopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()
        panel.becomesKeyOnlyIfNeeded = false
        // Changing the floating flag resets NSPanel.level. Assign the desktop level last.
        panel.isFloatingPanel = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        panel.collectionBehavior = [.managed, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(
            srgbRed: CGFloat((backgroundColor.rgb >> 16) & 255) / 255,
            green: CGFloat((backgroundColor.rgb >> 8) & 255) / 255,
            blue: CGFloat(backgroundColor.rgb & 255) / 255,
            alpha: CGFloat(backgroundOpacity)).cgColor
        background.layer?.masksToBounds = true
        panel.contentView = background
        if let clockView {
            background.addSubview(clockView)
        } else if let styledView {
            background.addSubview(styledView)
        } else {
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            text.isEditable = false
            text.isSelectable = false
            text.drawsBackground = false
            text.font = .monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
            text.textColor = tint
            text.textContainerInset = .zero
            text.textContainer?.lineFragmentPadding = 0
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = true
            text.textContainer?.widthTracksTextView = false
            text.textContainer?.containerSize = NSSize(width: 10000, height: CGFloat.greatestFiniteMagnitude)
            scroll.documentView = text
            background.addSubview(scroll)
        }
        metrics = settings.modules.compactMap { metricFactories[$0]?() }
        if ["weather", "markets"].contains(settings.type),
           let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(CachedReading.self, from: data) {
            reading = cached
            quotes = cached.quotes ?? [:]
            display(cached.text + "\nCached · " + stamp(cached.date) + " · refreshing…")
        }
        reposition()
        refresh()
        let minimum: Double
        switch settings.type {
        case "weather": minimum = 900
        case "markets": minimum = 300
        case "command": minimum = 5
        case "now_playing": minimum = 3
        default: minimum = 1
        }
        let interval = max(minimum, settings.interval)
        let next = Timer(timeInterval: interval, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        next.tolerance = interval * 0.1
        RunLoop.main.add(next, forMode: .common)
        timer = next
        panel.orderFrontRegardless()
    }

    func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let width = min(settings.width, area.width)
        let height = min(settings.height, area.height)
        panel.contentView?.layer?.cornerRadius = min(cornerRadius, min(width, height) / 2)
        let x = min(area.minX + settings.left, area.maxX - width)
        let y = max(area.minY, area.maxY - height - settings.top)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if let clockView {
            clockView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        } else if let styledView {
            styledView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        } else {
            scroll.frame = NSRect(x: 14, y: 12, width: width - 28, height: height - 24)
            text.setFrameSize(NSSize(width: max(10000, width - 28), height: max(height - 24, text.frame.height)))
        }
    }

    private func display(_ body: String) {
        if let styledView { styledView.update(body); return }
        let heading = settings.type == "metrics" ? "DESKSTAT" : settings.id.uppercased()
        let rendered = NSMutableAttributedString(attributedString: ansiText(heading + "\n" + body, font: .monospacedSystemFont(ofSize: settings.fontSize, weight: .regular), color: tint))
        // Apply the global theme after interpreting ANSI so command colors follow it too.
        rendered.addAttribute(.foregroundColor, value: tint, range: NSRange(location: 0, length: rendered.length))
        rendered.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                                .foregroundColor: tint.withAlphaComponent(0.65)],
                               range: NSRange(location: 0, length: (heading as NSString).length))
        if let footer = rendered.string.range(of: "\nFetched ", options: .backwards) {
            let range = NSRange(footer.lowerBound..<rendered.string.endIndex, in: rendered.string)
            rendered.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                                    .foregroundColor: tint.withAlphaComponent(0.5)], range: range)
        }
        text.textStorage?.setAttributedString(rendered)
        text.scrollToBeginningOfDocument(nil)
    }

    private func stamp(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    private func save(_ body: String) {
        let next = CachedReading(text: body, date: Date(), quotes: settings.type == "markets" ? quotes : nil)
        reading = next
        display(body + "\nFetched " + stamp(next.date))
        guard ["weather", "markets"].contains(settings.type) else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: cacheURL, options: .atomic)
        } catch { /* Cache failure does not prevent live updates. */ }
    }

    @objc private func refresh() {
        guard !stopped, task == nil else { return }
        switch settings.type {
        case "battery":
            display(batteryText())
            return
        case "network":
            display(network.sample())
            return
        case "clock":
            if let clockView { clockView.update(clock!.readings()) }
            else { display(clock!.sample()) }
            return
        case "metrics":
            display(metrics.indices.map { metrics[$0].sample() }.joined(separator: "\n"))
            return
        case "weather" where settings.zip.isEmpty:
            display("Set zip in this widget's settings.\nChoose Open Settings in the menu bar.\nWeather by Open-Meteo")
            return
        default: break
        }
        if reading == nil { display("Loading…") }
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                let body: String
                switch settings.type {
                case "command": body = try await commandText(settings)
                case "now_playing": body = try await nowPlayingText(settings)
                case "weather":
                    if location == nil { location = try await weatherLocation(settings) }
                    body = try await weatherText(settings, location: location!)
                case "markets": body = try await fetchMarkets()
                default: return
                }
                try Task.checkCancellation()
                guard !stopped else { return }
                if settings.type == "now_playing" {
                    reading = CachedReading(text: body, date: Date())
                    display(body)
                } else {
                    save(body)
                }
            } catch {
                guard !Task.isCancelled, !stopped else { return }
                if settings.type == "now_playing" {
                    reading = nil
                    display("Now Playing unavailable.\n" + error.localizedDescription)
                    return
                }
                let previous = reading.map { $0.text + "\nLast success " + self.stamp($0.date) + "\n" } ?? ""
                display(previous + "Update failed · " + error.localizedDescription)
            }
        }
    }

    private func fetchMarkets() async throws -> String {
        var rows: [String] = []
        var successes = 0
        for (index, symbol) in settings.symbols.enumerated() {
            try Task.checkCancellation()
            let label = index < settings.labels.count ? settings.labels[index] : symbol
            do {
                let quote = try await marketText(symbol: symbol, label: label)
                quotes[symbol] = quote
                rows.append(quote)
                successes += 1
            } catch {
                let prior = quotes[symbol].map { $0 + "\nStale · update failed" }
                rows.append(prior ?? "\(label) [\(symbol)]\nUnavailable · check symbol or connection")
            }
        }
        guard successes > 0 else { throw ConfigError(message: "No quotes returned. Will retry; check symbols or connection.") }
        return rows.joined(separator: "\n\n") + "\nYahoo Finance · quotes may be delayed"
    }

    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
        task?.cancel()
        panel.orderOut(nil)
    }
}

@MainActor
final class DeskStat: NSObject, NSApplicationDelegate {
    private let config = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DeskStat/deskstat.conf")
    private var widgets: [WidgetController] = []
    private var item: NSStatusItem?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item?.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "DeskStat"
            button.setAccessibilityLabel("DeskStat")
        }
        let menu = NSMenu()
        for (title, action) in [("Open Settings", #selector(openSettings)),
                                ("Edit Config File…", #selector(editConfigFile)),
                                ("Reload Settings", #selector(reload)),
                                ("Use New Widget Layout…", #selector(useExample)),
                                ("Open Widget Guide", #selector(openGuide)),
                                ("Quit DeskStat", #selector(quit))] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            entry.target = self
        }
        item?.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        reload()
    }

    private static func menuBarIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let screen = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4.5, width: 15, height: 12),
                                      xRadius: 2, yRadius: 2)
            screen.lineWidth = 1
            screen.stroke()
            let blocks = [NSRect(x: 3.5, y: 11.5, width: 4, height: 2.5),
                          NSRect(x: 3.5, y: 7, width: 4, height: 2.5),
                          NSRect(x: 9.5, y: 7, width: 4.5, height: 7)]
            for rect in blocks {
                let block = NSBezierPath(roundedRect: rect, xRadius: 0.5, yRadius: 0.5)
                block.lineWidth = 1
                block.stroke()
            }
            let stand = NSBezierPath()
            stand.lineWidth = 1
            stand.lineCapStyle = .round
            stand.move(to: NSPoint(x: 8.5, y: 4.5))
            stand.line(to: NSPoint(x: 8.5, y: 1.5))
            stand.move(to: NSPoint(x: 4.5, y: 1.5))
            stand.line(to: NSPoint(x: 12.5, y: 1.5))
            stand.stroke()
            return true
        }
        icon.isTemplate = true
        return icon
    }

    private func ensureConfig() throws {
        guard !FileManager.default.fileExists(atPath: config.path) else { return }
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try example().write(to: config, atomically: true, encoding: .utf8)
    }

    private func example() throws -> String {
        guard let url = Bundle.main.url(forResource: "deskstat", withExtension: "conf") else { throw CocoaError(.fileNoSuchFile) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @objc private func reload() {
        do {
            try ensureConfig()
            let source = try String(contentsOf: config, encoding: .utf8)
            apply(try Settings(source))
        } catch { show(error) }
    }

    private func apply(_ next: Settings) {
        let enabled = next.widgets.filter(\.enabled)
        for widget in widgets { widget.stop() }
        widgets = enabled.map {
            WidgetController($0, textColor: next.textColor, backgroundColor: next.backgroundColor,
                             backgroundOpacity: next.backgroundOpacity, cornerRadius: next.cornerRadius)
        }
    }

    @objc private func useExample() {
        let alert = NSAlert()
        alert.messageText = "Use the default widget layout?"
        alert.informativeText = "This restores the saved default positions and sizes for the system, weather, market, Fastfetch, clock, battery, network, and Now Playing widgets, along with the global colors, background opacity, and corner radius. Your current settings will be saved beside the settings file as a backup. Weather uses the saved default location. The market symbols are examples."
        alert.addButton(withTitle: "Use Layout")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let source = try example()
            _ = try Settings(source)
            if FileManager.default.fileExists(atPath: config.path) {
                let backup = config.deletingLastPathComponent().appendingPathComponent("deskstat-backup-\(UUID().uuidString).conf")
                try FileManager.default.copyItem(at: config, to: backup)
            }
            try source.write(to: config, atomically: true, encoding: .utf8)
            reload()
        } catch { show(error) }
    }

    @objc private func openSettings() {
        do {
            try ensureConfig()
            let source = try String(contentsOf: config, encoding: .utf8)
            if settingsWindow == nil {
                settingsWindow = SettingsWindow(config: config, source: source) { [weak self] next in
                    self?.apply(next)
                }
            }
            settingsWindow?.show(source: source)
        } catch { show(error) }
    }

    @objc private func editConfigFile() {
        do {
            try ensureConfig()
            if let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                NSWorkspace.shared.open([config], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
            } else { NSWorkspace.shared.open(config) }
        } catch { show(error) }
    }

    @objc private func openGuide() {
        if let url = Bundle.main.url(forResource: "README", withExtension: "md") { NSWorkspace.shared.open(url) }
    }

    @objc private func reposition() { widgets.forEach { $0.reposition() } }
    private func show(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { widgets.forEach { $0.stop() } }
}
