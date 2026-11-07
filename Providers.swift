import AppKit
import Darwin

func fetchJSON(_ base: String, _ query: [String: String] = [:]) async throws -> Data {
    var parts = URLComponents(string: base)!
    parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    var request = URLRequest(url: parts.url!, timeoutInterval: 20)
    request.setValue("DeskStat/0.2", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        throw ConfigError(message: "The data service is unavailable. Will retry.")
    }
    return data
}

struct WeatherLocation: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
}

private struct Locations: Decodable { let results: [WeatherLocation]? }
private struct Forecast: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let time: String
    }
    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Double?]
    }
    let current: Current
    let daily: Daily
}

func weatherLocation(_ settings: WidgetSettings) async throws -> WeatherLocation {
    let data = try await fetchJSON("https://geocoding-api.open-meteo.com/v1/search", [
        "name": settings.zip, "countryCode": settings.country, "count": "1"
    ])
    guard let place = try JSONDecoder().decode(Locations.self, from: data).results?.first else {
        throw ConfigError(message: "ZIP/postal code not found. Check zip and country.")
    }
    return place
}

func weatherText(_ settings: WidgetSettings, location: WeatherLocation) async throws -> String {
    let data = try await fetchJSON("https://api.open-meteo.com/v1/forecast", [
        "latitude": String(location.latitude), "longitude": String(location.longitude),
        "current": "temperature_2m,weather_code",
        "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        "temperature_unit": settings.units, "timezone": "auto", "forecast_days": "1"
    ])
    let forecast = try JSONDecoder().decode(Forecast.self, from: data)
    let current = forecast.current
    let unit = settings.units == "fahrenheit" ? "°F" : "°C"
    let region = location.admin1.map { ", \($0)" } ?? ""
    var lines = ["\(location.name)\(region)",
                 String(format: "%.0f%@  %@", current.temperature_2m, unit, condition(current.weather_code))]
    if let high = forecast.daily.temperature_2m_max.first, let low = forecast.daily.temperature_2m_min.first {
        lines.append(String(format: "High %.0f°  Low %.0f°", high, low))
    }
    if let rain = forecast.daily.precipitation_probability_max.first ?? nil {
        lines.append(String(format: "Precipitation chance %.0f%%", rain))
    }
    lines.append("As of \(current.time.replacingOccurrences(of: "T", with: " ")) local")
    lines.append("Weather by Open-Meteo · CC BY 4.0")
    return lines.joined(separator: "\n")
}

private func condition(_ code: Int) -> String {
    switch code {
    case 0: return "Clear"
    case 1: return "Mostly clear"
    case 2: return "Partly cloudy"
    case 3: return "Overcast"
    case 45, 48: return "Fog"
    case 51...57: return "Drizzle"
    case 61...67: return "Rain"
    case 71...77: return "Snow"
    case 80...82: return "Rain showers"
    case 85, 86: return "Snow showers"
    case 95...99: return "Thunderstorms"
    default: return "Conditions unavailable"
    }
}

private struct Chart: Decodable {
    struct Container: Decodable { let result: [Result]? }
    struct Result: Decodable {
        struct Meta: Decodable {
            let regularMarketPrice: Double?
            let regularMarketTime: Double?
            let regularMarketChangePercent: Double?
            let previousClose: Double?
            let chartPreviousClose: Double?
            let currency: String?
        }
        let meta: Meta
    }
    let chart: Container
}

func marketText(symbol: String, label: String) async throws -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: allowed) else { throw ConfigError(message: "Invalid symbol.") }
    let data = try await fetchJSON("https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)", ["interval": "1d", "range": "1d"])
    return try decodeMarket(data, symbol: symbol, label: label)
}

func decodeMarket(_ data: Data, symbol: String, label: String) throws -> String {
    guard let meta = try JSONDecoder().decode(Chart.self, from: data).chart.result?.first?.meta,
          let price = meta.regularMarketPrice, price.isFinite,
          let timestamp = meta.regularMarketTime, timestamp.isFinite else {
        throw ConfigError(message: "No quote for \(symbol).")
    }
    let prior = meta.previousClose ?? meta.chartPreviousClose
    let change = meta.regularMarketChangePercent ?? prior.flatMap { $0 > 0 ? (price / $0 - 1) * 100 : nil }
    let delta = change.map { String(format: "%+.2f%%", $0) } ?? "change unavailable"
    let date = Date(timeIntervalSince1970: timestamp)
    let stamp = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    return "\(label) [\(symbol)]\n" + String(format: "%.2f", price) + " \(meta.currency ?? "")  \(delta)\nQuote \(stamp)"
}

