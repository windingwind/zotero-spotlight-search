// ZotLight/Config.swift
// Configuration model, persistence, export/import, and LaunchAgent management.

import Foundation
import AppKit

// MARK: - Paths

enum ConfigPaths {
    static let configDir  = NSHomeDirectory() + "/.config/zotlight"
    static let configFile = configDir + "/config.json"

    static let launchAgentDir   = NSHomeDirectory() + "/Library/LaunchAgents"
    static let launchAgentLabel = "com.zotlight.app"
    static let launchAgentPlist = launchAgentDir + "/" + launchAgentLabel + ".plist"
    static let appBinary        = "/Applications/ZotLight.app/Contents/MacOS/ZotLight"
}

// MARK: - Config Model

struct Config: Codable {
    var apiPort: Int
    var excludedLibraries: [String]
    var autoSyncEnabled: Bool      // false = plugin-triggered only; true = timer-based
    var syncIntervalMinutes: Int
    var autoStartOnLogin: Bool
    var titleTemplate: String
    var descriptionTemplate: String
    var openOnClick: Bool      // true = open item (PDF), false = select in library

    static let defaults = Config(
        apiPort: 23119,
        excludedLibraries: [],
        autoSyncEnabled: false,
        syncIntervalMinutes: 10,
        autoStartOnLogin: false,
        titleTemplate: "{{ title }}",
        descriptionTemplate: "{{ authors }} · {{ publicationTitle }} · {{ year }}",
        openOnClick: false
    )
}

// MARK: - Backward-compatible decoding
// Allows loading old config files that predate optional fields (autoSyncEnabled, openOnClick).

extension Config {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiPort             = try c.decode(Int.self, forKey: .apiPort)
        excludedLibraries   = try c.decode([String].self, forKey: .excludedLibraries)
        autoSyncEnabled     = try c.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? false
        syncIntervalMinutes = try c.decode(Int.self, forKey: .syncIntervalMinutes)
        autoStartOnLogin    = try c.decode(Bool.self, forKey: .autoStartOnLogin)
        titleTemplate       = try c.decode(String.self, forKey: .titleTemplate)
        descriptionTemplate = try c.decode(String.self, forKey: .descriptionTemplate)
        openOnClick         = try c.decodeIfPresent(Bool.self, forKey: .openOnClick) ?? false
    }
}

// MARK: - Persistence

extension Config {

    static func load() -> Config {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: ConfigPaths.configFile)),
              let decoded = try? JSONDecoder().decode(Config.self, from: data)
        else { return .defaults }
        return decoded
    }

    func save() {
        try? FileManager.default.createDirectory(
            atPath: ConfigPaths.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: URL(fileURLWithPath: ConfigPaths.configFile), options: .atomic)
    }
}

// MARK: - Export / Import

extension Config {

    func exportToFile(relativeTo window: NSWindow?) {
        save() // ensure disk is current before exporting
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "zotlight-config.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let src = URL(fileURLWithPath: ConfigPaths.configFile)
        try? FileManager.default.copyItem(at: src, to: dest)
    }

    static func importFromFile(relativeTo window: NSWindow?) -> Config? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a ZotLight config.json to import"
        guard panel.runModal() == .OK,
              let src = panel.url,
              let data = try? Data(contentsOf: src),
              let decoded = try? JSONDecoder().decode(Config.self, from: data)
        else { return nil }
        return decoded
    }
}

// MARK: - LaunchAgent

extension Config {

    func launchAgentXML() -> String {
        let intervalKey = autoSyncEnabled ? """

            <key>StartInterval</key>
            <integer>\(syncIntervalMinutes * 60)</integer>
        """ : ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(ConfigPaths.launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(ConfigPaths.appBinary)</string>
                <string>--sync</string>
            </array>\(intervalKey)
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/tmp/ZotLight.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/ZotLight.err</string>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
    }

    static func isLaunchAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: ConfigPaths.launchAgentPlist)
    }

    func installLaunchAgent() {
        try? FileManager.default.createDirectory(
            atPath: ConfigPaths.launchAgentDir, withIntermediateDirectories: true)
        try? launchAgentXML().write(
            toFile: ConfigPaths.launchAgentPlist, atomically: true, encoding: .utf8)
        Config.runLaunchctl(["load", ConfigPaths.launchAgentPlist])
    }

    static func removeLaunchAgent() {
        if isLaunchAgentInstalled() {
            runLaunchctl(["unload", ConfigPaths.launchAgentPlist])
        }
        try? FileManager.default.removeItem(atPath: ConfigPaths.launchAgentPlist)
    }

    @discardableResult
    static func runLaunchctl(_ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }
}
