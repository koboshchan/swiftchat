import AppKit
import AVKit
import MessageRendering
import SwiftchatModels
import SwiftUI

struct MessageRowView: View, Equatable {
    let model: AppModel
    let message: Message
    let startsGroup: Bool
    let replyPreview: MessageReplyPreview?
    let canEdit: Bool
    let saveEdit: (String) -> Void
    let reply: () -> Void
    let delete: () -> Void
    let react: (String) -> Void
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var isReactionPickerPresented = false
    @State private var editText = ""
    @FocusState private var editFieldFocused: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model
            && lhs.message == rhs.message
            && lhs.startsGroup == rhs.startsGroup
            && lhs.replyPreview == rhs.replyPreview
            && lhs.canEdit == rhs.canEdit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let replyPreview {
                MessageReplyContext(model: model, preview: replyPreview)
            }
            HStack(alignment: .top, spacing: 12) {
                MessageAvatarColumn(
                    model: model,
                    startsGroup: startsGroup,
                    author: message.author,
                    timestamp: message.timestamp
                )
                VStack(alignment: .leading, spacing: 4) {
                    if startsGroup {
                        MessageAuthorLine(model: model, message: message)
                    }
                    MessageContent(
                        message: message,
                        isEditing: $isEditing,
                        editText: $editText,
                        editFieldFocused: $editFieldFocused,
                        save: commitEdit,
                        cancel: cancelEdit,
                        react: react
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, startsGroup ? 12 : 0)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Color.primary.opacity(0.055) : .clear)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if MessageActionVisibilityPolicy.isVisible(
                isRowHovered: isHovering,
                isReactionPickerPresented: isReactionPickerPresented,
                isEditing: isEditing
            ) {
                MessageActionCapsule(
                    model: model,
                    canEdit: canEdit,
                    isReactionPickerPresented: $isReactionPickerPresented,
                    edit: beginEditing,
                    reply: reply,
                    react: react,
                    copy: copyText,
                    delete: delete
                )
                .padding(.trailing, 14)
                .offset(y: -13)
            }
        }
        .onHover { isHovering = $0 }
        .zIndex(isHovering || isReactionPickerPresented ? 10 : 0)
        .overlay {
            MessageContextMenuBridge(
                canEdit: canEdit,
                edit: beginEditing,
                reply: reply,
                react: react,
                copy: copyText,
                delete: delete
            )
        }
    }

    private func beginEditing() {
        editText = message.content
        isEditing = true
        editFieldFocused = true
    }

    private func commitEdit() {
        let value = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isEditing = false
        saveEdit(value)
    }

    private func cancelEdit() {
        isEditing = false
        editText = message.content
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }
}

enum MessageActionVisibilityPolicy {
    nonisolated static func isVisible(
        isRowHovered: Bool,
        isReactionPickerPresented: Bool,
        isEditing: Bool
    ) -> Bool {
        !isEditing && (isRowHovered || isReactionPickerPresented)
    }
}

