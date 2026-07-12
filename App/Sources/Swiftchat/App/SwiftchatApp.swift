import AppKit
import SwiftUI

@main
struct SwiftchatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Swiftchat", id: "main") {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .task { await model.start() }
        }
        .defaultSize(width: 1_280, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { SwiftchatCommands() }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
