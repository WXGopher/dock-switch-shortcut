import Foundation

struct ToolResult {
    let status: Int32
    let output: String
}

func runTool(_ executable: String, _ arguments: [String]) throws -> ToolResult {
    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return ToolResult(status: task.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

struct LegacyHelper {
    static let label = "com.raycast.dock-switcher"
    let home: URL
    let uid: UInt32
    var run: (String, [String]) throws -> ToolResult = runTool

    var plistURL: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    func isLoaded() throws -> Bool {
        let result = try run("/bin/launchctl", ["list", Self.label])
        if result.status == 113 { return false }
        guard result.status == 0 else {
            throw AppError("Could not check the previous Dock Switcher helper. \(result.output)")
        }
        return true
    }

    func isInstalled() throws -> Bool {
        let loaded = try isLoaded()
        return loaded || FileManager.default.fileExists(atPath: plistURL.path)
    }

    func stopAndDisable() throws {
        if try isLoaded() {
            let result = try run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Self.label)"])
            let stillLoaded = try isLoaded()
            guard !stillLoaded else {
                throw AppError("The previous helper could not be stopped. \(result.output)")
            }
        }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
