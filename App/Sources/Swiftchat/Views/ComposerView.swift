import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    let model: AppModel
    let channelName: String
    @State private var attachments: [URL] = []
    @State private var showFileImporter = false
    @State private var showEmojiPicker = false
    @State private var showGIFPicker = false
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                if !attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(attachments, id: \.self) { url in
                                HStack(spacing: 7) {
                                    Image(systemName: "doc.fill")
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Button { attachments.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
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
                            Image(systemName: "arrowshape.turn.up.left.fill")
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
                    HStack(alignment: .center, spacing: 9) {
                        Button { showFileImporter = true } label: {
                            Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 28, height: 28).background(.white, in: Circle()).foregroundStyle(.black)
                        }
                            .buttonStyle(.plain).help("Add attachments")
                        TextField("Message #\(channelName)", text: $model.draft, axis: .vertical)
                            .textFieldStyle(.plain).lineLimit(1...8).focused($isFocused)
                            .onSubmit { send() }
                            .onChange(of: model.draft) { _, value in model.updateDraft(value) }
                        Button { showGIFPicker.toggle() } label: { Text("GIF").font(.caption.bold()).padding(4).overlay(RoundedRectangle(cornerRadius: 4).stroke()) }
                            .buttonStyle(.plain).popover(isPresented: $showGIFPicker) { GIFURLPicker { attachments.append($0); showGIFPicker = false } }
                        Button { showEmojiPicker.toggle() } label: { Image(systemName: "face.smiling.fill").font(.title3) }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showEmojiPicker) {
                                EmojiPickerView(model: model) { selection in
                                    switch selection {
                                    case let .native(value):
                                        model.updateDraft(model.draft + value)
                                    case let .custom(emoji):
                                        let value = model.composerText(for: emoji)
                                        let separator = model.draft.isEmpty || model.draft.last?.isWhitespace == true ? "" : " "
                                        model.updateDraft(model.draft + separator + value)
                                    }
                                }
                            }
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.body.weight(.bold))
                                .frame(width: 30, height: 30)
                                .background(.white, in: Circle())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                    }
                    .padding(.horizontal, 11)
                    .frame(minHeight: ChatChromeMetrics.controlHeight)
                }
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: ChatChromeMetrics.controlCornerRadius, style: .continuous)
                )
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { attachments.append(contentsOf: urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in attachments.append(contentsOf: urls); return true }
        .onReceive(NotificationCenter.default.publisher(for: .swiftchatFocusComposer)) { _ in isFocused = true }
    }

    private func send() {
        let staged = attachments
        attachments.removeAll()
        Task { await model.send(attachments: staged) }
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
