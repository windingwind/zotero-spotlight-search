// ZotLight/main.swift
// Background app: fetches Zotero personal + group libraries via local API and
// indexes items into Core Spotlight. Supports incremental updates via version/since.
//
// When a Spotlight result is clicked, macOS sends a NSUserActivity back to
// this app, which extracts the zotero:// URL and opens it in Zotero.

import Foundation
import CoreSpotlight
import AppKit
import UserNotifications

// MARK: - Active Config (loaded at sync time; defaults used until first sync)

var activeConfig: Config = .defaults

// MARK: - Version State
// Persists per-library version to ~/.config/zotlight/{libraryID}

let stateDir = NSHomeDirectory() + "/.config/zotlight"

func loadLastVersion(for libraryID: String) -> Int {
    let path = "\(stateDir)/\(libraryID)"
    guard let s = try? String(contentsOfFile: path, encoding: .utf8),
          let v = Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return 0 }
    return v
}

func saveVersion(_ version: Int, for libraryID: String) {
    try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
    try? String(version).write(toFile: "\(stateDir)/\(libraryID)", atomically: true, encoding: .utf8)
}

func clearVersionState() {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: stateDir) else { return }
    for entry in entries {
        // Keep config.json, only remove version state files
        if entry == "config.json" { continue }
        try? fm.removeItem(atPath: "\(stateDir)/\(entry)")
    }
}

func clearSpotlightIndex() {
    let sem = DispatchSemaphore(value: 0)
    CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["com.zotlight.app"]) { error in
        if let error = error {
            fputs("Clear error: \(error.localizedDescription)\n", stderr)
        } else {
            print("Cleared all ZotLight items from Spotlight.")
        }
        sem.signal()
    }
    sem.wait()
}

// MARK: - Zotero API Models

struct ZoteroGroup: Codable {
    let id: Int
    let data: GroupData
    struct GroupData: Codable {
        let name: String
    }
}

struct ZoteroItem: Codable {
    let key: String
    let version: Int
    let data: ItemData

    /// Decodes all Zotero data fields into a raw dictionary for dynamic template access,
    /// while keeping typed access to creators and tags.
    struct ItemData: Codable {
        let fields: [String: String]   // all scalar string fields (title, date, DOI, etc.)
        let creators: [Creator]
        let tags: [Tag]

        var key: String { fields["key"] ?? "" }
        var itemType: String { fields["itemType"] ?? "" }
        var title: String? { fields["title"] }
        var date: String? { fields["date"] }
        var publicationTitle: String? { fields["publicationTitle"] }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawCodingKey.self)
            var f: [String: String] = [:]
            var c: [Creator] = []
            var t: [Tag] = []
            for key in container.allKeys {
                switch key.stringValue {
                case "creators":
                    c = (try? container.decode([Creator].self, forKey: key)) ?? []
                case "tags":
                    t = (try? container.decode([Tag].self, forKey: key)) ?? []
                case "collections", "relations":
                    continue  // skip non-scalar fields
                default:
                    if let s = try? container.decode(String.self, forKey: key) {
                        f[key.stringValue] = s
                    } else if let i = try? container.decode(Int.self, forKey: key) {
                        f[key.stringValue] = String(i)
                    } else if let b = try? container.decode(Bool.self, forKey: key) {
                        f[key.stringValue] = b ? "true" : "false"
                    }
                }
            }
            self.fields = f
            self.creators = c
            self.tags = t
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: RawCodingKey.self)
            for (k, v) in fields {
                try container.encode(v, forKey: RawCodingKey(stringValue: k)!)
            }
            try container.encode(creators, forKey: RawCodingKey(stringValue: "creators")!)
            try container.encode(tags, forKey: RawCodingKey(stringValue: "tags")!)
        }
    }

    struct Creator: Codable {
        let firstName: String?
        let lastName: String?
        let name: String?
        let creatorType: String?

        var displayName: String {
            if let name = name, !name.isEmpty { return name }
            return [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    struct Tag: Codable {
        let tag: String
    }

    private struct RawCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }
}

// MARK: - Library descriptor

struct Library {
    let id: String        // "users/0" or "groups/5973640"
    let name: String      // "My Library" or group name
    let zoteroURLBase: String  // "zotero://select/library" or "zotero://select/groups/5973640"
}

// MARK: - Zotero API Client

let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    return URLSession(configuration: config)
}()