// Commands run directly, without a shell. Output goes to a temporary file so a full pipe cannot deadlock.
func commandText(_ settings: WidgetSettings) async throws -> String {
    let job = Task.detached(priority: .utility) { () throws -> String in
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("DeskStat-\(UUID().uuidString)")
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output")
        files.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].map { $0 + "/" + settings.command }
        let executable = settings.command.hasPrefix("/") ? settings.command : candidates.first(where: files.isExecutableFile)
        guard let executable, files.isExecutableFile(atPath: executable) else {
            throw ConfigError(message: "Command not found: \(settings.command)")
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = settings.arguments
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        process.currentDirectoryURL = files.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TERM"] = "xterm-256color"
        environment["COLUMNS"] = String(max(20, Int(settings.width / (settings.fontSize * 0.61))))
        process.environment = environment
        try Task.checkCancellation()
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + settings.timeout
        var failure: String?
        while process.isRunning {
            let size = (try? files.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
            if Task.isCancelled { failure = "Command cancelled." }
            if size > 1_048_576 { failure = "Command output exceeded 1 MB." }
            if ProcessInfo.processInfo.systemUptime >= deadline { failure = "Command timed out." }
            if failure != nil { kill(process.processIdentifier, SIGKILL); break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        process.waitUntilExit()
        if let failure { throw ConfigError(message: failure) }
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 1_048_576) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ConfigError(message: "Command exited \(process.terminationStatus).\n\(String(text.prefix(1000)))")
        }
        return text.isEmpty ? "Command returned no output." : text
    }
    return try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
}

// Preserve common ANSI SGR colors and strip terminal control sequences from periodic output.
func ansiText(_ source: String, font: NSFont, color: NSColor) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    let pattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]|\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)"
    let regex = try! NSRegularExpression(pattern: pattern)
    let text = source as NSString
    var position = 0
    var foreground = color
    let palette: [NSColor] = [.black, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPurple, .systemTeal, .lightGray,
                              .darkGray, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPink, .systemCyan, .white]
    func append(_ range: NSRange) {
        result.append(NSAttributedString(string: text.substring(with: range).replacingOccurrences(of: "\r", with: ""),
                                         attributes: [.font: font, .foregroundColor: foreground]))
    }
    for match in regex.matches(in: source, range: NSRange(location: 0, length: text.length)) {
        append(NSRange(location: position, length: match.range.location - position))
        let sequence = text.substring(with: match.range)
        if sequence.hasPrefix("\u{001B}["), sequence.hasSuffix("m") {
            let codes = sequence.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
            var index = 0
            while index < codes.count {
                let code = codes[index]
                switch code {
                case 0, 39: foreground = color
                case 30...37: foreground = palette[code - 30]
                case 90...97: foreground = palette[code - 90 + 8]
                case 38, 48:
                    if index + 4 < codes.count, codes[index + 1] == 2 {
                        if code == 38 {
                            foreground = NSColor(srgbRed: CGFloat(min(255, max(0, codes[index + 2]))) / 255,
                                                 green: CGFloat(min(255, max(0, codes[index + 3]))) / 255,
                                                 blue: CGFloat(min(255, max(0, codes[index + 4]))) / 255, alpha: 1)
                        }
                        index += 4
                    } else if index + 2 < codes.count, codes[index + 1] == 5 {
                        let value = min(255, max(0, codes[index + 2]))
                        if code == 38 {
                            if value < 16 { foreground = palette[value] }
                            else if value < 232 {
                                let n = value - 16
                                let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
                                foreground = NSColor(srgbRed: levels[n / 36] / 255, green: levels[(n / 6) % 6] / 255,
                                                     blue: levels[n % 6] / 255, alpha: 1)
                            } else { foreground = NSColor(white: CGFloat(8 + (value - 232) * 10) / 255, alpha: 1) }
                        }
                        index += 2
                    }
                default: break
                }
                index += 1
            }
        }
        position = match.range.location + match.range.length
    }
    append(NSRange(location: position, length: text.length - position))
    return result
}
