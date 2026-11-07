import Foundation

struct ConfigError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ThemeColor: Equatable {
    let rgb: UInt32
    static let mint = ThemeColor(rgb: 0xBAF5D1)
    static let named: [String: UInt32] = [
        "mint": mint.rgb, "white": 0xFFFFFF, "black": 0x000000,
        "green": 0x80E080, "cyan": 0x70DFFF, "blue": 0x80B0FF,
        "yellow": 0xFFD600, "amber": 0xFFBF00, "orange": 0xFFA060,
        "red": 0xFF8080, "pink": 0xFF9ECC, "purple": 0xC5A0FF,
        "gray": 0xB0B0B0, "grey": 0xB0B0B0,
        "charcoal": 0x121212, "darkgray": 0x303030, "navy": 0x142033
    ]

    init(rgb: UInt32) { self.rgb = rgb }

    init(_ value: String) throws {
        let name = value.lowercased()
        if let rgb = Self.named[name] {
            self.rgb = rgb
            return
        }
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : ""
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let rgb = UInt32(digits, radix: 16) else {
            throw ConfigError(message: "Use a named color or a quoted hex value such as \"#FFD600\".")
        }
        self.rgb = rgb
    }
}

struct WidgetSettings {
    var id: String
    var type = "metrics"
    var enabled = true
    var left = 24.0
    var top = 24.0
    var width = 360.0
    var height = 150.0
    var fontSize = 13.0
    var interval = 2.0
    var modules = ["cpu", "memory", "disk", "uptime"]
    var command = "fastfetch"
    var arguments: [String] = []
    var timeout = 10.0
    var zip = ""
    var country = "US"
    var units = "fahrenheit"
    var symbols = ["^GSPC", "VTI"]
    var labels = ["S&P 500", "Total US market"]
    var timeZones = ["America/Los_Angeles", "America/Chicago", "America/New_York", "GMT"]
    var cities = ["San Francisco", "Austin, TX", "Washington, DC", "GMT"]
    var timeFormat = "24h"
    var clockStyle = "cards"
}

struct Settings {
    var widgets: [WidgetSettings]
    var legacy: Bool
    var textColor = ThemeColor.mint
    var backgroundColor = ThemeColor(rgb: 0x121212)
    var backgroundOpacity = 0.88
    var cornerRadius = 8.0

