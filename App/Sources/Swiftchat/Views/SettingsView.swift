import SwiftUI

struct SettingsView: View {
    @AppStorage("sendWithReturn") private var sendWithReturn = true
    @AppStorage("mediaCacheLimit") private var mediaCacheLimit = 2_147_483_648
    @AppStorage("reduceAnimatedMedia") private var reduceAnimatedMedia = false

    var body: some View {
        TabView {
            Form {
                Toggle("Press Return to send messages", isOn: $sendWithReturn)
                Toggle("Reduce animated media", isOn: $reduceAnimatedMedia)
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Picker("Media cache", selection: $mediaCacheLimit) {
                    Text("512 MB").tag(536_870_912)
                    Text("2 GB").tag(2_147_483_648)
                    Text("5 GB").tag(5_368_709_120)
                    Text("10 GB").tag(10_737_418_240)
                }
                Text("Credentials are stored only in the macOS Keychain. Cached message data never contains the account credential.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Storage", systemImage: "internaldrive") }

            Form {
                Text("Plugins will run in a sandboxed WebAssembly host. This foundation build exposes the manifest and permission model but does not execute plugins yet.")
                    .font(.callout)
            }
            .formStyle(.grouped)
            .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 540, height: 330)
    }
}

