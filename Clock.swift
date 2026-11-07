import AppKit

struct ClockReading: Equatable {
    let city: String
    let time: String
    let zone: String
    let date: String
}

struct WorkClock {
    private struct ZoneClock {
        let city: String
        let time: DateFormatter
        let zone: DateFormatter
        let date: DateFormatter
    }
    private let zones: [ZoneClock]

    init(_ settings: WidgetSettings) {
        func formatter(_ identifier: String, pattern: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: identifier)!
            formatter.dateFormat = pattern
            return formatter
        }
        zones = zip(settings.cities, settings.timeZones).map { city, identifier in
            ZoneClock(city: city,
                      time: formatter(identifier, pattern: settings.timeFormat == "12h" ? "h:mm a" : "HH:mm"),
                      zone: formatter(identifier, pattern: "z"),
                      date: formatter(identifier, pattern: "EEE d MMM"))
        }
    }

    func readings(at date: Date = Date()) -> [ClockReading] {
        zones.map { zone in
            ClockReading(city: zone.city, time: zone.time.string(from: date),
                         zone: zone.zone.string(from: date), date: zone.date.string(from: date))
        }
    }

    func sample(at date: Date = Date()) -> String {
        let width = zones.map { $0.city.count }.max() ?? 0
        return readings(at: date).map { reading in
            reading.city.padding(toLength: width, withPad: " ", startingAt: 0)
                + "  \(reading.time) \(reading.zone)  \(reading.date)"
        }.joined(separator: "\n")
    }
}

@MainActor
final class StyledClockView: NSView {
    @MainActor
    private struct ClockLabels {
        let city = NSTextField(labelWithString: "")
        let time = NSTextField(labelWithString: "")
        let detail = NSTextField(labelWithString: "")
    }
    private let heading = NSTextField(labelWithString: "WORLD CLOCK")
    private let direction = NSTextField(labelWithString: "WEST → EAST")
    private let compact = NSTextField(labelWithString: "")
    private let labels: [ClockLabels]
    private let tint: NSColor
    private let baseFontSize: CGFloat
    private var readings: [ClockReading] = []
    private var columns = 1
    private var rows = 1
    private var compactLayout = false

    init(settings: WidgetSettings, tint: NSColor) {
        self.tint = tint
        baseFontSize = CGFloat(settings.fontSize)
        labels = settings.cities.map { _ in ClockLabels() }
        super.init(frame: .zero)
        heading.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        heading.textColor = tint
        direction.stringValue = settings.timeZones == ["America/Los_Angeles", "America/Chicago", "America/New_York", "GMT"]
            ? "WEST → EAST" : settings.timeFormat.uppercased()
        direction.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        direction.textColor = tint.withAlphaComponent(0.6)
        direction.alignment = .right
        compact.font = .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
        compact.textColor = tint
        compact.maximumNumberOfLines = 0
        for field in [heading, direction, compact] { addSubview(field) }
        for group in labels {
            for field in [group.city, group.time, group.detail] {
                field.textColor = tint
                field.maximumNumberOfLines = 1
                field.lineBreakMode = .byTruncatingTail
                addSubview(field)
            }
            group.city.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            group.detail.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
            group.detail.textColor = tint.withAlphaComponent(0.7)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ next: [ClockReading]) {
        guard next != readings else { return }
        readings = next
        for (group, reading) in zip(labels, next) {
            group.city.stringValue = reading.city.uppercased()
            group.time.stringValue = reading.time
            group.detail.stringValue = "\(reading.zone) · \(reading.date.uppercased())"
            group.time.setAccessibilityLabel("\(reading.city), \(reading.time) \(reading.zone), \(reading.date)")
            group.city.toolTip = reading.city
        }
        compact.stringValue = next.map { "\($0.city)  \($0.time) \($0.zone)  \($0.date)" }.joined(separator: "\n")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(1, bounds.width - 36)
        let bodyHeight = max(1, bounds.height - 52)
        columns = min(labels.count, max(1, Int(width / 135)))
        rows = (labels.count + columns - 1) / columns
        let cellWidth = width / CGFloat(columns)
        let cellHeight = bodyHeight / CGFloat(rows)
        compactLayout = cellHeight < 64
        heading.frame = NSRect(x: 18, y: bounds.height - 30, width: width, height: 15)
        direction.frame = NSRect(x: bounds.width - 118, y: bounds.height - 29, width: 100, height: 14)
        // WEST → EAST describes the default one-row layout. Custom grids need no direction label.
        direction.isHidden = compactLayout || rows > 1 || width < 300
        compact.isHidden = !compactLayout
        compact.frame = NSRect(x: 18, y: 12, width: width, height: bodyHeight)
        let availableWidth = max(1, cellWidth - 16)
        let preferred = min(30, baseFontSize * 2.15)
        let font = NSFont.monospacedDigitSystemFont(ofSize: preferred, weight: .medium)
        let widestTime = labels.map {
            ($0.time.stringValue as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 1
        let timeSize = preferred * min(1, availableWidth / max(1, widestTime))
        for (index, group) in labels.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = 18 + CGFloat(column) * cellWidth + (column == 0 ? 0 : 12)
            let top = bounds.height - 44 - CGFloat(row) * cellHeight
            for field in [group.city, group.time, group.detail] { field.isHidden = compactLayout }
            group.city.frame = NSRect(x: x, y: top - 18, width: availableWidth, height: 15)
            group.time.font = .monospacedDigitSystemFont(ofSize: timeSize, weight: .medium)
            group.time.frame = NSRect(x: x - 1, y: top - 59, width: availableWidth + 1, height: 36)
            group.detail.frame = NSRect(x: x, y: top - 78, width: availableWidth, height: 14)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        tint.withAlphaComponent(0.2).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 0.5
        lines.move(to: NSPoint(x: 18, y: bounds.height - 38))
        lines.line(to: NSPoint(x: bounds.width - 18, y: bounds.height - 38))
        if !compactLayout {
            let width = max(1, bounds.width - 36)
            let bodyHeight = max(1, bounds.height - 52)
            let cellWidth = width / CGFloat(columns)
            for column in 1..<columns {
                let x = 18 + CGFloat(column) * cellWidth - 2
                lines.move(to: NSPoint(x: x, y: 18))
                lines.line(to: NSPoint(x: x, y: bounds.height - 49))
            }
            for row in 1..<rows {
                let y = bounds.height - 44 - CGFloat(row) * bodyHeight / CGFloat(rows)
                lines.move(to: NSPoint(x: 18, y: y))
                lines.line(to: NSPoint(x: bounds.width - 18, y: y))
            }
        }
        lines.stroke()
    }
}
