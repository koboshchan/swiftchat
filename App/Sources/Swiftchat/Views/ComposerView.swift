import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    let model: AppModel
    let channelName: String
    @State private var attachments: [URL] = []
    @State private var showFileImporter = false
    @State private var showEmojiPicker = false
    @State private var showGIFPicker = false
    @State private var isFocused = false
    @State private var draftSelection: NSRange?
    @State private var selectionBeforeEmojiPicker: NSRange?
    @State private var isSubmitting = false
    @State private var emojiPickerDismissedAt: TimeInterval = -.infinity
    @AppStorage("sendWithReturn") private var sendWithReturn = true

    var body: some View {
        @Bindable var model = model
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                if !attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(attachments, id: \.self) { url in
                                HStack(spacing: 7) {
                                    Image(systemName: "doc")
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Button { attachments.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle") }
                                        .buttonStyle(.plain)
                                }
                                .padding(8)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                    .frame(height: 42)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let reply = model.replyingTo {
                        HStack(spacing: 7) {
                            Image(systemName: "arrowshape.turn.up.left")
                                .foregroundStyle(.secondary)
                            Text("Replying to")
                                .foregroundStyle(.secondary)
                            Text(reply.author.displayName)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Button { model.cancelReply() } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel reply")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                    }
                    HStack(alignment: .bottom, spacing: 9) {
                        ComposerActionButton(
                            systemImage: "plus",
                            help: "Add attachments",
                            iconSize: 19,
                            iconWeight: .regular
                        ) {
                            showFileImporter = true
                        }
                        ZStack(alignment: .leading) {
                            ComposerTextView(
                                text: model.draft,
                                placeholder: "Message #\(channelName)",
                                sendWithReturn: sendWithReturn,
                                onTextChange: model.updateDraft,
                                onSubmit: send,
                                selection: $draftSelection,
                                isFocused: $isFocused
                            )

                            if model.draft.isEmpty {
                                Text("Message #\(channelName)")
                                    .foregroundStyle(.tertiary)
                                    .font(.system(size: 15))
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 36, alignment: .center)
                        .layoutPriority(1)
                        HStack(spacing: 1) {
                            ComposerActionButton(
                                systemImage: "rectangle.stack",
                                help: "Choose GIF",
                                iconSize: 16
                            ) {
                                showGIFPicker.toggle()
                            }
                            .fixedSize()
                            .popover(isPresented: $showGIFPicker) { GIFURLPicker { attachments.append($0); showGIFPicker = false } }
                            ComposerActionButton(
                                systemImage: "face.smiling.inverse",
                                help: "Choose emoji",
                                iconSize: 19,
                                iconWeight: .medium
                            ) {
                                toggleEmojiPicker()
                            }
                            .fixedSize()
                            .popover(
                                isPresented: $showEmojiPicker,
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .bottom
                            ) {
                                composerEmojiPicker
                            }
                            Capsule()
                                .fill(.primary.opacity(0.16))
                                .frame(width: 1, height: 16)
                                .frame(width: 9, height: 36)
                                .accessibilityHidden(true)
                            ComposerSendButton(action: send)
                                .disabled(
                                    isSubmitting
                                        || (model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                                )
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .frame(minHeight: ChatChromeMetrics.controlHeight)
                }
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: ChatChromeMetrics.controlCornerRadius, style: .continuous)
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12).padding(.bottom, 12)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { attachments.append(contentsOf: urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in attachments.append(contentsOf: urls); return true }
        .onReceive(NotificationCenter.default.publisher(for: .swiftchatFocusComposer)) { _ in isFocused = true }
        .onChange(of: showEmojiPicker) { wasPresented, isPresented in
            if wasPresented, !isPresented {
                emojiPickerDismissedAt = ProcessInfo.processInfo.systemUptime
            }
        }
        .task(id: model.selectedChannelID) {
            attachments.removeAll()
            draftSelection = nil
            selectionBeforeEmojiPicker = nil
            showFileImporter = false
            showEmojiPicker = false
            showGIFPicker = false
            guard model.selectedChannel?.kind != .voice else { return }
            isFocused = true
        }
    }

    private var composerEmojiPicker: some View {
        EmojiPickerView(
            model: model,
            allowsPersistentSelection: true
        ) { activation in
            let replacementSelection = selectionBeforeEmojiPicker
                ?? NSRange(location: model.draft.utf16.count, length: 0)
            let restoredSelection: NSRange
            switch activation.selection {
            case let .native(value):
                restoredSelection = insertInDraft(value, replacing: replacementSelection)
            case let .custom(emoji):
                let value = model.composerText(for: emoji)
                let separator = model.draft.isEmpty || model.draft.last?.isWhitespace == true ? "" : " "
                restoredSelection = insertInDraft(
                    separator + value,
                    replacing: replacementSelection
                )
            }
            if activation.keepsPickerPresented {
                selectionBeforeEmojiPicker = restoredSelection
                draftSelection = restoredSelection
                return
            }
            showEmojiPicker = false
            selectionBeforeEmojiPicker = nil
            Task { @MainActor in
                await Task.yield()
                isFocused = true
                await Task.yield()
                draftSelection = restoredSelection
            }
        }
        .onExitCommand { showEmojiPicker = false }
    }

    private func toggleEmojiPicker() {
        if showEmojiPicker {
            showEmojiPicker = false
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - emojiPickerDismissedAt > 0.25 else { return }

        selectionBeforeEmojiPicker = draftSelection
            ?? NSRange(location: model.draft.utf16.count, length: 0)
        showEmojiPicker = true
    }

    private func send() {
        guard !isSubmitting,
              !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        isSubmitting = true
        draftSelection = nil
        selectionBeforeEmojiPicker = nil
        let staged = attachments
        attachments.removeAll()
        Task {
            let scopedURLs = staged.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
            }
            let didSend = await model.send(attachments: staged)
            if !didSend { attachments = staged }
            isSubmitting = false
            isFocused = true
        }
    }

    @discardableResult
    private func insertInDraft(
        _ insertedText: String,
        replacing selection: NSRange?
    ) -> NSRange {
        var value = model.draft
        let replacementRange = selection.flatMap { Range($0, in: value) }
            ?? value.endIndex..<value.endIndex
        let utf16Offset = selection?.location ?? value.utf16.count
        value.replaceSubrange(replacementRange, with: insertedText)
        model.updateDraft(value)
        return NSRange(location: utf16Offset + insertedText.utf16.count, length: 0)
    }
}

private struct ComposerActionButton: View {
    let systemImage: String
    let help: String
    var iconSize: CGFloat = 18
    var iconWeight: Font.Weight = .medium
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .symbolVariant(.none)
                .font(.system(size: iconSize, weight: iconWeight))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(buttonShape)
        }
        .buttonStyle(.plain)
        .background(hoverColor, in: buttonShape)
        .contentShape(buttonShape)
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    private var hoverColor: Color {
        isHovering && isEnabled ? .primary.opacity(0.14) : .clear
    }

}

private struct ComposerSendButton: View {
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(isEnabled ? Color.white : Color.gray.opacity(0.62))
                .frame(width: 36, height: 36)
                .contentShape(buttonShape)
        }
        .buttonStyle(.plain)
        .background(hoverColor, in: buttonShape)
        .contentShape(buttonShape)
        .onHover { isHovering = $0 }
        .help("Send message")
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    private var hoverColor: Color {
        isHovering && isEnabled ? .primary.opacity(0.14) : .clear
    }
}

private struct GIFURLPicker: View {
    let select: (URL) -> Void
    @State private var value = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send GIF by URL").font(.headline)
            Text("GIF search is provider-backed; paste a direct URL while using the demo provider.").font(.caption).foregroundStyle(.secondary)
            TextField("https://…/animation.gif", text: $value)
            Button("Add GIF") { if let url = URL(string: value), url.scheme == "https" { select(url) } }
                .buttonStyle(.borderedProminent).disabled(URL(string: value)?.scheme != "https")
        }
        .padding().frame(width: 360)
    }
}
