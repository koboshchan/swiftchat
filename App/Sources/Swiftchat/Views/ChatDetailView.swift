import SwiftchatModels
import SwiftUI

struct ChatDetailView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let channel = model.selectedChannel {
                MessageTimelineView(model: model)
                TypingIndicatorView(typingState: model.typingState, channelID: channel.id)
                ComposerView(model: model, channelName: channel.name)
            } else {
                ContentUnavailableView("Choose a conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Select a server and channel to begin."))
            }
        }
    }
}

private struct TypingIndicatorView: View {
    let typingState: TypingStateModel
    let channelID: ChannelID

    var body: some View {
        Text(typingState.presentation(in: channelID) ?? " ")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
            .padding(.horizontal, 16)
            .accessibilityHidden(typingState.presentation(in: channelID) == nil)
    }
}
