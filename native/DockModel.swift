import Cocoa

struct DockApp: Equatable {
    let name: String
    let bundleID: String
    let url: URL?
}

struct DockItem {
    let app: DockApp
    let isRunning: Bool
}

enum DockModel {
    static func apps(from preferences: Any) -> [DockApp] {
        guard let dictionary = preferences as? [String: Any],
              let tiles = dictionary["persistent-apps"] as? [Any] else { return [] }

        return tiles.compactMap { tile in
            guard let tile = tile as? [String: Any],
                  let data = tile["tile-data"] as? [String: Any],
                  let name = data["file-label"] as? String,
                  let bundleID = data["bundle-identifier"] as? String,
                  !name.isEmpty, !bundleID.isEmpty,
                  name != "Finder", bundleID != "com.apple.finder" else { return nil }

            let fileData = data["file-data"] as? [String: Any]
            let url = (fileData?["_CFURLString"] as? String).flatMap(URL.init(string:))
            return DockApp(name: name, bundleID: bundleID, url: url?.isFileURL == true ? url : nil)
        }
    }

    static func apps(from items: [DockItem], pinnedApps: [DockApp]) -> [DockApp] {
        let pinnedIDs = Set(pinnedApps.map(\.bundleID))
        var seen = Set<String>()
        return items.compactMap { item in
            let app = item.app
            guard app.bundleID != "com.apple.finder",
                  item.isRunning || pinnedIDs.contains(app.bundleID),
                  seen.insert(app.bundleID).inserted else { return nil }
            return app
        }
    }

    static func read(includeRunningApps: Bool = false, applicationID: CFString = "com.apple.dock" as CFString) throws -> [DockApp] {
        let pinnedApps = try readPinnedApps(applicationID: applicationID)
        guard includeRunningApps else { return pinnedApps }
        return apps(from: try DockAccessibility.items(), pinnedApps: pinnedApps)
    }

    private static func readPinnedApps(applicationID: CFString) throws -> [DockApp] {
        // Dock changes go through the preferences service. The on-disk plist can
        // lag behind it, and this process may already have cached an older value.
        guard CFPreferencesSynchronize(applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw AppError("Could not refresh Dock preferences. Try Remap Dock Apps again.")
        }
        guard let value = CFPreferencesCopyValue(
            "persistent-apps" as CFString, applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) else { return [] }
        guard let tiles = value as? [Any] else {
            throw AppError("The Dock app list could not be read. Try Remap Dock Apps again.")
        }
        return apps(from: ["persistent-apps": tiles])
    }
}

enum DockShortcut {
    static let keyCodes: [Int64: Int] = [
        18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
        22: 5, 26: 6, 28: 7, 25: 8, 29: 9,
    ]

    static func index(keyCode: Int64, flags: CGEventFlags) -> Int? {
        guard flags.contains(.maskCommand),
              flags.intersection([.maskShift, .maskAlternate, .maskControl]).isEmpty else { return nil }
        return keyCodes[keyCode]
    }

    static func label(for index: Int) -> String {
        "⌘\(index == 9 ? 0 : index + 1)"
    }
}

enum IntegrationCommand: String, CaseIterable {
    case enable, disable, mapping, settings

    init?(url: URL) {
        guard url.scheme?.lowercased() == "dockswitcher",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let host = url.host,
              let command = Self(rawValue: host) else { return nil }
        self = command
    }
}