func fetchGroups() -> [ZoteroGroup] {
    guard let url = URL(string: "http://localhost:\(activeConfig.apiPort)/api/users/0/groups?format=json") else { return [] }
    let sem = DispatchSemaphore(value: 0)
    var groups: [ZoteroGroup] = []
    session.dataTask(with: url) { data, _, error in
        defer { sem.signal() }
        guard let data = data, error == nil else { return }
        groups = (try? JSONDecoder().decode([ZoteroGroup].self, from: data)) ?? []
    }.resume()
    sem.wait()
    return groups
}

func fetchItems(library: Library, since sinceVersion: Int) -> (items: [ZoteroItem], libraryVersion: Int) {
    var all: [ZoteroItem] = []
    var start = 0
    let limit = 100
    var latestVersion = sinceVersion

    while true {
        var urlStr = "http://localhost:\(activeConfig.apiPort)/api/\(library.id)/items?start=\(start)&limit=\(limit)&format=json&itemType=-attachment%20%7C%7C%20-note"
        if sinceVersion > 0 {
            urlStr += "&since=\(sinceVersion)"
        }
        guard let url = URL(string: urlStr) else { break }

        let sem = DispatchSemaphore(value: 0)
        var page: [ZoteroItem] = []

        session.dataTask(with: url) { data, response, error in
            defer { sem.signal() }
            guard let data = data, error == nil else { return }
            if let http = response as? HTTPURLResponse,
               let vStr = http.value(forHTTPHeaderField: "Last-Modified-Version"),
               let v = Int(vStr) {
                latestVersion = v
            }
            page = (try? JSONDecoder().decode([ZoteroItem].self, from: data)) ?? []
        }.resume()
        sem.wait()

        if page.isEmpty { break }
        all.append(contentsOf: page)
        if page.count < limit { break }
        start += limit
    }
    return (all, latestVersion)
}

func fetchDeletedKeys(library: Library, since sinceVersion: Int) -> [String] {
    guard sinceVersion > 0 else { return [] }
    guard let url = URL(string: "http://localhost:\(activeConfig.apiPort)/api/\(library.id)/deleted?since=\(sinceVersion)&format=json") else { return [] }

    let sem = DispatchSemaphore(value: 0)
    var keys: [String] = []
    session.dataTask(with: url) { data, _, error in
        defer { sem.signal() }
        guard let data = data, error == nil else { return }
        if let json = try? JSONDecoder().decode([String: [String]].self, from: data) {
            keys = json["items"] ?? []
        }
    }.resume()
    sem.wait()
    return keys
}

// MARK: - Core Spotlight Indexing

private func loadIconThumbnail() -> Data? {
    let icon = NSWorkspace.shared.icon(forFile: "/Applications/Zotero.app")
    let size = NSSize(width: 64, height: 64)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Template Rendering
// Uses Zotero variable schema: https://www.zotero.org/support/file_renaming#variables
// Special computed variables: {{ authors }}, {{ editors }}, {{ creators }}, {{ firstCreator }},
// {{ year }}, {{ library }}
// All other {{ variableName }} tokens resolve directly from Zotero item data fields
// (title, publicationTitle, DOI, date, abstractNote, journalAbbreviation, etc.)

private func formatCreatorList(_ list: [ZoteroItem.Creator]) -> String {
    let names = list.map { $0.displayName }.filter { !$0.isEmpty }
    if names.isEmpty { return "" }
    if names.count <= 2 { return names.joined(separator: ", ") }
    return "\(names[0]) et al."
}

func renderTemplate(_ template: String, item: ZoteroItem, library: Library) -> String {
    let d = item.data

    // Pre-compute creator-based variables (Zotero schema)
    let authorCreators = d.creators.filter { $0.creatorType == "author" || $0.creatorType == nil }
    let editorCreators = d.creators.filter { $0.creatorType == "editor" }

    // Computed variables that don't come directly from item fields
    let computed: [String: String] = [
        "authors":       formatCreatorList(authorCreators),
        "editors":       formatCreatorList(editorCreators),
        "creators":      formatCreatorList(d.creators),
        "firstCreator":  formatCreatorList(Array(d.creators.prefix(2))),
        "authorsCount":  String(authorCreators.count),
        "editorsCount":  String(editorCreators.count),
        "creatorsCount": String(d.creators.count),
        "year": {
            guard let date = d.date, !date.isEmpty else { return "" }
            return String(date.prefix(4))
        }(),
        "library": library.name,
    ]

    // Resolve {{ variable }} tokens via regex
    let regex = try! NSRegularExpression(pattern: "\\{\\{\\s*(\\w+)\\s*\\}\\}")
    let nsTemplate = template as NSString
    let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsTemplate.length))

    var result = template
    // Replace in reverse order to preserve ranges
    for match in matches.reversed() {
        let fullRange = Range(match.range, in: template)!
        let varRange = Range(match.range(at: 1), in: template)!
        let varName = String(template[varRange])

        let value: String
        if let v = computed[varName] {
            value = v
        } else if let v = d.fields[varName], !v.isEmpty {
            value = v
        } else {
            value = ""
        }
        result = result.replacingCharacters(in: fullRange, with: value)
    }

    // Remove segments that became empty after token substitution (handles " · " separators)
    return result
        .components(separatedBy: " · ").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .joined(separator: " · ")
        .trimmingCharacters(in: .whitespaces)
}

