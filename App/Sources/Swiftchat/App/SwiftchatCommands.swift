import SwiftUI

struct SwiftchatCommands: Commands {
    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Quick Switcher") { NotificationCenter.default.post(name: .swiftchatQuickSwitcher, object: nil) }
                .keyboardShortcut("k")
            Button("Toggle Member Inspector") { NotificationCenter.default.post(name: .swiftchatToggleInspector, object: nil) }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Focus Composer") { NotificationCenter.default.post(name: .swiftchatFocusComposer, object: nil) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

