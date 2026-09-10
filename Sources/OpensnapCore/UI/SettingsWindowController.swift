import Cocoa

/// Settings window for the menu-bar app: screenshot folder, filename pattern,
/// Open at Login, and global hotkeys. Edits a draft; Save writes
/// `~/.config/opensnap/opensnap.conf` and applies (hotkeys re-register, login
/// item flips). Cancel/close discards.
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public var onSave: ((AppConfig) -> [String])?
    /// Fires when global-hotkey suspension should change: true while any
    /// recorder is armed (live hotkeys must not fire mid-record).
    public var onRecordingChanged: ((Bool) -> Void)?
    private var wasRecording = false

    private var draft = AppConfig.load()
    private var folderField = NSTextField()
    private var filenameField = NSTextField()
    private var loginCheckbox = NSSwitch()
    private var generalView = NSView()
    private var hotkeysView = NSView()
    private var aboutView = NSView()
    private var recorders: [HotkeyManager.Action: HotkeyRecorderButton] = [:]
    private var noticeLabel = NSTextField()

    private var generalPageHeight: NSLayoutConstraint?
    private var tabSwitchControl: NSSegmentedControl?
    private var buttonsRow: NSStackView?
    private var shotsCardBox: NSBox?
    private var systemCardBox: NSBox?
    private var hotkeysCardBox: NSBox?
    private var hotkeysHintLabel: NSTextField?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 448),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "opensnap Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
        reloadDraft()
        refitWindowToContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let tabSwitch = NSSegmentedControl(
            labels: ["General", "Hotkeys", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(tabChanged(_:))
        )
        tabSwitch.selectedSegment = 0
        tabSwitch.translatesAutoresizingMaskIntoConstraints = false
        tabSwitchControl = tabSwitch

        generalView.translatesAutoresizingMaskIntoConstraints = false
        hotkeysView.translatesAutoresizingMaskIntoConstraints = false
        aboutView.translatesAutoresizingMaskIntoConstraints = false
        hotkeysView.isHidden = true
        aboutView.isHidden = true
        buildGeneral(into: generalView)
        buildHotkeys(into: hotkeysView)
        buildAbout(into: aboutView)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.bezelColor = .controlAccentColor
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttonsRow = buttons

        noticeLabel.isEditable = false
        noticeLabel.isBordered = false
        noticeLabel.drawsBackground = false
        noticeLabel.textColor = .systemOrange
        noticeLabel.font = NSFont.systemFont(ofSize: 11)
        noticeLabel.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(tabSwitch)
        content.addSubview(generalView)
        content.addSubview(hotkeysView)
        content.addSubview(aboutView)
        content.addSubview(noticeLabel)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            tabSwitch.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            tabSwitch.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            generalView.topAnchor.constraint(equalTo: tabSwitch.bottomAnchor, constant: 12),
            generalView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            generalView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            generalView.widthAnchor.constraint(equalToConstant: 404),

            hotkeysView.topAnchor.constraint(equalTo: tabSwitch.bottomAnchor, constant: 12),
            hotkeysView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            hotkeysView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            hotkeysView.widthAnchor.constraint(equalToConstant: 404),

            aboutView.topAnchor.constraint(equalTo: tabSwitch.bottomAnchor, constant: 12),
            aboutView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            aboutView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            aboutView.widthAnchor.constraint(equalToConstant: 404),

            noticeLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            noticeLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            noticeLabel.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        // Both pages share one height (the taller content); the shorter page
        // top-aligns its content. Set in refitWindowToContent().
        let gh = generalView.heightAnchor.constraint(equalToConstant: 200)
        gh.isActive = true
        generalPageHeight = gh
        hotkeysView.heightAnchor.constraint(equalTo: generalView.heightAnchor).isActive = true
        aboutView.heightAnchor.constraint(equalTo: generalView.heightAnchor).isActive = true
    }

    /// Sizes the page host to the taller page and shrinks the window to fit,
    /// so neither tab has dead space. Card heights are explicit constants
    /// (see build sites); only leaf text (hint/notice) is measured. Called
    /// once at build.
    private func refitWindowToContent() {
        guard let window, let content = window.contentView else { return }
        window.layoutIfNeeded()
        // generalH: header + gaps + shotsCard(127) + header + gaps + systemCard(50)
        let generalH: CGFloat = 14 + 6 + 127 + 14 + 14 + 6 + 50
        let hintH = hotkeysHintLabel?.fittingSize.height ?? 28
        let hotkeysH: CGFloat = 14 + 6 + 191 + 8 + hintH
        let hostH = max(generalH, hotkeysH)
        generalPageHeight?.constant = hostH
        window.layoutIfNeeded()
        // Recompute exact window height from measured parts.
        let segH = tabSwitchControl?.fittingSize.height ?? 28
        let noticeH = max(18, noticeLabel.fittingSize.height)
        let buttonsH = buttonsRow?.fittingSize.height ?? 30
        let titlebarH = window.frame.height - content.frame.height
        let total = 14 + segH + 12 + hostH + 10 + noticeH + 8 + buttonsH + 14
        var frame = window.frame
        frame.origin.y += frame.height - (titlebarH + total)
        frame.size.height = titlebarH + total
        window.setFrame(frame, display: false)
        // Fixed-size panel: explicit content size stops Auto Layout from
        // shrink-wrapping the window around compressible fields.
        window.contentMinSize = NSSize(width: 440, height: total)
        window.contentMaxSize = NSSize(width: 440, height: total)
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// iOS-style small caps section header.
    private func makeSectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Frosted grouped card (iOS Settings style). Adapts to light/dark via
    /// semantic colors.
    private func makeCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = NSColor.controlBackgroundColor
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1.0
        box.cornerRadius = 12.0
        box.contentViewMargins = NSSize(width: 12, height: 12)
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func makeSeparator() -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        return sep
    }

    private func makeFootnote(_ text: String) -> NSTextField {
        let hint = NSTextField(labelWithString: text)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        return hint
    }

    private func buildGeneral(into view: NSView) {
        let shotsHeader = makeSectionHeader("Screenshots")
        let shotsCard = makeCard()
        let shotsStack = NSStackView()
        shotsStack.orientation = .vertical
        shotsStack.spacing = 12
        shotsStack.translatesAutoresizingMaskIntoConstraints = false

        let folderRow = NSStackView()
        folderRow.orientation = .horizontal
        folderRow.spacing = 8
        let folderCaption = makeLabel("Folder")
        folderCaption.widthAnchor.constraint(equalToConstant: 52).isActive = true
        folderField.translatesAutoresizingMaskIntoConstraints = false
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder(_:)))
        chooseButton.bezelStyle = .rounded
        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        chooseButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        folderRow.addArrangedSubview(folderCaption)
        folderRow.addArrangedSubview(folderField)
        folderRow.addArrangedSubview(chooseButton)

        let nameRow = NSStackView()
        nameRow.orientation = .horizontal
        nameRow.spacing = 8
        let nameCaption = makeLabel("Name")
        nameCaption.widthAnchor.constraint(equalToConstant: 52).isActive = true
        filenameField.translatesAutoresizingMaskIntoConstraints = false
        nameRow.addArrangedSubview(nameCaption)
        nameRow.addArrangedSubview(filenameField)

        shotsStack.addArrangedSubview(folderRow)
        shotsStack.addArrangedSubview(makeSeparator())
        shotsStack.addArrangedSubview(nameRow)
        shotsStack.addArrangedSubview(makeFootnote("Tokens: {date} {time} {app}  ·  “.png” is appended"))
        shotsCard.contentView?.addSubview(shotsStack)
        if let cardContent = shotsCard.contentView {
            NSLayoutConstraint.activate([
                shotsStack.topAnchor.constraint(equalTo: cardContent.topAnchor),
                shotsStack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor),
                shotsStack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor),
                shotsStack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor),
            ])
        }

        let systemHeader = makeSectionHeader("System")
        let systemCard = makeCard()
        let loginRow = NSStackView()
        loginRow.orientation = .horizontal
        loginRow.translatesAutoresizingMaskIntoConstraints = false
        loginRow.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let loginLabel = makeLabel("Open at Login")
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        loginCheckbox = NSSwitch()
        loginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        loginRow.addArrangedSubview(loginLabel)
        loginRow.addArrangedSubview(spacer)
        loginRow.addArrangedSubview(loginCheckbox)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
        systemCard.contentView?.addSubview(loginRow)
        if let cardContent = systemCard.contentView {
            NSLayoutConstraint.activate([
                loginRow.topAnchor.constraint(equalTo: cardContent.topAnchor),
                loginRow.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor),
                loginRow.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor),
                loginRow.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor),
            ])
        }

        view.addSubview(shotsHeader)
        view.addSubview(shotsCard)
        view.addSubview(systemHeader)
        view.addSubview(systemCard)
        NSLayoutConstraint.activate([
            shotsHeader.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            shotsHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            shotsCard.topAnchor.constraint(equalTo: shotsHeader.bottomAnchor, constant: 6),
            shotsCard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shotsCard.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            systemHeader.topAnchor.constraint(equalTo: shotsCard.bottomAnchor, constant: 14),
            systemHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            systemCard.topAnchor.constraint(equalTo: systemHeader.bottomAnchor, constant: 6),
            systemCard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            systemCard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            systemCard.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
        // Explicit heights: NSBox doesn't reliably derive height from its
        // content here, so cards are sized arithmetically from their rows
        // (24pt rows, 12pt stack gaps, 12pt card padding).
        // shotsCard: 24 + 12 + 5 + 12 + 24 + 12 + 14 + 24 = 127
        shotsCard.heightAnchor.constraint(equalToConstant: 127).isActive = true
        // systemCard: 26 + 24 = 50
        systemCard.heightAnchor.constraint(equalToConstant: 50).isActive = true
        shotsCardBox = shotsCard
        systemCardBox = systemCard
    }

    private func buildHotkeys(into view: NSView) {
        let header = makeSectionHeader("Shortcuts")
        let card = makeCard()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titles: [(HotkeyManager.Action, String)] = [
            (.region, "Capture Region"),
            (.window, "Capture Window"),
            (.scroll, "Capture Scrolling Region"),
            (.fullscreen, "Capture Fullscreen"),
        ]
        var first = true
        for (action, title) in titles {
            if !first {
                stack.addArrangedSubview(makeSeparator())
            }
            first = false
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let label = makeLabel(title)
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            let recorder = HotkeyRecorderButton()
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 148).isActive = true
            recorder.onRecordingChange = { [weak self] _ in self?.recheckRecording() }
            recorders[action] = recorder
            row.addArrangedSubview(label)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(recorder)
            row.heightAnchor.constraint(equalToConstant: 26).isActive = true
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
            stack.addArrangedSubview(row)
        }
        card.contentView?.addSubview(stack)
        if let cardContent = card.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cardContent.topAnchor),
                stack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor),
            ])
        }

        let hint = makeFootnote("Click a shortcut, then press keys (needs ⌘/⌃/⌥/⇧). Delete clears · Esc cancels.")
        view.addSubview(header)
        view.addSubview(card)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            hint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            hint.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
        hotkeysCardBox = card
        hotkeysHintLabel = hint
        // 4×26 rows + 3×5 separators + 6×8 gaps + 24 padding = 191
        card.heightAnchor.constraint(equalToConstant: 191).isActive = true
    }

    private func buildAbout(into view: NSView) {
        let header = makeSectionHeader("About")

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let card = makeCard()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (key, value) in [("Name", "opensnap"), ("Version", OpensnapApp.version)] {
            if stack.arrangedSubviews.isEmpty == false {
                stack.addArrangedSubview(makeSeparator())
            }
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let keyLabel = makeLabel(key)
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            let valueLabel = makeLabel(value)
            valueLabel.alignment = .right
            valueLabel.textColor = .secondaryLabelColor
            row.addArrangedSubview(keyLabel)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(valueLabel)
            row.heightAnchor.constraint(equalToConstant: 26).isActive = true
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
            stack.addArrangedSubview(row)
        }
        card.contentView?.addSubview(stack)
        if let cardContent = card.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cardContent.topAnchor),
                stack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor),
            ])
        }
        // 2×26 rows + 1×5 separator + 2×8 gaps + 24 padding = 97
        card.heightAnchor.constraint(equalToConstant: 97).isActive = true

        let footnote = makeFootnote("Native macOS screenshot and annotation editor.")
        view.addSubview(header)
        view.addSubview(iconView)
        view.addSubview(card)
        view.addSubview(footnote)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            header.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            footnote.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 8),
            footnote.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            footnote.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            footnote.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
    }

    // MARK: - Draft load/save

    private func reloadDraft() {
        draft = AppConfig.load()
        folderField.stringValue = draft.outputDirectory
        filenameField.stringValue = draft.filenamePattern
        let home = FileManager.default.homeDirectoryForCurrentUser
        loginCheckbox.state = MenuBarSupport.isLoginItemEnabled(home: home) ? .on : .off
        for action in HotkeyManager.Action.allCases {
            recorders[action]?.binding = draft.hotkeys[action.rawValue]
        }
        noticeLabel.stringValue = ""
    }

    public func show() {
        reloadDraft()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        showTab(sender.selectedSegment)
    }

    /// Test hook (also used for snapshot rendering).
    func showTab(_ index: Int) {
        generalView.isHidden = index != 0
        hotkeysView.isHidden = index != 1
        aboutView.isHidden = index != 2
    }

    /// Aggregates recorder arming into edge-triggered suspension notices.
    func recheckRecording() {
        let now = recorders.values.contains { $0.isRecording }
        guard now != wasRecording else { return }
        wasRecording = now
        onRecordingChanged?(now)
    }

    /// Disarms every recorder (Save/Cancel/close while armed).
    func stopAllRecording() {
        for recorder in recorders.values {
            recorder.cancelRecording()
        }
    }

    @objc private func chooseFolder(_ sender: Any?) {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.folderField.stringValue = url.path
            }
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // × discards like Cancel; never leave a recorder armed behind.
        stopAllRecording()
        return true
    }

    @objc private func save(_ sender: Any?) {
        stopAllRecording()
        let folder = folderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = filenameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty, !pattern.isEmpty else {
            notice("Folder and filename pattern must not be empty.", warning: true)
            return
        }
        draft.outputDirectory = folder
        draft.filenamePattern = pattern
        draft.hotkeys = [:]
        for (action, recorder) in recorders {
            if let binding = recorder.binding {
                draft.hotkeys[action.rawValue] = binding
            }
        }
        do {
            try draft.save()
        } catch {
            notice("Could not write config: \(error.localizedDescription)", warning: true)
            return
        }
        // Apply Open at Login.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let wantLogin = loginCheckbox.state == .on
        if wantLogin != MenuBarSupport.isLoginItemEnabled(home: home) {
            let program = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? ""
            do {
                try MenuBarSupport.setLoginItemEnabled(wantLogin, menubarProgram: program, home: home)
            } catch {
                notice("Login item failed: \(error.localizedDescription). " +
                       (MenuBarSupport.isAppBundle ? "The app must live in /Applications." : ""),
                       warning: true)
                return
            }
        }
        // Apply hotkeys; report combinations the system rejected.
        let failed = onSave?(draft) ?? []
        if !failed.isEmpty {
            notice("Saved, but the system rejected: \(failed.joined(separator: ", ")) (already in use?)", warning: true)
            return
        }
        notice("")
        window?.close()
    }

    @objc private func cancel(_ sender: Any?) {
        stopAllRecording()
        window?.close()
    }

    private func notice(_ text: String, warning: Bool = false) {
        noticeLabel.stringValue = text
        noticeLabel.textColor = warning ? .systemOrange : .secondaryLabelColor
    }
}