func indexItems(_ items: [ZoteroItem], library: Library, iconData: Data?) {
    guard !items.isEmpty else { return }
    let domainID = "com.zotlight.app"
    var searchableItems: [CSSearchableItem] = []

    for item in items {
        let d = item.data
        guard d.itemType != "attachment", d.itemType != "note" else { continue }

        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = renderTemplate(activeConfig.titleTemplate, item: item, library: library)
        attrs.contentDescription = renderTemplate(activeConfig.descriptionTemplate, item: item, library: library)
        attrs.thumbnailData = iconData

        var keywords: [String] = [library.name]  // include library name for searchability
        keywords.append(contentsOf: d.creators.map { $0.displayName }.filter { !$0.isEmpty })
        keywords.append(contentsOf: d.tags.map { $0.tag })
        if let pub = d.publicationTitle, !pub.isEmpty { keywords.append(pub) }
        keywords.append(d.itemType)
        attrs.keywords = keywords

        if let date = d.date, !date.isEmpty {
            attrs.contentCreationDate = parseDate(date)
        }
        attrs.contentURL = URL(string: "\(library.zoteroURLBase)/items/\(d.key)")

        // Unique identifier includes library prefix to avoid key collisions across libraries
        searchableItems.append(CSSearchableItem(
            uniqueIdentifier: "\(domainID).\(library.id).\(d.key)",
            domainIdentifier: domainID,
            attributeSet: attrs
        ))
    }

    let sem = DispatchSemaphore(value: 0)
    CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
        if let error = error {
            fputs("Spotlight index error: \(error.localizedDescription)\n", stderr)
        }
        sem.signal()
    }
    sem.wait()
}

func removeItems(keys: [String], library: Library) {
    guard !keys.isEmpty else { return }
    let domainID = "com.zotlight.app"
    let identifiers = keys.map { "\(domainID).\(library.id).\($0)" }

    let sem = DispatchSemaphore(value: 0)
    CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { error in
        if let error = error {
            fputs("Spotlight delete error: \(error.localizedDescription)\n", stderr)
        }
        sem.signal()
    }
    sem.wait()
}

func parseDate(_ str: String) -> Date? {
    let fmts = ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    for fmt in fmts {
        df.dateFormat = fmt
        if let d = df.date(from: String(str.prefix(fmt.count))) { return d }
    }
    return nil
}

// MARK: - Sync

func syncLibrary(_ library: Library, iconData: Data?) {
    let lastVersion = loadLastVersion(for: library.id.replacingOccurrences(of: "/", with: "_"))
    let isIncremental = lastVersion > 0

    print("[\(library.name)] \(isIncremental ? "Incremental sync since v\(lastVersion)" : "Full sync")...")

    let (items, newVersion) = fetchItems(library: library, since: lastVersion)
    let deletedKeys = fetchDeletedKeys(library: library, since: lastVersion)

    if items.isEmpty && deletedKeys.isEmpty {
        print("[\(library.name)] Nothing changed.")
        saveVersion(newVersion, for: library.id.replacingOccurrences(of: "/", with: "_"))
        return
    }

    if !items.isEmpty {
        print("[\(library.name)] Indexing \(items.count) new/updated item(s)...")
        indexItems(items, library: library, iconData: iconData)
    }
    if !deletedKeys.isEmpty {
        print("[\(library.name)] Removing \(deletedKeys.count) deleted item(s)...")
        removeItems(keys: deletedKeys, library: library)
    }

    saveVersion(newVersion, for: library.id.replacingOccurrences(of: "/", with: "_"))
    print("[\(library.name)] Done. Library version: \(newVersion)")
}

