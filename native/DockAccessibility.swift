import Cocoa

enum DockAccessibility {
    static func items() throws -> [DockItem] {
        guard AXIsProcessTrusted() else {
            throw AppError("Allow Dock Switcher in System Settings → Privacy & Security → Accessibility to include running apps. Then choose Remap Dock Apps.")
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw AppError("The Dock is not running. Try Remap Dock Apps when it is available.")
        }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let children = try value(kAXChildrenAttribute, of: application) as? [AXUIElement] else {
            throw unreadableDock()
        }
        var list: AXUIElement?
        for child in children {
            if try value(kAXRoleAttribute, of: child) as? String == kAXListRole {
                list = child
                break
            }
        }
        guard let list,
              let elements = try value(kAXChildrenAttribute, of: list) as? [AXUIElement] else {
            throw unreadableDock()
        }

        return try elements.compactMap { element in
            guard try value(kAXSubroleAttribute, of: element) as? String == kAXApplicationDockItemSubrole else { return nil }
            guard let url = try value(kAXURLAttribute, of: element) as? URL,
                  url.isFileURL,
                  let bundleID = Bundle(url: url)?.bundleIdentifier else {
                throw unreadableDock()
            }
            let name = try value(kAXTitleAttribute, of: element) as? String ?? url.deletingPathExtension().lastPathComponent
            guard let isRunning = try value(kAXIsApplicationRunningAttribute, of: element) as? Bool else {
                throw unreadableDock()
            }
            return DockItem(app: DockApp(name: name, bundleID: bundleID, url: url), isRunning: isRunning)
        }
    }

    private static func value(_ attribute: String, of element: AXUIElement) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        switch result {
        case .success:
            return value
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw unreadableDock()
        }
    }

    private static func unreadableDock() -> AppError {
        AppError("Could not read the current Dock order. Check Accessibility permission, then try Remap Dock Apps again.")
    }
}
