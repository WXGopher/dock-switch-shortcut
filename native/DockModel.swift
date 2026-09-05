import Cocoa

struct DockApp: Equatable {
    let name: String
    let bundleID: String
    let url: URL?
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

    static func read() throws -> [DockApp] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return apps(from: plist)
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