/// Click-to-record shortcut button. Click to arm, press the combo (a modifier
/// is required), Delete clears, Esc cancels. Never fires an action.
final class HotkeyRecorderButton: NSButton {
    var binding: HotkeyBinding? { didSet { updateTitle() } }
    private(set) var isRecording = false { didSet { updateTitle() } }
    /// Fires on every recording-state transition (arm/disarm).
    var onRecordingChange: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = nil
        action = nil
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        onRecordingChange?(recording)
    }

    /// Forcibly disarms (Save/Cancel/close while armed).
    func cancelRecording() {
        setRecording(false)
    }

    override func mouseDown(with event: NSEvent) {
        // Arm recording instead of firing any action.
        window?.makeFirstResponder(self)
        setRecording(true)
    }

    override func resignFirstResponder() -> Bool {
        setRecording(false)
        return super.resignFirstResponder()
    }

    private func updateTitle() {
        if isRecording {
            title = "Press shortcut…"
        } else if let binding = binding {
            title = binding.displayLabel
        } else {
            title = "Record shortcut"
        }
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        if isRecording {
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            var s = ""
            if mods.contains(.control) { s += "⌃" }
            if mods.contains(.option) { s += "⌥" }
            if mods.contains(.shift) { s += "⇧" }
            if mods.contains(.command) { s += "⌘" }
            title = s.isEmpty ? "Press shortcut…" : s + "…"
        } else {
            super.flagsChanged(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { // Esc: cancel
            setRecording(false)
            window?.makeFirstResponder(window?.contentView)
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete: clear
            binding = nil
            setRecording(false)
            window?.makeFirstResponder(window?.contentView)
            return
        }
        guard let next = HotkeyBinding.from(event: event) else {
            title = "Needs ⌘/⌃/⌥/⇧ + key…"
            NSSound.beep()
            return
        }
        binding = next
        setRecording(false)
        window?.makeFirstResponder(window?.contentView)
    }
}
