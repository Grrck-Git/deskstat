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

struct Disk: Metric {
    func sample() -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let bytes = attributes[.systemFreeSize] as? NSNumber else { return "DISK    unavailable" }
        return "DISK    " + ByteCountFormatter.string(fromByteCount: bytes.int64Value, countStyle: .file) + " free"
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

