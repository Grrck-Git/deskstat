import AppKit

@MainActor
final class SettingsWindow: NSObject {
    private let config: URL
    private let apply: (Settings) -> Void
    private let editor = NSTextView()
    private let status = NSTextField(labelWithString: "")
    private var savedSource: String
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false
    )

    init(config: URL, source: String, apply: @escaping (Settings) -> Void) {
        self.config = config
        self.apply = apply
        savedSource = source
        super.init()

        window.title = "DeskStat Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.center()

        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.string = source
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("DeskStat configuration")

        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = editor

        let description = NSTextField(wrappingLabelWithString:
            "Edit your widget layout and theme here. Save & Apply updates the config file and refreshes your desktop.")
        description.textColor = .secondaryLabelColor

        let revert = NSButton(title: "Reload From File", target: self, action: #selector(reloadFromFile))
        let save = NSButton(title: "Save & Apply", target: self, action: #selector(saveChanges))
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = [.command]
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        revert.setContentCompressionResistancePriority(.required, for: .horizontal)
        save.setContentCompressionResistancePriority(.required, for: .horizontal)
        let buttons = NSStackView(views: [status, revert, save])
        buttons.spacing = 8

        let content = NSView()
        window.contentView = content
        for view in [description, scroll, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16)
            ])
        }
        NSLayoutConstraint.activate([
            description.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 12),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        window.initialFirstResponder = editor
    }

    func show(source: String) {
        if editor.string == savedSource, source != savedSource {
            load(source)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func saveChanges() {
        do {
            let source = editor.string
            let next = try Settings(source)
            let diskSource = try String(contentsOf: config, encoding: .utf8)
            guard diskSource == savedSource || diskSource == source else {
                throw ConfigError(message: "The config file changed on disk. Copy any edits you want to keep, then use Reload From File before saving.")
            }
            if diskSource != source {
                try source.write(to: config, atomically: true, encoding: .utf8)
            }
            savedSource = source
            apply(next)
            status.stringValue = "Settings saved and applied."
        } catch {
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    @objc private func reloadFromFile() {
        if editor.string != savedSource {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved settings edits?"
            alert.addButton(withTitle: "Discard and Reload")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.readFile()
                }
            }
        } else {
            readFile()
        }
    }

    private func readFile() {
        do {
            load(try String(contentsOf: config, encoding: .utf8))
        } catch {
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    private func load(_ source: String) {
        editor.string = source
        editor.undoManager?.removeAllActions()
        savedSource = source
        status.stringValue = "Loaded from the config file."
    }
}