private struct MessageContextMenuBridge: NSViewRepresentable {
    let canEdit: Bool
    let edit: () -> Void
    let reply: () -> Void
    let react: (String) -> Void
    let copy: () -> Void
    let delete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            canEdit: canEdit,
            edit: edit,
            reply: reply,
            react: react,
            copy: copy,
            delete: delete
        )
    }

    func makeNSView(context: Context) -> MessageContextMenuHitView {
        let view = MessageContextMenuHitView()
        view.menuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.makeMenu()
        }
        return view
    }

    func updateNSView(_ nsView: MessageContextMenuHitView, context: Context) {
        context.coordinator.update(
            canEdit: canEdit,
            edit: edit,
            reply: reply,
            react: react,
            copy: copy,
            delete: delete
        )
        nsView.menuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.makeMenu()
        }
    }

    final class Coordinator: NSObject {
        private var canEdit: Bool
        private var edit: () -> Void
        private var reply: () -> Void
        private var react: (String) -> Void
        private var copy: () -> Void
        private var delete: () -> Void

        init(
            canEdit: Bool,
            edit: @escaping () -> Void,
            reply: @escaping () -> Void,
            react: @escaping (String) -> Void,
            copy: @escaping () -> Void,
            delete: @escaping () -> Void
        ) {
            self.canEdit = canEdit
            self.edit = edit
            self.reply = reply
            self.react = react
            self.copy = copy
            self.delete = delete
        }

        func update(
            canEdit: Bool,
            edit: @escaping () -> Void,
            reply: @escaping () -> Void,
            react: @escaping (String) -> Void,
            copy: @escaping () -> Void,
            delete: @escaping () -> Void
        ) {
            self.canEdit = canEdit
            self.edit = edit
            self.reply = reply
            self.react = react
            self.copy = copy
            self.delete = delete
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(menuItem("Add Reaction", systemImage: "face.smiling.inverse", action: #selector(addReaction)))
            menu.addItem(menuItem("Reply", systemImage: "arrowshape.turn.up.left", action: #selector(replyToMessage)))
            if canEdit {
                menu.addItem(menuItem("Edit Message", systemImage: "pencil", action: #selector(editMessage)))
            }
            menu.addItem(menuItem("Copy Text", systemImage: "doc.on.doc", action: #selector(copyMessage)))
            if canEdit {
                menu.addItem(.separator())
                menu.addItem(menuItem(
                    "Delete Message",
                    systemImage: "trash",
                    action: #selector(deleteMessage),
                    isDestructive: true
                ))
            }
            return menu
        }

        private func menuItem(
            _ title: String,
            systemImage: String,
            action: Selector,
            isDestructive: Bool = false
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = true

            let baseConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let configuration = isDestructive
                ? baseConfiguration.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
                : baseConfiguration
            if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
                .withSymbolConfiguration(configuration)
            {
                image.isTemplate = !isDestructive
                item.image = image
            }
            if #available(macOS 27.0, *) {
                item.preferredImageVisibility = .visible
            }

            if isDestructive {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            return item
        }

        @objc private func addReaction() {
            react("👍")
        }

        @objc private func replyToMessage() {
            reply()
        }

        @objc private func editMessage() {
            edit()
        }

        @objc private func copyMessage() {
            copy()
        }

        @objc private func deleteMessage() {
            delete()
        }
    }
}

private final class MessageContextMenuHitView: NSView {
    var menuProvider: (() -> NSMenu?)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = window?.currentEvent else { return nil }
        if event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        {
            return self
        }
        return nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }
}

private struct MessageActionCapsule: View {
    let model: AppModel
    let canEdit: Bool
    @Binding var isReactionPickerPresented: Bool
    let edit: () -> Void
    let reply: () -> Void
    let react: (String) -> Void
    let copy: () -> Void
    let delete: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 1) {
                ReactionActionMenu(
                    model: model,
                    isPickerPresented: $isReactionPickerPresented,
                    react: react
                )
                MessageActionButton(systemImage: "arrowshape.turn.up.left", help: "Reply", action: reply)
                if canEdit {
                    MessageActionButton(systemImage: "pencil", help: "Edit message", action: edit)
                }
                MessageActionButton(systemImage: "doc.on.doc", help: "Copy text", action: copy)
                if canEdit {
                    MessageActionButton(systemImage: "trash", help: "Delete message", role: .destructive, action: delete)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: Capsule())
        }
    }
}

private struct MessageActionButton: View {
    let systemImage: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .symbolVariant(.none)
                .font(.callout.weight(.medium))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(hoverColor, in: Circle())
        .contentShape(Circle())
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var iconColor: Color {
        role == .destructive && isHovering ? .red : .primary
    }

    private var hoverColor: Color {
        guard isHovering else { return .clear }
        return role == .destructive ? .red.opacity(0.18) : .primary.opacity(0.14)
    }
}

private struct ReactionActionMenu: View {
    let model: AppModel
    @Binding var isPickerPresented: Bool
    let react: (String) -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isHovering ? Color.primary.opacity(0.14) : .clear)

            Button { presentPicker() } label: {
                Image(systemName: "face.smiling.inverse")
                    .symbolVariant(.none)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPickerPresented, arrowEdge: .trailing) {
                EmojiPickerView(model: model) { activation in
                    switch activation.selection {
                    case let .native(value): react(value)
                    case let .custom(emoji): react(emoji.messageToken)
                    }
                    isPickerPresented = false
                }
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
        .onHover { isHovering = $0 }
        .help("Add reaction")
    }

    private func presentPicker() {
        guard !isPickerPresented else {
            isPickerPresented = false
            return
        }
        Task { @MainActor in
            await Task.yield()
            isPickerPresented = true
        }
    }
}

private struct MessageReplyContext: View {
    let model: AppModel
    let preview: MessageReplyPreview

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            MessageProfileAvatar(model: model, user: preview.author, size: 16)
            MessageProfileName(model: model, user: preview.author, font: .caption.weight(.semibold))
            CustomEmojiRichText(content: summary, emojiSize: 15)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: 18, alignment: .leading)
                .clipped()
        }
        .font(.caption)
        .padding(.leading, 50)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replying to \(preview.author.displayName): \(summary)")
    }

    private var summary: String {
        let value = preview.content.replacingOccurrences(of: "\n", with: " ")
        return value.isEmpty ? "Attachment" : value
    }
}

