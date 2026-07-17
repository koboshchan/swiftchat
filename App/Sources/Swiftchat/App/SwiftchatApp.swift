import AppKit
import DiscordProtocol
import SwiftUI

@main
struct SwiftchatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    private let launchConfiguration: AppLaunchConfiguration

    init() {
        let configuration = AppLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
        launchConfiguration = configuration
        let provider: (any ChatProvider)? = configuration.mode == .offlineTesting
            ? MockChatProvider(includesLongServerList: configuration.includesLongServerList)
            : nil
        _model = State(initialValue: AppModel(
            launchMode: configuration.mode,
            provider: provider
        ))
    }

    var body: some Scene {
        WindowGroup("Swiftchat", id: "main") {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    await model.start()
                    if launchConfiguration.opensVoiceChannel,
                       let channel = model.visibleChannels.first(where: { $0.kind == .voice }) {
                        model.selectedChannelID = channel.id
                        if launchConfiguration.joinsVoiceChannel { await model.joinVoice(channel) }
                    }
                }
        }
        .defaultSize(width: 1_280, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowBackgroundDragBehavior(.disabled)
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
