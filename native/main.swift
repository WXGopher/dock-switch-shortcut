import Cocoa

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--version"] {
    print("Dock Switcher 0.2.0")
    exit(0)
}
if arguments == ["--help"] {
    print("""
    Dock Switcher — your Dock, one shortcut away.

    Open Dock Switcher.app to use the menu bar controls.
    --version   Print the version without starting the app.
    --help      Show this help without starting the app.

    Optional integration: dockswitcher://enable, disable, mapping, settings
    Enable Allow Raycast Control in the app before using integration URLs.
    """)
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
