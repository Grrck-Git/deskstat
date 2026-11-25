import AppKit

/// Presentation of the same provider output used by the text interface and disk cache.
/// Unrecognized and error lines remain visible rather than being discarded.
@MainActor
final class StyledWidgetView: NSView {
    let settings: WidgetSettings
    let tint: NSColor
    private var body = ""
    override var isFlipped: Bool { true }

    init(settings: WidgetSettings, tint: NSColor) {
        self.settings = settings
        self.tint = tint
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ body: String) { self.body = body; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let width = max(0, bounds.width - 36)
        let base = CGFloat(settings.fontSize)
        func label(_ value: String, _ y: CGFloat, size: CGFloat, alpha: CGFloat = 1,
                   weight: NSFont.Weight = .regular, x: CGFloat = 18, w: CGFloat? = nil,
                   alignment: NSTextAlignment = .left) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = alignment
            (value as NSString).draw(in: NSRect(x: x, y: y, width: w ?? width, height: size + 7), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
                .foregroundColor: tint.withAlphaComponent(alpha), .paragraphStyle: paragraph
            ])
        }
        let title: String
        switch settings.type {
        case "metrics": title = "SYSTEM"
        case "now_playing": title = "NOW PLAYING"
        default: title = settings.id.replacingOccurrences(of: "-", with: " ").uppercased()
        }
        label(title, 14, size: 10, alpha: 0.65, weight: .semibold)
        let lines = body.components(separatedBy: "\n")
        func quiet(_ line: String) -> Bool {
            ["Fetched ", "Cached ·", "Last success ", "Quote ", "As of ", "Weather by ", "Yahoo Finance"].contains { line.hasPrefix($0) }
        }
        func meter(_ line: String, y: CGFloat) -> Bool {
            guard line.contains("█") || line.contains("░"),
                  let end = line.range(of: #"[0-9]+(?:\.[0-9]+)?%"#, options: .regularExpression),
                  let percent = Double(line[end].dropLast()) else { return false }
            let caption = line.prefix { $0 != "█" && $0 != "░" }.trimmingCharacters(in: .whitespaces)
            label(caption, y, size: base, alpha: 0.8)
            label(String(line[end]), y, size: base, weight: .medium, alignment: .right)
            let track = NSRect(x: 18, y: y + base + 5, width: width, height: 3)
            tint.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
            tint.withAlphaComponent(0.85).setFill()
            var fill = track
            fill.size.width *= CGFloat(min(1, max(0, percent / 100)))
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        var y: CGFloat = 36
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.isEmpty { i += 1; continue }
            let subdued = quiet(line)
            if settings.type == "weather", i == 1,
               let split = line.range(of: "  "), line.contains("°") {
                label(String(line[..<split.lowerBound]), y, size: min(30, base * 2.3), weight: .medium)
                y += min(30, base * 2.3) + 6
                label(String(line[split.upperBound...]), y, size: base, alpha: 0.85)
                y += base + 9
            } else if settings.type == "markets", line.hasSuffix("]"), line.contains(" ["),
                      i + 1 < lines.count, let split = line.range(of: " [", options: .backwards) {
                let symbol = String(line[split.upperBound...].dropLast())
                let name = String(line[..<split.lowerBound])
                label(symbol, y, size: base + 1, weight: .semibold, w: min(100, width * 0.35))
                let values = lines[i + 1].split(separator: " ").map(String.init)
                if values.count >= 3, Double(values[0]) != nil {
                    label(values[0] + " " + values[1], y, size: base + 1, weight: .medium,
                          x: 18 + width * 0.35, w: width * 0.65, alignment: .right)
                    y += base + 7
                    label(name, y, size: max(10, base - 2), alpha: 0.6, w: width * 0.65)
                    label(values.dropFirst(2).joined(separator: " "), y, size: max(10, base - 2), alpha: 0.85,
                          x: 18 + width * 0.65, w: width * 0.35, alignment: .right)
                    y += base + 10
                    i += 1
                } else {
                    y += base + 6
                    label(name, y, size: max(10, base - 2), alpha: 0.6)
                    y += base + 6
                }
            } else if meter(line, y: y) {
                y += base + 15
            } else {
                let idle = settings.type == "now_playing" && (line.hasPrefix("Open Apple") || line.hasPrefix("Nothing playing"))
                let size = subdued ? max(9, base - 3) : (settings.type == "now_playing" && i == 0 && !idle ? base + 4 : base)
                label(line, y, size: size, alpha: subdued || idle ? 0.5 : 0.9,
                      weight: settings.type == "now_playing" && i == 0 && !idle ? .medium : .regular)
                y += size + (subdued ? 4 : 7)
            }
            i += 1
        }
    }
}