func runSync() {
    activeConfig = Config.load() // always fresh at sync time
    let iconData = loadIconThumbnail()

    // Personal library
    let personalLib = Library(
        id: "users/0",
        name: "My Library",
        zoteroURLBase: "zotero://select/library"
    )
    if activeConfig.excludedLibraries.contains("users/0") {
        print("[My Library] Excluded — skipping.")
    } else {
        syncLibrary(personalLib, iconData: iconData)
    }

    // Group libraries
    let groups = fetchGroups()
    for group in groups {
        let libID = "groups/\(group.id)"
        if activeConfig.excludedLibraries.contains(libID) {
            print("[\(group.data.name)] Excluded — skipping.")
            continue
        }
        let lib = Library(
            id: libID,
            name: group.data.name,
            zoteroURLBase: "zotero://select/groups/\(group.id)"
        )
        syncLibrary(lib, iconData: iconData)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsController: SettingsWindowController?
    private var handledSpotlight = false

    func application(_ application: NSApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return false }

        handledSpotlight = true

        // identifier = "com.zotlight.app.users/0.KEY"
        //           or "com.zotlight.app.groups/5973640.KEY"
        // Extract the zotero:// URL by re-parsing the identifier
        let prefix = "com.zotlight.app."
        guard identifier.hasPrefix(prefix) else { return false }
        let rest = String(identifier.dropFirst(prefix.count))  // "users/0.KEY" or "groups/5973640.KEY"

        guard let dotRange = rest.range(of: ".", options: .backwards) else { return false }
        let libraryPath = String(rest[rest.startIndex..<dotRange.lowerBound])  // "users/0" or "groups/5973640"
        let key = String(rest[dotRange.upperBound...])

        let clickConfig = Config.load()
        let action = clickConfig.openOnClick ? "open-pdf" : "select"

        let zoteroURL: String
        if libraryPath == "users/0" {
            zoteroURL = "zotero://\(action)/library/items/\(key)"
        } else {
            // libraryPath = "groups/5973640"
            let groupID = libraryPath.replacingOccurrences(of: "groups/", with: "")
            zoteroURL = "zotero://\(action)/groups/\(groupID)/items/\(key)"
        }

        guard let url = URL(string: zoteroURL) else { return false }
        NSWorkspace.shared.open(url)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    private func showSettings() {
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        NSApp.activate(ignoringOtherApps: true)
        let controller = SettingsWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        settingsController = controller
    }

    private func installEditMenu() {
        let mainMenu = NSMenu()

        // App menu (required first item)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ZotLight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu with standard shortcuts
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments

        // --clear: wipe Spotlight index and version state, then quit
        if args.contains("--clear") {
            clearSpotlightIndex()
            clearVersionState()
            NSApplication.shared.terminate(nil)
            return
        }

        // --reset: restore default config, wipe index and version state, then quit
        if args.contains("--reset") {
            Config.defaults.save()
            clearSpotlightIndex()
            clearVersionState()
            print("Reset complete. Run with --sync to re-index.")
            NSApplication.shared.terminate(nil)
            return
        }

        // --notify <title> <body>: post a system notification then quit
        if let notifyIdx = args.firstIndex(of: "--notify") {
            let notifTitle = args.count > notifyIdx + 1 ? args[notifyIdx + 1] : "ZotLight"
            let notifBody  = args.count > notifyIdx + 2 ? args[notifyIdx + 2] : ""
            DispatchQueue.global().async {
                let center = UNUserNotificationCenter.current()
                let sem = DispatchSemaphore(value: 0)
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    guard granted else { sem.signal(); return }
                    let content = UNMutableNotificationContent()
                    content.title = notifTitle
                    content.body  = notifBody
                    let req = UNNotificationRequest(identifier: UUID().uuidString,
                                                    content: content, trigger: nil)
                    center.add(req) { _ in sem.signal() }
                }
                sem.wait()
                Thread.sleep(forTimeInterval: 0.5)
                NSApplication.shared.terminate(nil)
            }
            return
        }

        // --sync (from LaunchAgent or CLI): run sync silently then quit
        if args.contains("--sync") {
            if args.contains("--full") {
                clearVersionState()
            }
            DispatchQueue.global().async {
                runSync()
                NSApplication.shared.terminate(nil)
            }
            return
        }

        // No CLI flag → either a Spotlight click or user double-click.
        // Defer showing settings briefly: if Spotlight delivers a
        // NSUserActivity, the handler will fire first and terminate the app.
        // If no activity arrives, this is a normal launch → show settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !self.handledSpotlight else { return }
            self.showSettings()
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