    init(_ source: String) throws {
        var result: [WidgetSettings] = []
        var active: WidgetSettings?
        var inTheme = false
        let sectioned = source.components(separatedBy: .newlines).contains { $0.trimmed.hasPrefix("[widget.") }
        if !sectioned { active = WidgetSettings(id: "system") }
        for (lineNumber, raw) in source.components(separatedBy: .newlines).enumerated() {
            let line = stripComment(raw).trimmed
            guard !line.isEmpty else { continue }
            func invalid(_ reason: String) -> ConfigError {
                ConfigError(message: "Settings line \(lineNumber + 1): \(reason)")
            }
            if line == "[theme]" {
                if let widget = active { result.append(widget) }
                active = nil
                inTheme = true
                continue
            }
            if line.hasPrefix("[widget."), line.hasSuffix("]") {
                if let widget = active { result.append(widget) }
                let id = String(line.dropFirst(8).dropLast())
                guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                    throw invalid("Use a simple widget name, such as [widget.weather].")
                }
                active = WidgetSettings(id: id)
                inTheme = false
                continue
            }
            guard active != nil || inTheme else { throw invalid("Place settings inside a [widget.name] section.") }
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(\.trimmed)
            guard pair.count == 2 else { throw invalid("Expected key = value.") }
            let key = pair[0]
            let value = pair[1]
            func string() throws -> String {
                if value.hasPrefix("\"") {
                    guard let data = value.data(using: .utf8), let text = try? JSONDecoder().decode(String.self, from: data) else {
                        throw invalid("Invalid quoted text.")
                    }
                    return text
                }
                return value
            }
            func list() throws -> [String] {
                if value.hasPrefix("[") {
                    guard let data = value.data(using: .utf8), let items = try? JSONDecoder().decode([String].self, from: data) else {
                        throw invalid("Use an array of quoted strings, such as [\"cpu\", \"memory\"].")
                    }
                    return items
                }
                return value.split(separator: ",").map(\.trimmed)
            }
            func number(_ range: ClosedRange<Double>) throws -> Double {
                guard let number = Double(value), number.isFinite, range.contains(number) else {
                    throw invalid("\(key) must be between \(range.lowerBound) and \(range.upperBound).")
                }
                return number
            }
            if inTheme {
                switch key {
                case "text_color", "background_color":
                    let color: ThemeColor
                    do { color = try ThemeColor(string()) }
                    catch { throw invalid(error.localizedDescription) }
                    if key == "text_color" { textColor = color }
                    else { backgroundColor = color }
                case "background_opacity": backgroundOpacity = try number(0...1)
                case "corner_radius": cornerRadius = try number(0...2000)
                default: throw invalid("Unknown theme setting \(key).")
                }
                continue
            }
            switch key {
            case "type": active!.type = try string()
            case "enabled":
                guard ["true", "false"].contains(value) else { throw invalid("enabled must be true or false.") }
                active!.enabled = value == "true"
            case "left", "x", "right": active!.left = try number(0...20000)
            case "top", "y": active!.top = try number(0...20000)
            case "width": active!.width = try number(180...4000)
            case "height": active!.height = try number(80...4000)
            case "font_size": active!.fontSize = try number(10...32)
            case "refresh_seconds": active!.interval = try number(1...86400)
            case "modules": active!.modules = try list()
            case "command": active!.command = try string()
            case "arguments": active!.arguments = try list()
            case "timeout_seconds": active!.timeout = try number(1...60)
            case "zip": active!.zip = try string()
            case "country": active!.country = try string().uppercased()
            case "units": active!.units = try string()
            case "symbols": active!.symbols = try list()
            case "labels": active!.labels = try list()
            case "time_zones": active!.timeZones = try list()
            case "cities": active!.cities = try list()
            case "time_format": active!.timeFormat = try string()
            case "clock_style": active!.clockStyle = try string()
            default: throw invalid("Unknown setting \(key).")
            }
        }
        if let widget = active { result.append(widget) }
        guard !result.isEmpty else { throw ConfigError(message: "Add at least one [widget.name] section.") }
        var identifiers = Set<String>()
        for widget in result {
            guard identifiers.insert(widget.id).inserted else { throw ConfigError(message: "Duplicate widget name \(widget.id).") }
            guard ["metrics", "command", "weather", "markets", "chatgpt", "clock"].contains(widget.type) else {
                throw ConfigError(message: "Unknown widget type \(widget.type).")
            }
            if widget.type == "clock" {
                guard ["cards", "text"].contains(widget.clockStyle) else {
                    throw ConfigError(message: "Clock clock_style must be cards or text.")
                }
                guard (1...8).contains(widget.timeZones.count),
                      widget.timeZones.allSatisfy({ TimeZone(identifier: $0) != nil }),
                      widget.cities.count == widget.timeZones.count,
                      widget.cities.allSatisfy({ !$0.isEmpty && $0.count <= 40 && !$0.contains(where: \.isNewline) }) else {
                    throw ConfigError(message: "Clock widgets need matching cities and valid time_zones lists with 1–8 entries.")
                }
                guard ["12h", "24h"].contains(widget.timeFormat) else {
                    throw ConfigError(message: "Clock time_format must be 12h or 24h.")
                }
            }
            if widget.type == "chatgpt", widget.height < 150 || widget.width < 300 {
                throw ConfigError(message: "ChatGPT widgets need width of at least 300 and height of at least 150.")
            }
            guard !widget.modules.isEmpty, widget.modules.allSatisfy({ metricFactories[$0] != nil }) else {
                throw ConfigError(message: "Use cpu, memory, disk, or uptime for modules in \(widget.id).")
            }
            guard ["fahrenheit", "celsius"].contains(widget.units) else { throw ConfigError(message: "Use fahrenheit or celsius for units.") }
            guard widget.country.count == 2, widget.country.allSatisfy(\.isLetter) else { throw ConfigError(message: "Use a two-letter country code.") }
            guard widget.symbols.count <= 12, !widget.symbols.isEmpty,
                  widget.symbols.allSatisfy({ !$0.isEmpty && $0.count <= 30 && !$0.contains(where: \.isWhitespace) }) else {
                throw ConfigError(message: "Choose between 1 and 12 market symbols.")
            }
        }
        widgets = result
        legacy = !sectioned
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

private func stripComment(_ line: String) -> String {
    var quoted = false
    var escaped = false
    for index in line.indices {
        let character = line[index]
        if escaped { escaped = false; continue }
        if character == "\\", quoted { escaped = true; continue }
        if character == "\"" { quoted.toggle() }
        if character == "#", !quoted { return String(line[..<index]) }
    }
    return line
}
