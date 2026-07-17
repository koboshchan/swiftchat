import Foundation

nonisolated enum AppLaunchMode: Equatable, Sendable {
    case normal
    case offlineTesting
}

nonisolated struct AppLaunchConfiguration: Equatable, Sendable {
    let mode: AppLaunchMode
    let includesLongServerList: Bool
    let opensVoiceChannel: Bool
    let joinsVoiceChannel: Bool

    init(arguments: [String]) {
        includesLongServerList = arguments.contains("--demo-long-server-list")
        opensVoiceChannel = arguments.contains("--demo-voice")
            || arguments.contains("--demo-voice-page")
        joinsVoiceChannel = arguments.contains("--demo-voice")

        let testingFlags: Set = [
            "--offline",
            "--demo",
            "--demo-voice",
            "--demo-voice-page",
            "--demo-long-server-list"
        ]
        mode = arguments.contains(where: testingFlags.contains) ? .offlineTesting : .normal
    }
}
