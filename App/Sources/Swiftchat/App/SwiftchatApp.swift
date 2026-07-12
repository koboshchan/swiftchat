import AppKit
import SwiftUI

@main
struct SwiftchatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let useDemoData = arguments.contains("--demo")
            || arguments.contains("--demo-voice")
            || arguments.contains("--demo-voice-page")
        _model = State(initialValue: AppModel(restoreStoredSession: !useDemoData))
    }

    var body: some Scene {
        WindowGroup("Swiftchat", id: "main") {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    await model.start()
                    let arguments = ProcessInfo.processInfo.arguments
                    if (arguments.contains("--demo-voice") || arguments.contains("--demo-voice-page")),
                       let channel = model.visibleChannels.first(where: { $0.kind == .voice }) {
                        model.selectedChannelID = channel.id
                        if arguments.contains("--demo-voice") { await model.joinVoice(channel) }
                    }
                }
        }
        .defaultSize(width: 1_280, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { SwiftchatCommands() }

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
