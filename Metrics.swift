import AppKit
import Darwin

protocol Metric {
    mutating func sample() -> String
}

func bar(_ fraction: Double) -> String {
    let percent = Int((min(1, max(0, fraction)) * 100).rounded())
    let filled = percent / 10
    return String(repeating: "█", count: filled) + String(repeating: "░", count: 10 - filled)
        + String(format: " %3d%%", percent)
}

private let hostPort = mach_host_self()


struct CPU: Metric {
    private var previous: [UInt32]?

    mutating func sample() -> String {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return "CPU     unavailable" }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previous = ticks }
        guard let previous else { return "CPU     sampling…" }
        let delta = zip(ticks, previous).map { Double($0.0 &- $0.1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return "CPU     sampling…" }
        return "CPU     " + bar(1 - delta[Int(CPU_STATE_IDLE)] / total)
    }
}

struct Memory: Metric {
    func sample() -> String {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return "RAM     unavailable" }
        let pages = Double(info.internal_page_count) + Double(info.wire_count)
            + Double(info.compressor_page_count) - Double(info.purgeable_count)
        let used = pages * Double(vm_kernel_page_size)
        return "RAM     " + bar(used / Double(ProcessInfo.processInfo.physicalMemory))
    }
}

struct DiskCapacity {
    let free: Int64
    let available: Int64?
    var text: String {
        func size(_ bytes: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        guard let available, available >= free else {
            return "DISK    " + size(free) + " free\n        Purgeable unavailable"
        }
        // Important-usage capacity is a budget, not an exact count of purgeable files.
        let reclaimable = available - free
        return "DISK    " + size(available) + " available\n        "
            + size(free) + " free · ~" + size(reclaimable) + " purgeable"
    }
}

struct Disk: Metric {
    private var cached: String?
    private var sampledAt: TimeInterval = -.infinity

    mutating func sample() -> String {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, now - sampledAt < 60 { return cached }
        // A fresh URL avoids retaining Foundation's cached resource values indefinitely.
        let home = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
        let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ])
        let fallback = try? FileManager.default.attributesOfFileSystem(forPath: home.path)
        guard let free = values?.volumeAvailableCapacity.map(Int64.init)
                ?? (fallback?[.systemFreeSize] as? NSNumber)?.int64Value, free >= 0 else {
            return "DISK    unavailable"
        }
        let output = DiskCapacity(free: free, available: values?.volumeAvailableCapacityForImportantUsage).text
        cached = output
        sampledAt = now
        return output
    }
}

struct Uptime: Metric {
    func sample() -> String {
        let minutes = Int(ProcessInfo.processInfo.systemUptime) / 60
        return "UP      \(minutes / 1440)d \((minutes / 60) % 24)h \(minutes % 60)m"
    }
}

let metricFactories: [String: () -> any Metric] = [
    "cpu": { CPU() }, "memory": { Memory() }, "disk": { Disk() }, "uptime": { Uptime() }
]

