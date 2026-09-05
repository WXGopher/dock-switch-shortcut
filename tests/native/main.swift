import Cocoa

var passed = 0

func check(_ description: String, _ body: () throws -> Void) {
    do {
        try body()
        passed += 1
        print("PASS \(description)")
    } catch {
        fputs("FAIL \(description): \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw AppError(message) }
}

func tile(_ name: String, _ bundleID: String, url: String = "file:///Applications/Example.app/") -> [String: Any] {
    ["tile-data": ["file-label": name, "bundle-identifier": bundleID, "file-data": ["_CFURLString": url]]]
}

check("Dock mapping preserves order and excludes Finder, spacers, and recent apps") {
    let preferences: [String: Any] = [
        "persistent-apps": [
            tile("Renamed Finder", "com.apple.finder"),
            tile("Safari", "com.apple.Safari"),
            ["tile-type": "spacer-tile"],
            "invalid",
            tile("Terminal", "com.apple.Terminal"),
        ],
        "recent-apps": [tile("Preview", "com.apple.Preview")],
    ]
    try expect(DockModel.apps(from: preferences).map(\.name) == ["Safari", "Terminal"], "Incorrect mapping order")
}

check("Special characters and missing icon URLs do not shift mapping") {
    let name = "Editor \"A&B\"; Tools"
    let preferences: [String: Any] = ["persistent-apps": [
        tile(name, "example.first", url: "https://example.com/app"),
        tile("Second", "example.second", url: "file:///Applications/Second%20App.app/"),
    ]]
    let apps = DockModel.apps(from: preferences)
    try expect(apps.count == 2 && apps[0].name == name && apps[0].url == nil, "Invalid icon changed mapping")
    try expect(apps[1].url?.path == "/Applications/Second App.app", "File URL not decoded")
}

check("Malformed Dock preferences are handled without crashing") {
    for value: Any in [[], [:], ["persistent-apps": "invalid"], ["persistent-apps": [NSNull(), [:]]]] {
        try expect(DockModel.apps(from: value).isEmpty, "Malformed preferences accepted")
    }
}

check("All ten physical number keys map correctly; modifiers and keypad pass through") {
    for (index, key) in [18, 19, 20, 21, 23, 22, 26, 28, 25, 29].enumerated() {
        try expect(DockShortcut.index(keyCode: Int64(key), flags: .maskCommand) == index, "Wrong numeric mapping")
        for flags: CGEventFlags in [[], .maskShift, [.maskCommand, .maskShift], [.maskCommand, .maskAlternate], [.maskCommand, .maskControl]] {
            try expect(DockShortcut.index(keyCode: Int64(key), flags: flags) == nil, "Unexpected modifier interception")
        }
    }
    try expect(DockShortcut.label(for: 9) == "⌘0", "Tenth shortcut must use zero")
    try expect(DockShortcut.index(keyCode: 83, flags: .maskCommand) == nil, "Numeric keypad intercepted")
    try expect(DockShortcut.index(keyCode: 18, flags: [.maskCommand, .maskAlphaShift]) == 0, "Caps Lock changed shortcut")
}

check("Integration accepts only the four documented commands") {
    for command in IntegrationCommand.allCases {
        try expect(IntegrationCommand(url: URL(string: "dockswitcher://\(command.rawValue)")!) == command, "Known command rejected")
    }
    for value in ["https://enable", "dockswitcher://quit", "dockswitcher://enable/shell", "dockswitcher://enable?command=anything", "dockswitcher://user@enable", "dockswitcher://enable:123", "dockswitcher://enable#fragment"] {
        try expect(IntegrationCommand(url: URL(string: value)!) == nil, "Unsupported URL accepted")
    }
}

check("Legacy migration is idempotent when the old helper is absent") {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let helper = LegacyHelper(home: temporary, uid: 501) { _, arguments in
        try expect(arguments == ["list", LegacyHelper.label], "Unexpected service mutation")
        return ToolResult(status: 113, output: "")
    }
    let installed = try helper.isInstalled()
    try expect(!installed, "Missing helper reported installed")
    try helper.stopAndDisable()
}

check("Legacy migration preserves the plist when unloading fails") {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let helper = LegacyHelper(home: temporary, uid: 501) { _, arguments in
        ToolResult(status: arguments.first == "bootout" ? 5 : 0, output: "service is still loaded")
    }
    try FileManager.default.createDirectory(at: helper.plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Data("fixture".utf8).write(to: helper.plistURL)
    var failed = false
    do { try helper.stopAndDisable() } catch { failed = true }
    try expect(failed, "Unload failure was hidden")
    try expect(FileManager.default.fileExists(atPath: helper.plistURL.path), "Plist removed despite failed unload")
}

check("Legacy migration removes only its plist after verified unload") {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var loaded = true
    let helper = LegacyHelper(home: temporary, uid: 501) { executable, arguments in
        try expect(executable == "/bin/launchctl", "Unexpected executable")
        if arguments.first == "bootout" {
            try expect(arguments == ["bootout", "gui/501/\(LegacyHelper.label)"], "Wrong service targeted")
            loaded = false
            return ToolResult(status: 0, output: "")
        }
        return ToolResult(status: loaded ? 0 : 113, output: "")
    }
    try FileManager.default.createDirectory(at: helper.plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Data("fixture".utf8).write(to: helper.plistURL)
    let neighbor = helper.plistURL.deletingLastPathComponent().appendingPathComponent("unrelated.plist")
    try Data("keep".utf8).write(to: neighbor)
    try helper.stopAndDisable()
    try expect(!FileManager.default.fileExists(atPath: helper.plistURL.path), "Old plist remains")
    try expect(FileManager.default.fileExists(atPath: neighbor.path), "Unrelated file changed")
}

check("Legacy status errors are not interpreted as an absent helper") {
    let helper = LegacyHelper(home: URL(fileURLWithPath: "/example"), uid: 501) { _, _ in
        ToolResult(status: 5, output: "query failed")
    }
    var failed = false
    do { _ = try helper.isLoaded() } catch { failed = true }
    try expect(failed, "Unexpected launchctl failure hidden")
}

print("\(passed) native checks passed. No real services or permissions were changed.")
