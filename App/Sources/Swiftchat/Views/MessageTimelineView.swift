import SwiftchatModels
import SwiftUI

struct MessageTimelineView: View {
    let model: AppModel
    @State private var isNearBottom = true
    @State private var allowsAutomaticHistoryLoading = false

    private let bottomID = "message-timeline-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.hasMoreMessages {
                            EarlierMessageLoader(
                                isLoading: model.isLoadingEarlier
                            ) {
                                loadEarlier(using: proxy)
                            }
                        }
                        ForEach(model.messageRows) { row in
                            MessageRowView(
                                model: model,
                                message: row.message,
                                startsGroup: row.startsGroup,
                                replyPreview: row.replyPreview,
                                canEdit: row.message.author.id == model.snapshot?.currentUser.id,
                                saveEdit: { content in Task { await model.edit(row.message, content: content) } },
                                reply: { model.reply(to: row.message) },
                                delete: { Task { await model.delete(row.message) } },
                                react: { emoji in Task { await model.toggleReaction(emoji, on: row.message) } }
                            )
                            .equatable()
                            .id(row.id)
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.vertical, 12)
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                }
                .defaultScrollAnchor(.bottom)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onScrollGeometryChange(for: TimelineScrollState.self) { geometry in
                    TimelineScrollState(
                        isNearTop: geometry.contentOffset.y < 100,
                        isNearBottom: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 120
                    )
                } action: { _, value in
                    isNearBottom = value.isNearBottom
                    if value.isNearTop, allowsAutomaticHistoryLoading, model.hasMoreMessages, !model.isLoadingEarlier {
                        loadEarlier(using: proxy)
                    }
                }
                .overlay {
                    if model.messages.isEmpty, model.isLoadingMessages {
                        ProgressView("Loading messages…")
                            .controlSize(.small)
                    }
                }
                .overlay(alignment: .top) {
                    if let error = model.messageLoadError {
                        MessageLoadErrorBanner(message: error, retry: model.retryMessageLoad)
                            .padding(8)
                    }
                }
                .onChange(of: model.messages.last?.id) { oldID, id in
                    guard let id else { return }
                    guard oldID == nil || isNearBottom else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
                .onChange(of: model.selectedChannelID) {
                    isNearBottom = true
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
                .task(id: model.selectedChannelID) {
                    allowsAutomaticHistoryLoading = false
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    allowsAutomaticHistoryLoading = true
                }
            }
        }
    }

    private func loadEarlier(using proxy: ScrollViewProxy) {
        let anchor = model.messages.first?.id
        Task {
            await model.loadEarlier()
            guard let anchor, model.selectedChannelID != nil else { return }
            proxy.scrollTo(anchor, anchor: .top)
        }
    }
}

private struct EarlierMessageLoader: View {
    let isLoading: Bool
    let load: () -> Void

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading earlier messages…")
                }
            } else {
                Button("Load earlier messages", action: load)
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct TimelineScrollState: Equatable {
    let isNearTop: Bool
    let isNearBottom: Bool
}

private struct MessageLoadErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text(message).lineLimit(2)
            Spacer(minLength: 8)
            Button("Retry", action: retry).buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary)
    }
}
