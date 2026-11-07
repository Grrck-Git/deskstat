import AppKit
import Darwin
import IOKit.ps

func batteryText() -> String {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
          let battery = sources.compactMap({ IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any] })
            .first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }),
          let current = battery[kIOPSCurrentCapacityKey] as? Double,
          let maximum = battery[kIOPSMaxCapacityKey] as? Double, maximum > 0 else {
        return "No internal battery"
    }
    let onAC = battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
    let charging = battery[kIOPSIsChargingKey] as? Bool == true
    let state = charging ? "Charging · AC power" : onAC ? "AC power" : "On battery"
    let timeKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
    let estimate = battery[timeKey] as? Int ?? -1
    let remaining = estimate > 0 ? "\n\(estimate / 60)h \(estimate % 60)m " + (charging ? "until full" : "remaining") : ""
    return bar(current / maximum) + "\n" + state + remaining
}

struct NetworkActivity {
    private struct Counters {
        let received: UInt32
        let sent: UInt32
    }

    private var previous: [String: Counters] = [:]
    private var timestamp: Double?
    private var download: [Double] = []
    private var upload: [Double] = []

    mutating func sample() -> String {
        let current = counters()
        let now = ProcessInfo.processInfo.systemUptime
        let before = previous
        let last = timestamp
        previous = current
        timestamp = now
        guard !current.isEmpty else {
            download.removeAll()
            upload.removeAll()
            return "No active Ethernet or Wi-Fi interface"
        }
        guard let last, now > last else { return "Sampling network activity…" }

        var received = 0.0
        var sent = 0.0
        for (name, values) in current {
            guard let old = before[name] else { continue }
            // Darwin interface byte counters can wrap at 32 bits.
            received += Double(values.received &- old.received)
            sent += Double(values.sent &- old.sent)
        }
        download = Array((download + [received / (now - last)]).suffix(16))
        upload = Array((upload + [sent / (now - last)]).suffix(16))
        return "↓ " + line(download) + "\n↑ " + line(upload)
    }

    private func counters() -> [String: Counters] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let list else { return [:] }
        defer { freeifaddrs(list) }
        var result: [String: Counters] = [:]
        var node: UnsafeMutablePointer<ifaddrs>? = list
        while let entry = node {
            let interface = entry.pointee
            node = interface.ifa_next
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en"), interface.ifa_flags & UInt32(IFF_RUNNING) != 0,
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
            result[name] = Counters(received: data.ifi_ibytes, sent: data.ifi_obytes)
        }
        return result
    }

    private func line(_ samples: [Double]) -> String {
        let peak = max(1, samples.max() ?? 1)
        let glyphs = Array("▁▂▃▄▅▆▇█")
        let sparkline = String(samples.map { glyphs[min(7, Int($0 / peak * 7))] })
        let rate = ByteCountFormatter.string(fromByteCount: Int64(samples.last ?? 0), countStyle: .decimal)
        return (rate + "/s").padding(toLength: 13, withPad: " ", startingAt: 0) + "  " + sparkline
    }
}

let musicSnapshotScript = """
if application id "com.apple.Music" is not running then return "closed"
with timeout of 4 seconds
    tell application id "com.apple.Music"
        if player state is stopped then return "stopped"
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackDuration to duration of current track
        set trackPosition to player position
        return (player state as text) & linefeed & (trackPosition as text) & linefeed & (trackDuration as text) & linefeed & trackName & linefeed & trackArtist
    end tell
end timeout
"""

func nowPlayingText(_ settings: WidgetSettings) async throws -> String {
    var request = settings
    request.command = "/usr/bin/osascript"
    request.arguments = ["-e", musicSnapshotScript]
    request.timeout = 60
    let output: String
    do {
        output = try await commandText(request)
    } catch {
        if error.localizedDescription.contains("-1743") {
            return "Allow DeskStat to read Music in\nPrivacy & Security → Automation."
        }
        throw error
    }
    return musicDisplayText(output)
}

func musicDisplayText(_ output: String) -> String {
    let parts = output.trimmingCharacters(in: .newlines)
        .split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
    if parts.first == "closed" { return "Open Apple Music to see playback." }
    if parts.first == "stopped" { return "Nothing playing in Apple Music." }
    guard parts.count >= 4 else { return "Playback information unavailable." }
    let artist = parts.count == 5 ? parts[4].replacingOccurrences(of: "\n", with: " ") : ""
    let state = parts[0] == "paused" ? "Paused" : "Playing"
    let title = parts[3]
    let subtitle = artist.isEmpty ? state : "\(artist) · \(state)"
    guard let position = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
          let duration = Double(parts[2].replacingOccurrences(of: ",", with: ".")),
          position.isFinite, duration.isFinite, duration > 0 else { return "\(title)\n\(subtitle)" }
    return "\(title)\n\(subtitle)\n" + bar(position / duration)
}