private struct MessageAvatarColumn: View {
    let model: AppModel
    let startsGroup: Bool
    let author: User
    let timestamp: Date
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if startsGroup {
                MessageProfileAvatar(model: model, user: author, size: 38)
            } else if isHovering {
                Text(timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 38, height: startsGroup ? 38 : 20)
        .onHover { isHovering = $0 }
    }
}

private struct MessageContent: View {
    let message: Message
    @Binding var isEditing: Bool
    @Binding var editText: String
    var editFieldFocused: FocusState<Bool>.Binding
    let save: () -> Void
    let cancel: () -> Void
    let react: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                InlineMessageEditor(
                    text: $editText,
                    isFocused: editFieldFocused,
                    save: save,
                    cancel: cancel
                )
            } else if !message.content.isEmpty {
                DiscordMessageContentView(content: message.content)
            }
            ForEach(message.attachments) { attachment in AttachmentView(attachment: attachment) }
            MessageReactions(reactions: message.reactions, react: react)
            if message.outboxState != .confirmed {
                Label(message.outboxState.rawValue.capitalized, systemImage: message.outboxState == .failed ? "exclamationmark.circle" : "clock")
                    .font(.caption2)
                    .foregroundStyle(message.outboxState == .failed ? .red : .secondary)
            }
        }
    }
}

