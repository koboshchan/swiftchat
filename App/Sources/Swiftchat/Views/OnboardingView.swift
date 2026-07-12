import SwiftUI

struct OnboardingView: View {
    @Binding var acceptedRisk: Bool
    @Binding var showLogin: Bool
    @State private var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 38)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("Welcome to Swiftchat").font(.largeTitle.bold())
                    Text("A native macOS Discord client foundation").foregroundStyle(.secondary)
                }
            }

            GroupBox("Unofficial client warning") {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Discord does not authorize third-party normal-account clients.", systemImage: "exclamationmark.triangle.fill")
                    Label("Embedded sign-in is session capture, not Discord OAuth.", systemImage: "key.fill")
                    Label("Using an account may result in suspension and can break without notice.", systemImage: "person.crop.circle.badge.exclamationmark")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            Toggle("I understand and accept these risks", isOn: $confirmed)

            HStack {
                Link("Read Discord’s self-bot policy", destination: URL(string: "https://support.discord.com/hc/en-us/articles/115002192352-Automated-User-Accounts-Self-Bots")!)
                Spacer()
                Button("Open Discord Sign-In") {
                    acceptedRisk = true
                    showLogin = true
                }
                .disabled(!confirmed)
                Button("Explore Demo") { acceptedRisk = true }
                    .buttonStyle(.borderedProminent).disabled(!confirmed)
            }
        }
        .padding(28).frame(width: 620)
        .interactiveDismissDisabled()
    }
}

