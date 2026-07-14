import DiscordProtocol
import SwiftchatModels
import SwiftchatPersistence
import CoreAudio
import Foundation
import MediaPipeline
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: BootstrapSnapshot?
    private(set) var visibleChannels: [Channel] = []
    private(set) var selectedChannel: Channel?
    private(set) var messages: [Message] = [] {
        didSet {
            messageRows = MessageGrouping.rows(for: messages)
            if let selectedChannelID { messageCache[selectedChannelID] = messages }
        }
    }
    private(set) var messageRows: [MessageRowPresentation] = []
    private(set) var members: [Member] = [] {
        didSet { memberSections = MemberSection.make(from: members) }
    }
    private(set) var memberSections: [MemberSection] = []
    private(set) var currentStatus: PresenceStatus = .offline
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isAuthenticated = false
    private(set) var typingText: String?
    private(set) var isLoading = false
    private(set) var isLoadingMessages = false
    private(set) var isLoadingEarlier = false
    private(set) var hasMoreMessages = false
    private(set) var messageLoadError: String?
    private(set) var replyingTo: Message?
    private(set) var selectedMember: Member?
    private(set) var selectedProfile: UserProfile?
    private(set) var isLoadingProfile = false
    private(set) var profileErrorMessage: String?
    private(set) var activeVoiceChannel: Channel?
    private(set) var voiceSessionState: VoiceSessionState = .idle
    private(set) var voiceParticipants: [VoiceRemoteParticipant] = []
    private(set) var isLocallySpeaking = false
    private(set) var voiceVideoFrames: [String: VoiceVideoFrame] = [:]
    private(set) var voiceEncryptionVersion: UInt16?
    private(set) var voiceLatencyMilliseconds: Int?
    private(set) var voiceErrorMessage: String?
    private(set) var voiceStates: [UserID: VoiceParticipantState] = [:]
    private(set) var mediaDevices = MediaDeviceCatalog.snapshot()
    private(set) var emojisByGuild: [GuildID: [DiscordEmoji]] = [:]
    private(set) var loadingEmojiGuildIDs: Set<GuildID> = []
    private(set) var emojiLoadErrorsByGuild: [GuildID: String] = [:]
    private(set) var favoriteEmojiKeys: Set<String>
    private(set) var emojiUsageCounts: [String: Int]
    private(set) var discordFavoriteEmojiKeys: Set<String> = []
    private(set) var discordEmojiUsageScores: [String: Int] = [:]
    var isVoiceMuted = UserDefaults.standard.bool(forKey: "voiceMuted")
    var isVoiceDeafened = UserDefaults.standard.bool(forKey: "voiceDeafened")
    var isCameraEnabled = false
    var inputVolume = Float(UserDefaults.standard.object(forKey: "voiceInputVolume") as? Double ?? 1)
    var outputVolume = Float(UserDefaults.standard.object(forKey: "voiceOutputVolume") as? Double ?? 1)
    var selectedGuildID: GuildID?
    var selectedChannelID: ChannelID? {
        didSet {
            guard selectedChannelID != oldValue else { return }
            selectedChannel = snapshot?.channels.first { $0.id == selectedChannelID }
                ?? visibleChannels.first { $0.id == selectedChannelID }
            beginSelectedChannelLoad()
        }
    }
    var draft = ""
    var showInspector = true
    var showQuickSwitcher = false
    var errorMessage: String?

    @ObservationIgnored private var provider: any ChatProvider
    @ObservationIgnored private var database: SwiftchatDatabase?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var typingTask: Task<Void, Never>?
    @ObservationIgnored private var profileTask: Task<Void, Never>?
    @ObservationIgnored private var channelLoadTask: Task<Void, Never>?
    @ObservationIgnored private var guildActivationTask: Task<Void, Never>?
    @ObservationIgnored private var memberLoadTask: Task<Void, Never>?
    @ObservationIgnored private var voiceEventTask: Task<Void, Never>?
    @ObservationIgnored private var voiceMigrationTask: Task<Void, Never>?
    @ObservationIgnored private var voiceSession: DiscordVoiceSession?
    @ObservationIgnored private var voiceMigrationGeneration = 0
    @ObservationIgnored private var channelLoadGeneration = 0
    @ObservationIgnored private var messageCache: [ChannelID: [Message]] = [:]
    @ObservationIgnored private var hasMoreCache: [ChannelID: Bool] = [:]
    @ObservationIgnored private let restoreStoredSession: Bool
    @ObservationIgnored private let discordNetworkDisabled: Bool
    @ObservationIgnored private var didAttemptSessionRestore = false
    @ObservationIgnored private var credentialHandle: CredentialHandle?
    @ObservationIgnored private var didAttemptDiscordEmojiSettings = false

    init(provider: any ChatProvider = MockChatProvider(), restoreStoredSession: Bool = true) {
        self.provider = provider
        discordNetworkDisabled = CommandLine.arguments.contains("--offline")
            || ProcessInfo.processInfo.environment["SWIFTCHAT_DISABLE_DISCORD_NETWORK"] == "1"
        self.restoreStoredSession = restoreStoredSession && !discordNetworkDisabled
        favoriteEmojiKeys = Set(UserDefaults.standard.stringArray(forKey: "dev.swiftchat.favorite-emojis") ?? [])
        emojiUsageCounts = UserDefaults.standard.dictionary(forKey: "dev.swiftchat.emoji-usage") as? [String: Int] ?? [:]
        database = try? SwiftchatDatabase(accountID: AccountID(rawValue: 1))
    }

    func connectAuthenticatedAccount(_ handle: CredentialHandle) async -> Bool {
        guard !discordNetworkDisabled else {
            errorMessage = "Discord networking is disabled in offline UI mode."
            return false
        }
        await leaveVoice()
        await provider.disconnect()
        eventTask?.cancel()
        provider = DiscordRESTProvider(credentials: KeychainCredentialStore(), handle: handle)
        credentialHandle = handle
        database = AccountID(handle.accountID).flatMap { try? SwiftchatDatabase(accountID: $0) }
        snapshot = nil
        emojisByGuild = [:]
        loadingEmojiGuildIDs = []
        emojiLoadErrorsByGuild = [:]
        didAttemptDiscordEmojiSettings = false
        voiceStates = [:]
        visibleChannels = []
        selectedChannel = nil
        selectedGuildID = nil
        selectedChannelID = nil
        messages = []
        messageCache = [:]
        hasMoreCache = [:]
        dismissProfile()
        errorMessage = nil
        await start()
        isAuthenticated = snapshot != nil
        return isAuthenticated
    }

    func logout() async {
        await leaveVoice()
        await provider.disconnect()
        eventTask?.cancel()
        typingTask?.cancel()
        if let credentialHandle {
            do {
                try await KeychainCredentialStore().remove(credentialHandle)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        credentialHandle = nil
        provider = MockChatProvider()
        database = try? SwiftchatDatabase(accountID: AccountID(rawValue: 1))
        snapshot = nil
        emojisByGuild = [:]
        loadingEmojiGuildIDs = []
        emojiLoadErrorsByGuild = [:]
        didAttemptDiscordEmojiSettings = false
        voiceStates = [:]
        visibleChannels = []
        selectedChannel = nil
        selectedGuildID = nil
        selectedChannelID = nil
        messages = []
        messageCache = [:]
        hasMoreCache = [:]
        members = []
        dismissProfile()
        connectionState = .disconnected
        isAuthenticated = false
        didAttemptSessionRestore = true
        await start()
    }

    func start() async {
        guard snapshot == nil else { return }
        if restoreStoredSession, !didAttemptSessionRestore {
            didAttemptSessionRestore = true
            if let handles = try? await KeychainCredentialStore().handles(), let handle = handles.first {
                _ = await connectAuthenticatedAccount(handle)
                return
            }
        }
        let stream = await provider.eventStream()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                self?.consume(event)
            }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await provider.bootstrap()
            snapshot = value
            if credentialHandle != nil { isAuthenticated = true }
            members = value.members
            currentStatus = await provider.currentStatus()
            await activateGuild(value.guilds.first?.id)
            await channelLoadTask?.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectGuild(_ guildID: GuildID?) {
        guildActivationTask?.cancel()
        guildActivationTask = Task { [weak self] in
            await self?.activateGuild(guildID)
        }
    }

    private func activateGuild(_ guildID: GuildID?) async {
        dismissProfile()
        selectedGuildID = guildID
        var channels = snapshot?.channels.filter { channel in
            guildID == nil ? channel.guildID == nil : channel.guildID == guildID
        } ?? []
        visibleChannels = channels
        if channels.isEmpty {
            do {
                channels = try await provider.channels(in: guildID)
                if var value = snapshot {
                    value.channels.removeAll { $0.guildID == guildID }
                    value.channels.append(contentsOf: channels)
                    snapshot = value
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        guard !Task.isCancelled, selectedGuildID == guildID else { return }
        visibleChannels = channels
        if !visibleChannels.contains(where: { $0.id == selectedChannelID }) {
            selectedChannelID = visibleChannels.first(where: { $0.name == "general" })?.id ?? visibleChannels.first?.id
        }
        beginMemberLoad(for: guildID)
    }

    func loadEmojis(for guildID: GuildID) async {
        guard emojisByGuild[guildID] == nil, !loadingEmojiGuildIDs.contains(guildID) else { return }
        loadingEmojiGuildIDs.insert(guildID)
        defer { loadingEmojiGuildIDs.remove(guildID) }
        do {
            emojisByGuild[guildID] = try await provider.emojis(in: guildID)
            emojiLoadErrorsByGuild[guildID] = nil
        } catch {
            emojiLoadErrorsByGuild[guildID] = error.localizedDescription
        }
    }

    func retryEmojis(for guildID: GuildID) async {
        emojisByGuild[guildID] = nil
        emojiLoadErrorsByGuild[guildID] = nil
        await loadEmojis(for: guildID)
    }

    func loadDiscordEmojiSettings() async {
        guard !didAttemptDiscordEmojiSettings else { return }
        didAttemptDiscordEmojiSettings = true
        guard let settings = try? await provider.emojiUserSettings() else { return }
        discordFavoriteEmojiKeys = settings.favoriteKeys
        discordEmojiUsageScores = settings.usageScores
    }

    func recordEmojiUse(_ key: String) {
        emojiUsageCounts[key, default: 0] += 1
        UserDefaults.standard.set(emojiUsageCounts, forKey: "dev.swiftchat.emoji-usage")
    }

    func toggleFavoriteEmoji(_ key: String) {
        if favoriteEmojiKeys.contains(key) { favoriteEmojiKeys.remove(key) }
        else { favoriteEmojiKeys.insert(key) }
        UserDefaults.standard.set(Array(favoriteEmojiKeys), forKey: "dev.swiftchat.favorite-emojis")
    }

    func composerText(for emoji: DiscordEmoji) -> String {
        let hasNitro = (snapshot?.currentUser.premiumType ?? 0) > 0
        if emoji.guildID != selectedGuildID, !hasNitro { return emoji.linkedImageMarkdown }
        return emoji.messageToken
    }

    private func beginMemberLoad(for guildID: GuildID?) {
        memberLoadTask?.cancel()
        memberLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await provider.members(in: guildID)
                guard !Task.isCancelled, selectedGuildID == guildID else { return }
                members = value
            } catch {
                guard !Task.isCancelled, selectedGuildID == guildID else { return }
                members = snapshot.map { [Member(user: $0.currentUser, roleName: "You", status: currentStatus)] } ?? []
            }
        }
    }

    private func beginSelectedChannelLoad() {
        channelLoadTask?.cancel()
        channelLoadGeneration &+= 1
        let generation = channelLoadGeneration
        messageLoadError = nil
        isLoadingEarlier = false
        typingTask?.cancel()
        typingText = nil
        replyingTo = nil

        guard let channelID = selectedChannelID, selectedChannel?.kind != .voice else {
            messages = []
            draft = ""
            hasMoreMessages = false
            isLoadingMessages = false
            return
        }

        messages = messageCache[channelID] ?? []
        hasMoreMessages = hasMoreCache[channelID] ?? false
        draft = ""
        isLoadingMessages = true
        channelLoadTask = Task { [weak self] in
            await self?.loadSelectedChannel(channelID, generation: generation)
        }
    }

    private func loadSelectedChannel(_ channelID: ChannelID, generation: Int) async {
        async let cachedMessages = storedMessages(in: channelID)
        async let storedDraft = storedDraft(in: channelID)
        async let freshPage = provider.messages(in: channelID, before: nil, limit: 100)

        let cached = await cachedMessages
        guard isCurrentLoad(channelID, generation: generation) else { return }
        if messages.isEmpty, !cached.isEmpty { messages = cached }

        let savedDraft = await storedDraft
        guard isCurrentLoad(channelID, generation: generation) else { return }
        if draft.isEmpty { draft = savedDraft }

        do {
            let page = try await freshPage
            guard isCurrentLoad(channelID, generation: generation) else { return }
            let merged = Self.merging(current: messages, fresh: page.messages)
            if merged != messages { messages = merged }
            hasMoreMessages = page.hasMoreBefore
            hasMoreCache[channelID] = page.hasMoreBefore
            messageLoadError = nil
            isLoadingMessages = false
            try await database?.save(messages: page.messages)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(channelID, generation: generation) else { return }
            messageLoadError = error.localizedDescription
            isLoadingMessages = false
        }
    }

    func loadEarlier() async {
        guard let channelID = selectedChannelID, let first = messages.first, hasMoreMessages, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        defer { if selectedChannelID == channelID { isLoadingEarlier = false } }
        do {
            let page = try await provider.messages(in: channelID, before: first.id, limit: 50)
            guard !Task.isCancelled, selectedChannelID == channelID else { return }
            let existingIDs = Set(messages.lazy.map(\.id))
            let earlier = page.messages.filter { !existingIDs.contains($0.id) }
            if !earlier.isEmpty { messages.insert(contentsOf: earlier, at: 0) }
            hasMoreMessages = page.hasMoreBefore
            hasMoreCache[channelID] = page.hasMoreBefore
            messageLoadError = nil
            try await database?.save(messages: page.messages)
        } catch is CancellationError {
            return
        } catch {
            guard selectedChannelID == channelID else { return }
            messageLoadError = error.localizedDescription
        }
    }

    func retryMessageLoad() {
        guard selectedChannelID != nil else { return }
        beginSelectedChannelLoad()
    }

    func reply(to message: Message) {
        guard message.channelID == selectedChannelID else { return }
        replyingTo = message
        NotificationCenter.default.post(name: .swiftchatFocusComposer, object: nil)
    }

    func cancelReply() {
        replyingTo = nil
    }

    func updateDraft(_ value: String) {
        draft = value
        guard let channelID = selectedChannelID else { return }
        Task { try? await database?.saveDraft(value, channelID: channelID) }
    }

    func send(attachments: [URL] = []) async {
        guard let channelID = selectedChannelID else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !attachments.isEmpty else { return }
        let replyTo = replyingTo?.id
        let replyPreview = replyingTo.map {
            MessageReplyPreview(messageID: $0.id, author: $0.author, content: $0.content)
        }
        let outgoing = SendMessageDraft(channelID: channelID, content: content, replyTo: replyTo, attachmentURLs: attachments)
        let optimistic = Message(
            id: MessageID(rawValue: UInt64.max - UInt64(messages.count)), channelID: channelID,
            author: snapshot?.currentUser ?? User(id: UserID(rawValue: 1), username: "me", displayName: "Me"),
            content: content, replyTo: replyTo, replyPreview: replyPreview, attachments: attachments.enumerated().map {
                Attachment(id: "pending-\($0.offset)", filename: $0.element.lastPathComponent, url: $0.element)
            }, nonce: outgoing.nonce, outboxState: .sending
        )
        messages.append(optimistic)
        replyingTo = nil
        updateDraft("")
        do {
            let confirmed = try await provider.send(outgoing)
            reconcile(confirmed)
            try await database?.save(messages: [confirmed])
        } catch {
            if let index = messages.firstIndex(where: { $0.nonce == outgoing.nonce }) { messages[index].outboxState = .failed }
            errorMessage = error.localizedDescription
        }
    }

    func edit(_ message: Message, content: String) async {
        do { reconcile(try await provider.edit(messageID: message.id, channelID: message.channelID, content: content)) }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ message: Message) async {
        do {
            try await provider.delete(messageID: message.id, channelID: message.channelID)
            if replyingTo?.id == message.id { replyingTo = nil }
        }
        catch { errorMessage = error.localizedDescription }
    }

    func toggleReaction(_ emoji: String, on message: Message) async {
        do { try await provider.toggleReaction(emoji, messageID: message.id, channelID: message.channelID) }
        catch { errorMessage = error.localizedDescription }
    }

    func updateStatus(_ status: PresenceStatus) async {
        do {
            try await provider.updateStatus(status)
            currentStatus = status
            members = members.map { member in
                guard member.user.id == snapshot?.currentUser.id else { return member }
                var updatedMember = member
                updatedMember.status = status
                return updatedMember
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func joinVoice(_ channel: Channel) async {
        guard channel.kind == .voice else { return }
        if activeVoiceChannel?.id == channel.id,
           voiceSessionState == .connected || voiceSessionState == .connecting { return }
        await leaveVoice()
        activeVoiceChannel = channel
        voiceSessionState = .connecting
        voiceErrorMessage = nil
        do {
            let info = try await provider.joinVoice(
                channelID: channel.id,
                guildID: channel.guildID,
                selfMute: isVoiceMuted,
                selfDeaf: isVoiceDeafened
            )
            try await startVoiceSession(with: info)
        } catch {
            voiceEventTask?.cancel()
            voiceEventTask = nil
            await voiceSession?.disconnect()
            voiceSessionState = .failed
            voiceErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            try? await provider.updateVoiceState(
                channelID: nil,
                guildID: channel.guildID,
                selfMute: false,
                selfDeaf: false,
                selfVideo: false
            )
            activeVoiceChannel = nil
            voiceSession = nil
        }
    }

    func leaveVoice() async {
        let guildID = activeVoiceChannel?.guildID
        voiceMigrationGeneration &+= 1
        voiceMigrationTask?.cancel()
        voiceMigrationTask = nil
        voiceEventTask?.cancel()
        voiceEventTask = nil
        await voiceSession?.disconnect()
        voiceSession = nil
        if activeVoiceChannel != nil {
            try? await provider.updateVoiceState(
                channelID: nil,
                guildID: guildID,
                selfMute: false,
                selfDeaf: false,
                selfVideo: false
            )
        }
        activeVoiceChannel = nil
        voiceParticipants = []
        isLocallySpeaking = false
        voiceVideoFrames = [:]
        if let ownUserID = snapshot?.currentUser.id { voiceStates[ownUserID] = nil }
        voiceEncryptionVersion = nil
        voiceLatencyMilliseconds = nil
        voiceSessionState = .idle
        isCameraEnabled = false
    }

    func toggleVoiceMute() async {
        isVoiceMuted.toggle()
        UserDefaults.standard.set(isVoiceMuted, forKey: "voiceMuted")
        await voiceSession?.setMuted(isVoiceMuted)
        await publishVoiceState()
    }

    func toggleVoiceDeafen() async {
        isVoiceDeafened.toggle()
        UserDefaults.standard.set(isVoiceDeafened, forKey: "voiceDeafened")
        await voiceSession?.setDeafened(isVoiceDeafened)
        await publishVoiceState()
    }

    func toggleCamera() async {
        let enabled = !isCameraEnabled
        if voiceSession == nil {
            isCameraEnabled = enabled
            await publishVoiceState()
            return
        }
        do {
            try await voiceSession?.setCameraEnabled(enabled)
            isCameraEnabled = enabled
            if !enabled, let ownUserID = snapshot?.currentUser.id {
                voiceVideoFrames[String(ownUserID.rawValue)] = nil
            }
            try await provider.updateVoiceState(
                channelID: activeVoiceChannel?.id,
                guildID: activeVoiceChannel?.guildID,
                selfMute: isVoiceMuted,
                selfDeaf: isVoiceDeafened,
                selfVideo: enabled
            )
        } catch {
            voiceErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func selectCamera(_ camera: CameraDeviceInfo?) async {
        UserDefaults.standard.set(camera?.uniqueID, forKey: "voiceCameraUID")
        do { try await voiceSession?.selectCamera(uniqueID: camera?.uniqueID) }
        catch {
            voiceErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func updateInputVolume(_ value: Float) async {
        inputVolume = min(max(value, 0), 2)
        UserDefaults.standard.set(Double(inputVolume), forKey: "voiceInputVolume")
        await voiceSession?.setInputVolume(inputVolume)
    }

    func updateOutputVolume(_ value: Float) async {
        outputVolume = min(max(value, 0), 2)
        UserDefaults.standard.set(Double(outputVolume), forKey: "voiceOutputVolume")
        await voiceSession?.setOutputVolume(outputVolume)
    }

    func selectInputDevice(_ device: AudioDeviceInfo?) async {
        UserDefaults.standard.set(device?.uid, forKey: "voiceInputDeviceUID")
        do { try await voiceSession?.selectInputDevice(device?.id) }
        catch { errorMessage = error.localizedDescription }
    }

    func selectOutputDevice(_ device: AudioDeviceInfo?) async {
        UserDefaults.standard.set(device?.uid, forKey: "voiceOutputDeviceUID")
        do { try await voiceSession?.selectOutputDevice(device?.id) }
        catch { errorMessage = error.localizedDescription }
    }

    func updateParticipantVolume(_ value: Float, userID: String) async {
        await voiceSession?.setParticipantVolume(value, userID: userID)
    }

    func refreshMediaDevices() {
        mediaDevices = MediaDeviceCatalog.snapshot()
    }

    private func publishVoiceState() async {
        guard let activeVoiceChannel else { return }
        do {
            try await provider.updateVoiceState(
                channelID: activeVoiceChannel.id,
                guildID: activeVoiceChannel.guildID,
                selfMute: isVoiceMuted,
                selfDeaf: isVoiceDeafened,
                selfVideo: isCameraEnabled
            )
        } catch {
            voiceErrorMessage = error.localizedDescription
        }
    }

    private func selectedAudioDeviceID(defaultsKey: String, devices: [AudioDeviceInfo]) -> AudioDeviceID? {
        guard let uid = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        return devices.first(where: { $0.uid == uid })?.id
    }

    private func currentVoiceConfiguration() -> VoiceSessionConfiguration {
        let outputDeviceID = selectedAudioDeviceID(
            defaultsKey: "voiceOutputDeviceUID",
            devices: mediaDevices.audioOutputs
        )
        return VoiceSessionConfiguration(
            inputDeviceID: resolvedInputDeviceID(),
            outputDeviceID: outputDeviceID,
            inputVolume: inputVolume,
            outputVolume: outputVolume,
            isMuted: isVoiceMuted,
            isDeafened: isVoiceDeafened,
            cameraUniqueID: UserDefaults.standard.string(forKey: "voiceCameraUID")
        )
    }

    private func resolvedInputDeviceID() -> AudioDeviceID? {
        if let storedUID = UserDefaults.standard.string(forKey: "voiceInputDeviceUID"),
           !storedUID.isEmpty {
            return mediaDevices.audioInputs.first(where: { $0.uid == storedUID })?.id
        }

        let defaultInput = mediaDevices.audioInputs.first(where: \.isDefault)
        // Automatic capture must not inherit a Bluetooth call route or a
        // silent virtual/aggregate device. Explicit selections remain honored.
        if defaultInput?.isBluetooth == true || defaultInput?.isVirtual == true,
           let builtIn = mediaDevices.audioInputs.first(where: \.isBuiltIn) {
            return builtIn.id
        }
        return nil
    }

    private func startVoiceSession(with info: VoiceConnectionInfo) async throws {
        if info.endpoint == "mock.swiftchat.invalid" {
            voiceSessionState = .connected
            return
        }

        let session = DiscordVoiceSession(info: info, configuration: currentVoiceConfiguration())
        voiceSession = session
        voiceEventTask?.cancel()
        voiceEventTask = Task { [weak self] in
            for await event in session.events {
                guard !Task.isCancelled else { return }
                self?.consumeVoiceEvent(event)
            }
        }
        try await session.connect()
    }

    private func scheduleVoiceServerMigration(to info: VoiceConnectionInfo?) {
        voiceMigrationGeneration &+= 1
        let generation = voiceMigrationGeneration
        voiceMigrationTask?.cancel()
        voiceMigrationTask = Task { [weak self] in
            await self?.migrateVoiceServer(to: info, generation: generation)
        }
    }

    private func migrateVoiceServer(to info: VoiceConnectionInfo?, generation: Int) async {
        guard activeVoiceChannel != nil, generation == voiceMigrationGeneration else { return }
        let cameraWasEnabled = isCameraEnabled

        voiceEventTask?.cancel()
        voiceEventTask = nil
        await voiceSession?.disconnect()
        guard !Task.isCancelled, generation == voiceMigrationGeneration else { return }

        voiceSession = nil
        voiceParticipants = []
        voiceVideoFrames = [:]
        voiceEncryptionVersion = nil
        voiceLatencyMilliseconds = nil
        isCameraEnabled = false
        voiceSessionState = .reconnecting

        guard let info else { return }
        guard info.channelID == activeVoiceChannel?.id else { return }

        do {
            try await startVoiceSession(with: info)
            guard !Task.isCancelled, generation == voiceMigrationGeneration else {
                await voiceSession?.disconnect()
                return
            }
            if cameraWasEnabled, voiceSession != nil {
                try await voiceSession?.setCameraEnabled(true)
                isCameraEnabled = true
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == voiceMigrationGeneration else { return }
            voiceSessionState = .failed
            voiceErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func consumeVoiceEvent(_ event: VoiceSessionEvent) {
        switch event {
        case let .stateChanged(state):
            voiceSessionState = state
        case let .latencyUpdated(milliseconds):
            voiceLatencyMilliseconds = milliseconds
        case let .participantChanged(participant):
            if let index = voiceParticipants.firstIndex(where: { $0.userID == participant.userID }) {
                voiceParticipants[index] = participant
            } else {
                voiceParticipants.append(participant)
            }
            voiceParticipants.sort { $0.userID < $1.userID }
            if let userID = UserID(participant.userID), var state = voiceStates[userID] {
                state.isVideoEnabled = participant.isCameraEnabled
                voiceStates[userID] = state
            }
        case let .participantLeft(userID):
            voiceParticipants.removeAll { $0.userID == userID }
            voiceVideoFrames[userID] = nil
        case let .localSpeakingChanged(speaking):
            isLocallySpeaking = speaking
        case let .encryptionReady(version):
            voiceEncryptionVersion = version
        case let .videoFrame(userID, frame):
            voiceVideoFrames[userID] = frame
        case let .videoStopped(userID):
            voiceVideoFrames[userID] = nil
        case let .error(message):
            voiceErrorMessage = message
        }
    }

    func selectMember(_ member: Member) {
        if selectedMember?.id == member.id {
            dismissProfile()
            return
        }
        presentProfile(for: member)
    }

    func showProfile(for user: User) {
        showInspector = true
        let member = members.first(where: { $0.id == user.id })
            ?? Member(user: user, roleName: "Member", status: .offline)
        presentProfile(for: member)
    }

    private func presentProfile(for member: Member) {
        profileTask?.cancel()
        selectedMember = member
        selectedProfile = nil
        profileErrorMessage = nil
        isLoadingProfile = true
        let guildID = selectedGuildID
        profileTask = Task { [weak self] in
            guard let self else { return }
            do {
                var value = try await provider.profile(for: member.id, in: guildID)
                guard !Task.isCancelled, selectedMember?.id == member.id, selectedGuildID == guildID else { return }
                value.status = member.status
                value.customStatus = member.customStatus
                selectedProfile = value
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedMember?.id == member.id else { return }
                profileErrorMessage = error.localizedDescription
            }
            if selectedMember?.id == member.id { isLoadingProfile = false }
        }
    }

    func dismissProfile() {
        profileTask?.cancel()
        profileTask = nil
        selectedMember = nil
        selectedProfile = nil
        isLoadingProfile = false
        profileErrorMessage = nil
    }

    func dismissError() { errorMessage = nil }

    private func storedMessages(in channelID: ChannelID) async -> [Message] {
        (try? await database?.messages(in: channelID)) ?? []
    }

    private func storedDraft(in channelID: ChannelID) async -> String {
        (try? await database?.draft(channelID: channelID)) ?? ""
    }

    private func isCurrentLoad(_ channelID: ChannelID, generation: Int) -> Bool {
        !Task.isCancelled && selectedChannelID == channelID && channelLoadGeneration == generation
    }

    private static func merging(current: [Message], fresh: [Message]) -> [Message] {
        var byID: [MessageID: Message] = [:]
        for message in current { byID[message.id] = message }
        for message in fresh {
            var resolved = message
            if let existing = byID[message.id] {
                resolved.replyTo = resolved.replyTo ?? existing.replyTo
                resolved.replyPreview = resolved.replyPreview ?? existing.replyPreview
            }
            byID[resolved.id] = resolved
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
    }

    private func consume(_ event: ClientEvent) {
        switch event {
        case let .connectionChanged(state): connectionState = state
        case let .messageCreated(message):
            persist(message)
            if message.channelID == selectedChannelID { reconcile(message) }
            else { cache(message) }
        case let .messageUpdated(message):
            persist(message)
            if message.channelID == selectedChannelID { reconcile(message) }
            else { cache(message) }
        case let .messageDeleted(channelID, messageID):
            Task { try? await database?.deleteMessage(messageID) }
            if replyingTo?.id == messageID { replyingTo = nil }
            if channelID == selectedChannelID {
                messages.removeAll { $0.id == messageID }
            } else {
                messageCache[channelID]?.removeAll { $0.id == messageID }
            }
        case let .typing(channelID, user):
            guard channelID == selectedChannelID else { return }
            typingText = "\(user.displayName) is typing…"
            typingTask?.cancel()
            typingTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.typingText = nil
            }
        case let .membersChanged(guildID, value):
            guard guildID == selectedGuildID else { return }
            members = value
            if let selectedMember, let updated = value.first(where: { $0.id == selectedMember.id }) {
                self.selectedMember = updated
            }
        case let .voiceStateChanged(state):
            if state.channelID == nil { voiceStates[state.userID] = nil }
            else { voiceStates[state.userID] = state }
            if !state.isVideoEnabled { voiceVideoFrames[String(state.userID.rawValue)] = nil }
        case let .voiceServerChanged(info):
            scheduleVoiceServerMigration(to: info)
        case let .snapshotChanged(value):
            snapshot = value
            selectGuild(selectedGuildID)
        }
    }

    private func reconcile(_ message: Message) {
        var updated = messages
        var resolved = message
        if let nonce = message.nonce, let index = updated.firstIndex(where: { $0.nonce == nonce }) {
            resolved.replyTo = resolved.replyTo ?? updated[index].replyTo
            resolved.replyPreview = resolved.replyPreview ?? updated[index].replyPreview
            updated[index] = resolved
        } else if let index = updated.firstIndex(where: { $0.id == message.id }) {
            resolved.replyTo = resolved.replyTo ?? updated[index].replyTo
            resolved.replyPreview = resolved.replyPreview ?? updated[index].replyPreview
            updated[index] = resolved
        } else {
            updated.append(resolved)
        }
        var messagesByID: [MessageID: Message] = [:]
        for value in updated { messagesByID[value.id] = value }
        updated = messagesByID.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
        if updated != messages { messages = updated }
    }

    private func persist(_ message: Message) {
        Task { try? await database?.save(messages: [message]) }
    }

    private func cache(_ message: Message) {
        let current = messageCache[message.channelID] ?? []
        messageCache[message.channelID] = Self.merging(current: current, fresh: [message])
    }
}

struct MessageRowPresentation: Identifiable, Equatable {
    var id: MessageID { message.id }
    let message: Message
    let startsGroup: Bool
    let replyPreview: MessageReplyPreview?
}

enum MessageGrouping {
    // Discord's current cozy layout uses a seven-minute continuation barrier.
    private static let continuationInterval: TimeInterval = 7 * 60

    static func rows(for messages: [Message], calendar: Calendar = .autoupdatingCurrent) -> [MessageRowPresentation] {
        var messagesByID: [MessageID: Message] = [:]
        for message in messages { messagesByID[message.id] = message }
        return messages.enumerated().map { index, message in
            let replyPreview = message.replyTo.flatMap { messageID -> MessageReplyPreview? in
                if let referenced = messagesByID[messageID] {
                    return MessageReplyPreview(messageID: referenced.id, author: referenced.author, content: referenced.content)
                }
                return message.replyPreview
            }
            guard index > 0 else {
                return MessageRowPresentation(message: message, startsGroup: true, replyPreview: replyPreview)
            }
            let previous = messages[index - 1]
            let continues = previous.author.id == message.author.id
                && message.replyTo == nil
                && previous.replyTo == nil
                && message.timestamp.timeIntervalSince(previous.timestamp) >= 0
                && message.timestamp.timeIntervalSince(previous.timestamp) < continuationInterval
                && calendar.isDate(previous.timestamp, inSameDayAs: message.timestamp)
            return MessageRowPresentation(message: message, startsGroup: !continues, replyPreview: replyPreview)
        }
    }
}
