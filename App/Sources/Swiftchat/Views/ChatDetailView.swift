import SwiftchatModels
import SwiftUI

struct ChatDetailView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let channel = model.selectedChannel {
                MessageTimelineView(model: model)
                if let typingText = model.typingText {
                    Text(typingText).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
                }
                ComposerView(model: model, channelName: channel.name)
            } else {
                ContentUnavailableView("Choose a conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Select a server and channel to begin."))
            }
        }
    }
}
