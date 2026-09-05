import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = ShortcutEngine()
    private let preferences = UserDefaults.standard
    private let legacy = LegacyHelper(home: FileManager.default.homeDirectoryForCurrentUser, uid: getuid())
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var mappingMenu = NSMenu()
    private var lastError: String?
    private var handlingURL = false
    private var didLaunch = false
    private var pendingURLs: [URL] = []

    private var enabled: Bool {
        get { preferences.bool(forKey: "shortcutsEnabled") }
        set { preferences.set(newValue, forKey: "shortcutsEnabled") }
    }

    private var allowsRaycast: Bool {
        get { preferences.bool(forKey: "allowRaycastControl") }
        set { preferences.set(newValue, forKey: "allowRaycastControl") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Dock Switcher")
            button.toolTip = "Dock Switcher"
        }
        menu.delegate = self
        statusItem.menu = menu
        engine.onFailure = { [weak self] message in self?.lastError = message }
        restoreShortcuts()
        rebuildMenu()
        didLaunch = true
        let firstLaunch = !preferences.bool(forKey: "hasLaunched")
        preferences.set(true, forKey: "hasLaunched")

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            DispatchQueue.main.async { [weak self] in self?.application(NSApp, open: urls) }
        } else if firstLaunch {
            DispatchQueue.main.async { [weak self] in self?.presentMenu() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentMenu()
        return false
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            restoreShortcuts()
            rebuildMenu()
        }
    }

    private func restoreShortcuts() {
        guard enabled, !engine.isRunning else { return }
        do {
            guard try !legacy.isInstalled() else {
                lastError = "Previous Raycast helper found. Enable shortcuts to migrate."
                return
            }
            if AXIsProcessTrusted() { _ = engine.start() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func addItem(_ title: String, action: Selector? = nil, checked: Bool? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let checked { item.state = checked ? .on : .off }
        menu.addItem(item)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        addItem("Dock Switcher")
        addItem(engine.isRunning ? "Shortcuts are on" : "Shortcuts are paused")
        if enabled && !AXIsProcessTrusted() { addItem("Accessibility permission needed") }
        if let lastError {
            let item = NSMenuItem(title: "View Last Error…", action: #selector(showLastError), keyEquivalent: "")
            item.target = self
            item.toolTip = lastError
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addItem("Enable Dock Shortcuts", action: #selector(toggleShortcuts), checked: enabled)

        rebuildMapping()
        let mapping = NSMenuItem(title: "Current Mapping", action: nil, keyEquivalent: "")
        mapping.submenu = mappingMenu
        menu.addItem(mapping)

        menu.addItem(.separator())
        let loginStatus = SMAppService.mainApp.status
        addItem("Launch at Login", action: #selector(toggleLogin), checked: loginStatus == .enabled || loginStatus == .requiresApproval)
        if loginStatus == .requiresApproval {
            addItem("Approve in Login Items…", action: #selector(openLoginSettings))
        }
        addItem("Allow Raycast Control", action: #selector(toggleRaycast), checked: allowsRaycast)
        menu.items.last?.toolTip = "Accept local dockswitcher:// links, including requests from Raycast."
        addItem("Accessibility Permission…", action: #selector(openAccessibility))
        menu.addItem(.separator())
        addItem("Quit Dock Switcher", action: #selector(quit))
        statusItem.button?.appearsDisabled = !engine.isRunning
    }

    private func rebuildMapping() {
        mappingMenu = NSMenu(title: "Current Mapping")
        do {
            let apps = Array(try DockModel.read().prefix(10))
            if apps.isEmpty {
                mappingMenu.addItem(NSMenuItem(title: "Pin apps to your Dock to get started", action: nil, keyEquivalent: ""))
            }
            for (index, app) in apps.enumerated() {
                let item = NSMenuItem(title: "\(DockShortcut.label(for: index))  \(app.name)", action: nil, keyEquivalent: "")
                if let url = app.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                    let image = NSWorkspace.shared.icon(forFile: url.path)
                    image.size = NSSize(width: 16, height: 16)
                    item.image = image
                }
                mappingMenu.addItem(item)
            }
            mappingMenu.addItem(.separator())
            mappingMenu.addItem(NSMenuItem(title: "Pinned apps · Finder skipped", action: nil, keyEquivalent: ""))
        } catch {
            mappingMenu.addItem(NSMenuItem(title: "Could not read Dock preferences", action: nil, keyEquivalent: ""))
            lastError = error.localizedDescription
        }
    }

    @objc private func toggleShortcuts() {
        if enabled {
            enabled = false
            engine.stop()
            lastError = nil
        } else {
            enableShortcuts()
        }
        rebuildMenu()
    }

    private func enableShortcuts() {
        do {
            if try legacy.isInstalled() {
                let alert = NSAlert()
                alert.messageText = "Replace the previous Raycast helper?"
                alert.informativeText = "Dock Switcher now runs as a standalone app. Stop the old helper and remove its login entry before enabling shortcuts here."
                alert.addButton(withTitle: "Stop Old Helper")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                try legacy.stopAndDisable()
            }
        } catch {
            showError(error.localizedDescription)
            return
        }

        enabled = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            showMessage("Allow Dock Switcher in Accessibility", "Open System Settings → Privacy & Security → Accessibility and enable Dock Switcher. Then reopen this menu. Shortcuts are paused until permission is granted. They replace app shortcuts such as browser tab selection.")
            openAccessibility()
            return
        }
        if engine.start() {
            lastError = nil
        } else {
            showError("Could not enable keyboard shortcuts. Check Accessibility permission, then try again.")
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { openLoginSettings() }
            }
        } catch {
            showError("Could not change Launch at Login. Move Dock Switcher to Applications and try again. \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    @objc private func toggleRaycast() {
        allowsRaycast.toggle()
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func showLastError() {
        if let lastError { showMessage("Dock Switcher", lastError) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func showError(_ message: String) {
        lastError = message
        showMessage("Dock Switcher", message)
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentMenu() {
        guard statusItem != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        statusItem.button?.performClick(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard didLaunch else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        guard !handlingURL else { return }
        handlingURL = true
        defer { handlingURL = false }
        for url in urls {
            guard let command = IntegrationCommand(url: url) else { continue }
            guard allowsRaycast else {
                showMessage("Raycast control is off", "Enable Allow Raycast Control in the Dock Switcher menu to accept these requests. The app works independently of Raycast.")
                presentMenu()
                return
            }
            switch command {
            case .enable:
                enableShortcuts()
                rebuildMenu()
            case .disable:
                enabled = false
                engine.stop()
                lastError = nil
                rebuildMenu()
            case .mapping:
                rebuildMapping()
                NSApp.activate(ignoringOtherApps: true)
                mappingMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: statusItem.button)
            case .settings:
                presentMenu()
            }
        }
    }
}