private struct InlineMessageEditor: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("Edit message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 12)
                .focused(isFocused)
                .padding(9)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit(save)
            HStack(spacing: 6) {
                Text("Escape to cancel · Enter to save")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Cancel", action: cancel).buttonStyle(.link).keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(.link).keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct MessageAuthorLine: View {
    let model: AppModel
    let message: Message

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            MessageProfileName(model: model, user: message.author, font: .headline)
                .foregroundStyle(message.author.isBot ? Color.accentColor : .primary)
            if message.author.isBot {
                Text("APP").font(.caption2.bold()).padding(.horizontal, 4).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 3))
            }
            Text(message.timestamp, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
            if message.editedTimestamp != nil {
                Text("(edited)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MessageReactions: View {
    let reactions: [Reaction]
    let react: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(reactions) { reaction in
                Button { react(reaction.emoji) } label: {
                    HStack(spacing: 4) {
                        if ParsedCustomEmoji(token: reaction.emoji) != nil {
                            CustomEmojiGlyph(token: reaction.emoji, size: 17)
                        } else {
                            Text(reaction.emoji)
                        }
                        Text(reaction.count, format: .number)
                    }
                    .font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(reaction.didCurrentUserReact ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MessageProfileAvatar: View {
    let model: AppModel
    let user: User
    let size: CGFloat
    @State private var isPresented = false

    var body: some View {
        Button { open() } label: {
            AvatarView(name: user.displayName, url: user.avatarURL, size: size)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            MessageProfilePopoverContent(model: model, userID: user.id)
        }
        .help("View \(user.displayName)'s profile")
    }

    private func open() {
        model.showProfile(for: user)
        isPresented = true
    }
}

private struct MessageProfileName: View {
    let model: AppModel
    let user: User
    let font: Font
    @State private var isPresented = false

    var body: some View {
        Button {
            model.showProfile(for: user)
            isPresented = true
        } label: {
            Text(user.displayName).font(font)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            MessageProfilePopoverContent(model: model, userID: user.id)
        }
        .help("View \(user.displayName)'s profile")
    }
}

private struct MessageProfilePopoverContent: View {
    let model: AppModel
    let userID: UserID

    var body: some View {
        ZStack {
            if let member = model.selectedMember, member.id == userID {
                MemberProfilePopover(
                    member: member,
                    profile: model.selectedProfile,
                    isLoading: model.isLoadingProfile,
                    errorMessage: model.profileErrorMessage
                )
            } else {
                ProgressView().padding(40)
            }
        }
        .onDisappear {
            if !model.isInspectorProfilePresented, model.selectedMember?.id == userID {
                model.dismissProfile()
            }
        }
    }
}

private struct AttachmentView: View {
    let attachment: Attachment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AttachmentPreview(attachment: attachment, kind: previewKind)
            if let description = attachment.description {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var isImage: Bool {
        attachment.mediaType?.hasPrefix("image/") == true
            || ["png", "jpg", "jpeg", "gif", "webp"].contains(attachment.url.pathExtension.lowercased())
    }

    private var isGIF: Bool {
        attachment.mediaType == "image/gif" || attachment.url.pathExtension.lowercased() == "gif"
    }

    private var isVideo: Bool {
        attachment.mediaType?.hasPrefix("video/") == true || ["mp4", "mov", "webm", "m4v"].contains(attachment.url.pathExtension.lowercased())
    }

    private var isAudio: Bool {
        attachment.mediaType?.hasPrefix("audio/") == true || ["mp3", "m4a", "wav", "ogg", "flac"].contains(attachment.url.pathExtension.lowercased())
    }

    private var previewKind: AttachmentPreviewKind {
        if isGIF {
            return .gif
        }
        if isImage {
            return .image
        }
        if isVideo {
            return .video
        }
        if isAudio {
            return .audio
        }
        return .file
    }
}

private enum AttachmentPreviewKind { case gif, image, video, audio, file }

private struct AttachmentPreview: View {
    let attachment: Attachment
    let kind: AttachmentPreviewKind

    var body: some View {
        ZStack {
            switch kind {
            case .gif:
                AnimatedGIFView(url: attachment.proxyURL ?? attachment.url)
                    .frame(width: 420, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .image:
                StaticImageAttachmentView(
                    url: attachment.proxyURL ?? attachment.url,
                    pixelWidth: attachment.width,
                    pixelHeight: attachment.height
                )
            case .video:
                InlineAVPreview(url: attachment.url, compact: false)
            case .audio:
                InlineAVPreview(url: attachment.url, compact: true)
            case .file:
                FileAttachmentCard(filename: attachment.filename, size: attachment.size, url: attachment.url)
            }
        }
    }
}

private struct StaticImageAttachmentView: View {
    let url: URL
    let pixelWidth: Int?
    let pixelHeight: Int?

    var body: some View {
        ZStack {
            if url.isFileURL {
                AnimatedRemoteImage(url: url, isLooping: false)
            } else {
                AsyncImage(request: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    default:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var displaySize: CGSize {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else {
            return CGSize(width: 320, height: 180)
        }
        let scale = min(1, min(420 / CGFloat(pixelWidth), 300 / CGFloat(pixelHeight)))
        return CGSize(width: CGFloat(pixelWidth) * scale, height: CGFloat(pixelHeight) * scale)
    }
}

private struct FileAttachmentCard: View {
    let filename: String
    let size: Int
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "doc").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename).lineLimit(1)
                    if size > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
        }
        .background { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
    }
}

private struct InlineAVPreview: View {
    let url: URL
    let compact: Bool
    var body: some View {
        NativeAVPlayerView(url: url)
            .frame(width: compact ? 360 : 420, height: compact ? 72 : 236)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct NativeAVPlayerView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.player?.pause()
        let player = AVPlayer(url: url)
        context.coordinator.url = url
        context.coordinator.player = player
        nsView.player = player
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        nsView.player = nil
    }

    final class Coordinator {
        var url: URL?
        var player: AVPlayer?
    }
}

private struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadTask?.cancel()
        context.coordinator.loadedURL = url
        nsView.image = nil
        context.coordinator.loadTask = Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) != false,
                  !Task.isCancelled,
                  context.coordinator.loadedURL == url,
                  let image = NSImage(data: data) else { return }
            nsView.image = image
        }
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        coordinator.loadTask = nil
        nsView.image = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedURL: URL?
        var loadTask: Task<Void, Never>?
    }
}
