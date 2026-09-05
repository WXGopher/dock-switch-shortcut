import Cocoa

final class ShortcutEngine {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onFailure: ((String) -> Void)?

    var isRunning: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func start() -> Bool {
        if isRunning { return true }
        stop()
        guard AXIsProcessTrusted() else { return false }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<ShortcutEngine>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = engine.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown,
                  let index = DockShortcut.index(
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags
                  ) else { return Unmanaged.passUnretained(event) }

            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                engine.activateApp(at: index)
            }
            // Preserve the original behavior: all ten shortcuts are reserved.
            return nil
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else { return false }

        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }

    private func activateApp(at index: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let apps = try DockModel.read()
                guard apps.indices.contains(index) else { return }
                let app = apps[index]
                DispatchQueue.main.async { [weak self] in
                    guard self?.isRunning == true else { return }
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) ?? app.url else {
                        self?.onFailure?("Could not find \(app.name). Re-add it to your Dock.")
                        return
                    }
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                        if let error {
                            DispatchQueue.main.async { self?.onFailure?(error.localizedDescription) }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { self?.onFailure?("Could not read Dock preferences: \(error.localizedDescription)") }
            }
        }
    }

    deinit { stop() }
}
