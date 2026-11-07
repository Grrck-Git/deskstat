import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--check-config" || arguments.first == "--sample" {
    do {
        let source = try arguments.dropFirst().first.map { try String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        let settings = try Settings(source)
        for widget in settings.widgets {
            print("\(widget.id): \(widget.type), enabled=\(widget.enabled), left=\(widget.left), top=\(widget.top)")
            if arguments.first == "--sample", widget.type == "clock", widget.enabled {
                print(WorkClock(widget).sample())
            }
            if arguments.first == "--sample", widget.type == "metrics", widget.enabled {
                var metrics = widget.modules.compactMap { metricFactories[$0]?() }
                for index in metrics.indices { _ = metrics[index].sample() }
                Thread.sleep(forTimeInterval: min(2, widget.interval))
                for index in metrics.indices { print(metrics[index].sample()) }
            }
        }
    } catch {
        fputs(error.localizedDescription + "\n", stderr)
        exit(1)
    }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = DeskStat()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
