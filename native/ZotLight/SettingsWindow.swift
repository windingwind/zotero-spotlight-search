// ZotLight/SettingsWindow.swift
// Native macOS settings window — pure AppKit, no XIB, no SwiftUI.

import AppKit
import Foundation

class SettingsWindowController: NSWindowController {

    private var portField: NSTextField!
    private var syncIntervalField: NSTextField!
    private var autoStartCheckbox: NSButton!
    private var autoSyncCheckbox: NSButton!
    private var clickActionSelectRadio: NSButton!
    private var clickActionOpenRadio: NSButton!
    private var libraryStackView: NSStackView!
    private var libraryCheckboxes: [(button: NSButton, libraryID: String)] = []
    private var titleTemplateField: NSTextField!
    private var descriptionTemplateField: NSTextField!

    private var config: Config = Config.load()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ZotLight Settings"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
        populateControls()
        fetchAndPopulateLibraries()
    }

    // MARK: - UI Construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 20
        outer.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        outer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outer.topAnchor.constraint(equalTo: contentView.topAnchor),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])

        let cardWidth: CGFloat = 520 - 28 * 2  // 464

        // ── General ──
        portField = NSTextField()
        portField.placeholderString = "23119"
        portField.widthAnchor.constraint(equalToConstant: 80).isActive = true

        syncIntervalField = NSTextField()
        syncIntervalField.placeholderString = "10"
        syncIntervalField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let minutesLabel = NSTextField(labelWithString: "minutes")
        minutesLabel.textColor = .secondaryLabelColor
        minutesLabel.font = NSFont.systemFont(ofSize: 13)
        let intervalControl = NSStackView(views: [syncIntervalField, minutesLabel])
        intervalControl.orientation = .horizontal
        intervalControl.spacing = 6

        autoSyncCheckbox = NSButton(checkboxWithTitle: "Auto-sync on a timer",
                                    target: self, action: #selector(autoSyncToggled(_:)))

        autoStartCheckbox = NSButton(checkboxWithTitle: "Start automatically on login",
                                     target: nil, action: nil)

        clickActionSelectRadio = NSButton(radioButtonWithTitle: "Select item in library",
                                          target: self, action: #selector(clickActionChanged(_:)))
        clickActionSelectRadio.tag = 0
        clickActionOpenRadio = NSButton(radioButtonWithTitle: "Open item directly",
                                        target: self, action: #selector(clickActionChanged(_:)))
        clickActionOpenRadio.tag = 1

        let clickActionLabel = NSTextField(labelWithString: "On result click")
        clickActionLabel.font = NSFont.systemFont(ofSize: 13)
        clickActionLabel.alignment = .right
        clickActionLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        clickActionLabel.setContentHuggingPriority(.required, for: .horizontal)

        let clickActionRadios = NSStackView(views: [clickActionSelectRadio, clickActionOpenRadio])
        clickActionRadios.orientation = .horizontal
        clickActionRadios.spacing = 16
        clickActionRadios.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let clickActionRow = NSStackView(views: [clickActionLabel, clickActionRadios])
        clickActionRow.orientation = .horizontal
        clickActionRow.spacing = 8
        clickActionRow.alignment = .centerY

        let generalRows = NSStackView()
        generalRows.orientation = .vertical
        generalRows.alignment = .leading
        generalRows.spacing = 10
        let autoSyncControl = NSStackView(views: [autoSyncCheckbox, intervalControl])
        autoSyncControl.orientation = .horizontal
        autoSyncControl.spacing = 12

        generalRows.addArrangedSubview(formRow(label: "API Port", control: portField))
        generalRows.addArrangedSubview(formRow(label: "Sync", control: autoSyncControl))
        generalRows.addArrangedSubview(autoStartCheckbox)
        generalRows.addArrangedSubview(clickActionRow)

        let generalCard = makeCard(title: "General", content: generalRows, width: cardWidth)
        outer.addArrangedSubview(generalCard)

        // ── Libraries ──
        let hint = NSTextField(labelWithString: "Uncheck libraries to exclude them from Spotlight indexing.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = cardWidth - 32

        libraryStackView = NSStackView()
        libraryStackView.orientation = .vertical
        libraryStackView.alignment = .leading
        libraryStackView.spacing = 6
        libraryStackView.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        libraryStackView.translatesAutoresizingMaskIntoConstraints = false

        let placeholder = NSTextField(labelWithString: "Loading libraries…")
        placeholder.textColor = .tertiaryLabelColor
        libraryStackView.addArrangedSubview(placeholder)

        let libScroll = NSScrollView()
        libScroll.hasVerticalScroller = true
        libScroll.autohidesScrollers = true
        libScroll.borderType = .noBorder
        libScroll.drawsBackground = false
        libScroll.translatesAutoresizingMaskIntoConstraints = false
        libScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        libScroll.documentView = libraryStackView

        let libRows = NSStackView()
        libRows.orientation = .vertical
        libRows.alignment = .leading
        libRows.spacing = 8
        libRows.addArrangedSubview(hint)
        libRows.addArrangedSubview(libScroll)
        libScroll.widthAnchor.constraint(equalTo: libRows.widthAnchor).isActive = true

        let libCard = makeCard(title: "Libraries", content: libRows, width: cardWidth)
        outer.addArrangedSubview(libCard)

        // ── Display Templates ──
        let tokenHint = NSTextField(labelWithString: "Uses Zotero variable schema. Common: {{ title }} {{ authors }} {{ year }}\n{{ publicationTitle }} {{ DOI }} {{ itemType }} {{ firstCreator }} {{ library }}\nAny Zotero field name works: {{ shortTitle }} {{ date }} {{ ISBN }} …")
        tokenHint.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        tokenHint.textColor = .tertiaryLabelColor
        tokenHint.lineBreakMode = .byWordWrapping
        tokenHint.maximumNumberOfLines = 0
        tokenHint.preferredMaxLayoutWidth = cardWidth - 32

        titleTemplateField = NSTextField()
        titleTemplateField.placeholderString = "{{ title }}"
        titleTemplateField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        descriptionTemplateField = NSTextField()
        descriptionTemplateField.placeholderString = "{{ authors }} · {{ publicationTitle }} · {{ year }}"
        descriptionTemplateField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let tmplRows = NSStackView()
        tmplRows.orientation = .vertical
        tmplRows.alignment = .leading
        tmplRows.spacing = 10
        tmplRows.addArrangedSubview(tokenHint)
        tmplRows.addArrangedSubview(formRow(label: "Title", control: titleTemplateField))
        tmplRows.addArrangedSubview(formRow(label: "Description", control: descriptionTemplateField))

        let tmplCard = makeCard(title: "Display Templates", content: tmplRows, width: cardWidth)
        outer.addArrangedSubview(tmplCard)

        // ── Bottom button bar ──
        let importBtn = NSButton(title: "Import…", target: self, action: #selector(importConfig))
        importBtn.bezelStyle = .rounded
        importBtn.controlSize = .small
        importBtn.font = NSFont.systemFont(ofSize: 11)

        let exportBtn = NSButton(title: "Export…", target: self, action: #selector(exportConfig))
        exportBtn.bezelStyle = .rounded
        exportBtn.controlSize = .small
        exportBtn.font = NSFont.systemFont(ofSize: 11)

        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        resetBtn.font = NSFont.systemFont(ofSize: 11)

        let leftGroup = NSStackView(views: [importBtn, exportBtn, resetBtn])
        leftGroup.orientation = .horizontal
        leftGroup.spacing = 6

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.keyEquivalent = "\u{1B}"
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.keyEquivalent = "\r"
        saveBtn.bezelStyle = .rounded

        let rightGroup = NSStackView(views: [cancelBtn, saveBtn])
        rightGroup.orientation = .horizontal
        rightGroup.spacing = 8

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let btnBar = NSStackView(views: [leftGroup, spacer, rightGroup])
        btnBar.orientation = .horizontal
        btnBar.spacing = 8
        btnBar.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        outer.addArrangedSubview(btnBar)
    }

    // MARK: - UI Helpers

    private func makeCard(title: String, content: NSView, width: CGFloat) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor

        // Card background
        let card = NSBox()
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.fillColor = .controlBackgroundColor
        card.cornerRadius = 10
        card.borderColor = .separatorColor
        card.borderWidth = 0.5
        card.translatesAutoresizingMaskIntoConstraints = false

        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        card.widthAnchor.constraint(equalToConstant: width).isActive = true

        // Wrapper stack: title above card
        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 6
        wrapper.addArrangedSubview(titleLabel)
        wrapper.addArrangedSubview(card)

        return wrapper
    }

    private func formRow(label: String, control: NSView) -> NSStackView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 13)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 100).isActive = true
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let r = NSStackView(views: [lbl, control])
        r.orientation = .horizontal
        r.spacing = 8
        r.alignment = .centerY
        return r
    }

    // MARK: - Populate

    private func populateControls() {
        portField.stringValue = "\(config.apiPort)"
        syncIntervalField.stringValue = "\(config.syncIntervalMinutes)"
        autoStartCheckbox.state = Config.isLaunchAgentInstalled() ? .on : .off
        autoSyncCheckbox.state = config.autoSyncEnabled ? .on : .off
        syncIntervalField.isEnabled = config.autoSyncEnabled
        clickActionSelectRadio.state = config.openOnClick ? .off : .on
        clickActionOpenRadio.state = config.openOnClick ? .on : .off
        titleTemplateField.stringValue = config.titleTemplate
        descriptionTemplateField.stringValue = config.descriptionTemplate
    }

    private func fetchAndPopulateLibraries() {
        let port = config.apiPort
        DispatchQueue.global(qos: .userInitiated).async {
            var libraries: [(id: String, name: String)] = [("users/0", "My Library")]
            if let url = URL(string: "http://localhost:\(port)/api/users/0/groups?format=json") {
                let sem = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    defer { sem.signal() }
                    if let data = data,
                       let groups = try? JSONDecoder().decode([ZoteroGroup].self, from: data) {
                        for g in groups {
                            libraries.append(("groups/\(g.id)", g.data.name))
                        }
                    }
                }.resume()
                sem.wait()
            }
            DispatchQueue.main.async { self.populateLibraryCheckboxes(libraries) }
        }
    }

    private func populateLibraryCheckboxes(_ libraries: [(id: String, name: String)]) {
        for v in libraryStackView.arrangedSubviews {
            libraryStackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        libraryCheckboxes.removeAll()

        for lib in libraries {
            let cb = NSButton(checkboxWithTitle: lib.name, target: nil, action: nil)
            cb.state = config.excludedLibraries.contains(lib.id) ? .off : .on
            libraryStackView.addArrangedSubview(cb)
            libraryCheckboxes.append((button: cb, libraryID: lib.id))
        }

        let h = max(libraryStackView.fittingSize.height, 1)
        libraryStackView.frame.size.height = h
    }

    // MARK: - Actions

    @objc private func autoSyncToggled(_ sender: NSButton) {
        syncIntervalField.isEnabled = sender.state == .on
    }

    @objc private func clickActionChanged(_ sender: NSButton) {
        clickActionSelectRadio.state = sender.tag == 0 ? .on : .off
        clickActionOpenRadio.state = sender.tag == 1 ? .on : .off
    }

    @objc private func save() {
        guard let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)),
              port > 0, port < 65536 else {
            alert(title: "Invalid Port", message: "API port must be a number between 1 and 65535.")
            return
        }
        let wantsAutoSync = autoSyncCheckbox.state == .on
        var interval = config.syncIntervalMinutes
        if wantsAutoSync {
            guard let parsed = Int(syncIntervalField.stringValue.trimmingCharacters(in: .whitespaces)),
                  parsed > 0 else {
                alert(title: "Invalid Interval", message: "Sync interval must be a positive number of minutes.")
                return
            }
            interval = parsed
        }

        let excluded = libraryCheckboxes.filter { $0.button.state == .off }.map { $0.libraryID }
        let wantsAutoStart = autoStartCheckbox.state == .on
        let wasInstalled   = Config.isLaunchAgentInstalled()

        config.apiPort = port
        config.autoSyncEnabled = wantsAutoSync
        config.syncIntervalMinutes = interval
        config.excludedLibraries = excluded
        config.autoStartOnLogin = wantsAutoStart
        config.openOnClick = clickActionOpenRadio.state == .on
        let titleTmpl = titleTemplateField.stringValue.trimmingCharacters(in: .whitespaces)
        let descTmpl  = descriptionTemplateField.stringValue.trimmingCharacters(in: .whitespaces)
        let newTitle  = titleTmpl.isEmpty ? Config.defaults.titleTemplate : titleTmpl
        let newDesc   = descTmpl.isEmpty  ? Config.defaults.descriptionTemplate : descTmpl
        config.titleTemplate = newTitle
        config.descriptionTemplate = newDesc
        config.save()

        // Reconcile LaunchAgent
        if wantsAutoStart {
            if wasInstalled { Config.removeLaunchAgent() }
            config.installLaunchAgent()
        } else if wasInstalled {
            Config.removeLaunchAgent()
        }

        // Any config change: clear old indexed entries and do a full re-sync now
        DispatchQueue.global().async {
            clearSpotlightIndex()
            clearVersionState()
            runSync()
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @objc private func resetToDefaults() {
        let a = NSAlert()
        a.messageText = "Reset to Defaults?"
        a.informativeText = "This will restore all settings to their defaults and clear the Spotlight index. A full re-sync will run on next launch."
        a.alertStyle = .warning
        a.addButton(withTitle: "Reset")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Config.defaults.save()
        clearSpotlightIndex()
        clearVersionState()
        NSApplication.shared.terminate(nil)
    }

    @objc private func cancel() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func exportConfig() {
        config.exportToFile(relativeTo: window)
    }

    @objc private func importConfig() {
        guard let imported = Config.importFromFile(relativeTo: window) else { return }
        config = imported
        config.save()
        populateControls()
        for v in libraryStackView.arrangedSubviews {
            libraryStackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let placeholder = NSTextField(labelWithString: "Loading libraries…")
        placeholder.textColor = .tertiaryLabelColor
        libraryStackView.addArrangedSubview(placeholder)
        fetchAndPopulateLibraries()
    }

    private func alert(title: String, message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .warning
        a.addButton(withTitle: "OK")
        if let w = window { a.beginSheetModal(for: w) } else { a.runModal() }
    }

    // MARK: - Window lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }
}
