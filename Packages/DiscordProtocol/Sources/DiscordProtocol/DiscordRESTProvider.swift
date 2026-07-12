import SwiftchatModels
import Foundation
import OSLog

private let gatewayLogger = Logger(subsystem: "dev.swiftchat.Swiftchat", category: "Gateway")

public actor DiscordRESTProvider: ChatProvider {
    private let credentials: any CredentialStore
    private let handle: CredentialHandle
    private let session: URLSession
    private var continuation: AsyncStream<ClientEvent>.Continuation?
    private var currentUser: User?
    private var authorizationValue: String?
    private var cachedMessages: [MessageID: Message] = [:]
    private var cachedChannels: [GuildID?: [Channel]] = [:]
    private var presenceStatus: PresenceStatus = .invisible
    private var globalRateLimitDate: Date = .distantPast
    private var routeRateLimitDates: [String: Date] = [:]
    private var webSocket: URLSessionWebSocketTask?
    private var gatewayTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var gatewaySequence: Int?
    private var gatewayReady = false
    private var pendingMemberGuildID: GuildID?
    private var cachedMembers: [GuildID: [Member]] = [:]
    private var cachedMemberListItems: [GuildID: [GuildMemberListUpdateDTO.Item?]] = [:]
    private var cachedGuildRoles: [GuildID: [GuildRoleDTO]] = [:]
    private var cachedGuilds: [GuildID: Guild] = [:]
    private var cachedProfiles: [ProfileCacheKey: UserProfile] = [:]
    private var profileEffects: [String: ProfileEffectConfigDTO]?

    public init(credentials: any CredentialStore, handle: CredentialHandle, session: URLSession = .shared) {
        self.credentials = credentials
        self.handle = handle
        self.session = session
    }

    public func bootstrap() async throws -> BootstrapSnapshot {
        continuation?.yield(.connectionChanged(.connecting))
        _ = try await authorizationToken()
        async let userRequest: UserDTO = request("/users/@me")
        async let guildRequest: [GuildDTO] = request("/users/@me/guilds")
        async let directMessageRequest: [ChannelDTO] = request("/users/@me/channels")
        let (userDTO, guildDTOs, dmDTOs) = try await (userRequest, guildRequest, directMessageRequest)
        let user = try userDTO.domain()
        currentUser = user
        let guilds = try guildDTOs.map { try $0.domain() }
        cachedGuilds = Dictionary(uniqueKeysWithValues: guilds.map { ($0.id, $0) })
        let channels = try dmDTOs.map { try $0.domain(guildID: nil) }
        cachedChannels[nil] = channels
        presenceStatus = UserDefaults.standard.string(forKey: statusDefaultsKey).flatMap(PresenceStatus.init(rawValue:)) ?? .invisible
        let members = [Member(user: user, roleName: "You", status: presenceStatus)]
        try await startGateway()
        continuation?.yield(.connectionChanged(.ready))
        return BootstrapSnapshot(currentUser: user, guilds: guilds, channels: channels, members: members)
    }

    public func channels(in guildID: GuildID?) async throws -> [Channel] {
        if let cached = cachedChannels[guildID] { return cached }
        guard let guildID else { return cachedChannels[nil] ?? [] }
        let values: [ChannelDTO] = try await request("/guilds/\(guildID)/channels")
        let categories = Dictionary(uniqueKeysWithValues: values.filter { $0.type == 4 }.map { ($0.id, $0) })
        let channels = try values.filter { $0.type != 4 }.map { dto in
            let category = dto.parentID.flatMap { categories[$0] }
            return try dto.domain(
                guildID: guildID,
                categoryName: category?.name,
                categoryPosition: category?.position ?? -1
            )
        }
        .sorted { lhs, rhs in
            if lhs.categoryPosition != rhs.categoryPosition { return lhs.categoryPosition < rhs.categoryPosition }
            return lhs.position < rhs.position
        }
        cachedChannels[guildID] = channels
        return channels
    }

    public func members(in guildID: GuildID?) async throws -> [Member] {
        guard let guildID else {
            return cachedChannels[nil]?.flatMap(\.recipients).map { Member(user: $0, roleName: "Direct Message", status: .offline) } ?? []
        }
        if cachedGuildRoles[guildID] == nil {
            do {
                let roles: [GuildRoleDTO] = try await request("/guilds/\(guildID)/roles")
                cachedGuildRoles[guildID] = roles
            } catch {
                gatewayLogger.warning("Guild roles unavailable; member categories will use the default group: \(error.localizedDescription, privacy: .public)")
                cachedGuildRoles[guildID] = []
            }
        }
        pendingMemberGuildID = guildID
        gatewayLogger.info("Member list requested; gatewayReady=\(self.gatewayReady)")
        if gatewayReady { await attemptMemberSubscription(guildID: guildID) }
        return cachedMembers[guildID] ?? []
    }

    public func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        let key = ProfileCacheKey(userID: userID, guildID: guildID)
        if let cached = cachedProfiles[key] { return cached }

        var query = [
            URLQueryItem(name: "with_mutual_guilds", value: "true"),
            URLQueryItem(name: "with_mutual_friends", value: "true"),
            URLQueryItem(name: "with_mutual_friends_count", value: "true"),
        ]
        if let guildID { query.append(URLQueryItem(name: "guild_id", value: guildID.description)) }
        let dto: UserProfileDTO = try await request("/users/\(userID)/profile", query: query)

        let effectID = dto.guildMemberProfile?.profileEffect?.resolvedID ?? dto.userProfile?.profileEffect?.resolvedID
        if effectID != nil, profileEffects == nil {
            let locale = Locale.preferredLanguages.first ?? "en-US"
            let response: ProfileEffectsDTO? = try? await request(
                "/user-profile-effects",
                query: [URLQueryItem(name: "locale", value: locale)]
            )
            var effectsByID: [String: ProfileEffectConfigDTO] = [:]
            for effect in response?.profileEffectConfigs?.elements ?? [] {
                if let id = effect.id { effectsByID[id] = effect }
                if let skuID = effect.skuID { effectsByID[skuID] = effect }
            }
            profileEffects = effectsByID
        }
        if let effectID, profileEffects?[effectID] == nil {
            let product: CollectibleProductDTO? = try? await request("/collectibles-products/\(effectID)")
            for effect in product?.items?.elements.filter({ $0.type == 1 }) ?? [] {
                if let id = effect.id { profileEffects?[id] = effect }
                if let skuID = effect.skuID { profileEffects?[skuID] = effect }
            }
        }

        let profile = try dto.domain(
            guildID: guildID,
            guilds: cachedGuilds,
            guildRoles: guildID.flatMap { cachedGuildRoles[$0] } ?? [],
            effectConfig: effectID.flatMap { profileEffects?[$0] }
        )
        gatewayLogger.debug(
            "Profile assets resolved; bio=\(profile.bio?.isEmpty == false), badges=\(profile.badges.count), effect=\(profile.effect != nil), animations=\(profile.effect?.animations.count ?? 0)"
        )
        cachedProfiles[key] = profile
        return profile
    }

    private func searchGuildMembers(guildID: GuildID) async throws -> [GuildMemberSearchResultDTO] {
        for attempt in 0..<3 {
            let (data, response) = try await perform(
                "/guilds/\(guildID)/members/search",
                method: "GET",
                query: [URLQueryItem(name: "query", value: ""), URLQueryItem(name: "limit", value: "1000")],
                body: nil
            )
            if response.statusCode == 202, attempt < 2 {
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let delay = min(max((object?["retry_after"] as? NSNumber)?.doubleValue ?? 1, 0.5), 5)
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                throw ChatProviderError.transport(status: response.statusCode, requestID: response.value(forHTTPHeaderField: "x-request-id"))
            }
            return try JSONDecoder().decode([GuildMemberSearchResultDTO].self, from: data)
        }
        return []
    }

    public func currentStatus() async -> PresenceStatus { presenceStatus }

    public func updateStatus(_ status: PresenceStatus) async throws {
        try await sendGateway([
            "op": 3,
            "d": ["since": 0, "activities": [], "status": status.rawValue, "afk": false] as [String: Any],
        ])
        presenceStatus = status
        UserDefaults.standard.set(status.rawValue, forKey: statusDefaultsKey)
    }

    private var statusDefaultsKey: String { "dev.swiftchat.presence.\(handle.accountID)" }

    public func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage {
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))]
        if let before { query.append(URLQueryItem(name: "before", value: before.description)) }
        let payload: LossyList<MessageDTO> = try await request("/channels/\(channelID)/messages", query: query)
        if payload.skippedCount > 0 {
            gatewayLogger.warning("Skipped \(payload.skippedCount) unsupported message payloads in channel \(channelID)")
        }
        let values = payload.elements.compactMap { try? $0.domain() }.sorted { $0.timestamp < $1.timestamp }
        for message in values { cachedMessages[message.id] = message }
        return MessagePage(messages: values, hasMoreBefore: values.count == min(max(limit, 1), 100))
    }

    public func send(_ draft: SendMessageDraft) async throws -> Message {
        var body: [String: JSONValue] = [
            "content": .string(draft.content),
            "nonce": .string(draft.nonce),
            "tts": .bool(false),
            "flags": .number(0),
        ]
        if let replyTo = draft.replyTo {
            body["message_reference"] = .object(["message_id": .string(replyTo.description)])
        }
        if !draft.attachmentURLs.isEmpty {
            body["attachments"] = .array(try await uploadAttachments(draft.attachmentURLs, channelID: draft.channelID))
        }
        let dto: MessageDTO = try await request("/channels/\(draft.channelID)/messages", method: "POST", body: body)
        var message = try dto.domain()
        message.nonce = draft.nonce
        cachedMessages[message.id] = message
        continuation?.yield(.messageCreated(message))
        return message
    }

    private func uploadAttachments(_ urls: [URL], channelID: ChannelID) async throws -> [JSONValue] {
        var descriptors: [JSONValue] = []
        for (index, url) in urls.enumerated() {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            descriptors.append(.object([
                "filename": .string(url.lastPathComponent),
                "file_size": .number(Double(size)),
                "id": .string(String(index)),
                "is_clip": .bool(false),
            ]))
        }

        let reservation: AttachmentReservationDTO = try await request(
            "/channels/\(channelID)/attachments",
            method: "POST",
            body: ["files": .array(descriptors)]
        )
        guard reservation.attachments.count == urls.count else {
            throw ChatProviderError.invalidRequest("Discord did not reserve every selected attachment.")
        }

        var uploaded: [JSONValue] = []
        for pair in zip(urls, reservation.attachments) {
            let (fileURL, slot) = pair
            guard let uploadURL = URL(string: slot.uploadURL) else {
                throw ChatProviderError.invalidRequest("Discord returned an invalid attachment upload URL.")
            }
            let accessed = fileURL.startAccessingSecurityScopedResource()
            defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
            var uploadRequest = URLRequest(url: uploadURL)
            uploadRequest.httpMethod = "PUT"
            uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, rawResponse) = try await session.upload(for: uploadRequest, fromFile: fileURL)
            guard let response = rawResponse as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw ChatProviderError.invalidRequest("Discord's attachment storage rejected \(fileURL.lastPathComponent).")
            }
            uploaded.append(.object([
                "id": .string(String(slot.id)),
                "filename": .string(fileURL.lastPathComponent),
                "uploaded_filename": .string(slot.uploadFilename),
            ]))
        }
        return uploaded
    }

    public func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message {
        let dto: MessageDTO = try await request("/channels/\(channelID)/messages/\(messageID)", method: "PATCH", body: ["content": .string(content)])
        let message = try dto.domain()
        cachedMessages[message.id] = message
        continuation?.yield(.messageUpdated(message))
        return message
    }

    public func delete(messageID: MessageID, channelID: ChannelID) async throws {
        try await requestEmpty("/channels/\(channelID)/messages/\(messageID)", method: "DELETE")
        cachedMessages[messageID] = nil
        continuation?.yield(.messageDeleted(channelID: channelID, messageID: messageID))
    }

    public func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {
        guard var message = cachedMessages[messageID] else { throw ChatProviderError.messageNotFound }
        let encoded = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? emoji
        let existing = message.reactions.firstIndex { $0.emoji == emoji }
        let reacted = existing.map { message.reactions[$0].didCurrentUserReact } ?? false
        let method = reacted ? "DELETE" : "PUT"
        try await requestEmpty("/channels/\(channelID)/messages/\(messageID)/reactions/\(encoded)/@me", method: method)
        if let index = existing {
            message.reactions[index].didCurrentUserReact.toggle()
            message.reactions[index].count += reacted ? -1 : 1
            if message.reactions[index].count <= 0 { message.reactions.remove(at: index) }
        } else {
            message.reactions.append(Reaction(emoji: emoji, count: 1, didCurrentUserReact: true))
        }
        cachedMessages[messageID] = message
        continuation?.yield(.messageUpdated(message))
    }

    public func eventStream() async -> AsyncStream<ClientEvent> {
        let stream = AsyncStream<ClientEvent>.makeStream(bufferingPolicy: .bufferingNewest(500))
        continuation = stream.continuation
        return stream.stream
    }

    public func disconnect() async {
        gatewayTask?.cancel()
        heartbeatTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        continuation?.yield(.connectionChanged(.disconnected))
        continuation?.finish()
        continuation = nil
        authorizationValue = nil
    }

    private func startGateway() async throws {
        guard webSocket == nil else { return }
        let socket = session.webSocketTask(with: URL(string: "wss://gateway.discord.gg/?encoding=json&v=9")!)
        webSocket = socket
        socket.resume()
        gatewayTask = Task { [weak self] in await self?.receiveGatewayEvents() }
    }

    private func receiveGatewayEvents() async {
        guard let webSocket else { return }
        while !Task.isCancelled {
            do {
                let message = try await webSocket.receive()
                let data: Data = switch message {
                case let .data(value): value
                case let .string(value): Data(value.utf8)
                @unknown default: Data()
                }
                guard
                    let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let op = payload["op"] as? Int
                else { continue }
                if let sequence = payload["s"] as? Int { gatewaySequence = sequence }
                if op == 10, let hello = payload["d"] as? [String: Any], let interval = hello["heartbeat_interval"] as? NSNumber {
                    startHeartbeat(interval: interval.doubleValue / 1_000)
                    try await identifyGateway()
                } else if op == 0, let eventName = payload["t"] as? String, let body = payload["d"] {
                    await handleGatewayDispatch(name: eventName, body: body)
                } else if op == 7 {
                    webSocket.cancel(with: .goingAway, reason: nil)
                    self.webSocket = nil
                    try? await Task.sleep(for: .seconds(1))
                    try? await startGateway()
                    return
                }
            } catch {
                continuation?.yield(.connectionChanged(.backingOff))
                break
            }
        }
    }

    private func identifyGateway() async throws {
        let credential = try await credentials.credential(for: handle)
        guard let token = String(data: credential, encoding: .utf8) else { throw ChatProviderError.unauthenticated }
        let properties: [String: Any] = [
            "os": "Mac OS X",
            "browser": "Discord Client",
            "device": "Discord Client",
            "system_locale": Locale.preferredLanguages.first ?? "en-US",
            "browser_user_agent": "Swiftchat/0.1 (macOS; native Swift client)",
            "browser_version": DiscordProductionBaseline.july2026.desktopVersion,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "referrer": "",
            "referring_domain": "",
            "release_channel": "stable",
            "client_build_number": DiscordProductionBaseline.july2026.webBuildNumber,
            "client_event_source": NSNull(),
            "has_client_mods": false,
        ]
        try await sendGateway([
            "op": 2,
            "d": [
                "token": token,
                "capabilities": DiscordProductionBaseline.july2026.defaultCapabilities,
                "properties": properties,
                "presence": ["status": presenceStatus.rawValue, "since": 0, "activities": [], "afk": false],
                "compress": false,
                "client_state": ["guild_versions": [:]],
            ] as [String: Any],
        ])
    }

    private func startHeartbeat(interval: TimeInterval) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            let initialDelay = Double.random(in: 0...max(0.1, interval))
            try? await Task.sleep(for: .seconds(initialDelay))
            while !Task.isCancelled {
                guard let self else { return }
                try? await self.sendGateway(["op": 1, "d": await self.gatewaySequence ?? NSNull()])
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func subscribeToMemberList(guildID: GuildID) async throws {
        let channel = cachedChannels[guildID]?.first(where: { $0.kind != .voice })
        try await sendGateway(DiscordGatewayPayloadFactory.guildSubscriptions(
            guildID: guildID,
            channelID: channel?.id
        ))
        gatewayLogger.info("Sent current bulk guild subscription with member-list range")
    }

    private func attemptMemberSubscription(guildID: GuildID) async {
        do { try await subscribeToMemberList(guildID: guildID) }
        catch { gatewayLogger.error("Lazy member-list subscription failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func sendGateway(_ payload: [String: Any]) async throws {
        guard let webSocket else { throw ChatProviderError.invalidRequest("Discord Gateway is not connected yet.") }
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await webSocket.send(.data(data))
    }

    private func handleGatewayDispatch(name: String, body: Any) async {
        guard JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        switch name {
        case "READY", "RESUMED":
            gatewayReady = true
            gatewayLogger.info("Gateway session ready")
            continuation?.yield(.connectionChanged(.ready))
            if let pendingMemberGuildID { await attemptMemberSubscription(guildID: pendingMemberGuildID) }
        case "MESSAGE_CREATE":
            if let dto = try? JSONDecoder().decode(MessageDTO.self, from: data), let message = try? dto.domain() {
                cachedMessages[message.id] = message
                continuation?.yield(.messageCreated(message))
            }
        case "MESSAGE_UPDATE":
            if let update = try? JSONDecoder().decode(MessageUpdateDTO.self, from: data),
               let messageID = MessageID(update.id), ChannelID(update.channelID) != nil,
               var message = cachedMessages[messageID] {
                if let content = update.content { message.content = content }
                if let edited = update.editedTimestamp { message.editedTimestamp = DiscordDate.parse(edited) }
                if let attachments = update.attachments, let values = try? attachments.map({ try $0.domain() }) { message.attachments = values }
                cachedMessages[messageID] = message
                continuation?.yield(.messageUpdated(message))
            }
        case "MESSAGE_DELETE":
            if let value = try? JSONDecoder().decode(MessageDeleteDTO.self, from: data),
               let channelID = ChannelID(value.channelID), let messageID = MessageID(value.id) {
                continuation?.yield(.messageDeleted(channelID: channelID, messageID: messageID))
            }
        case "GUILD_MEMBER_LIST_UPDATE":
            guard let update = try? JSONDecoder().decode(GuildMemberListUpdateDTO.self, from: data), let guildID = GuildID(update.guildID) else {
                gatewayLogger.error("Member-list update could not be decoded; bytes=\(data.count)")
                return
            }
            let syncItemCount = update.ops.reduce(0) { $0 + ($1.items?.count ?? 0) }
            if syncItemCount > 0 {
                gatewayLogger.info("Member-list range synchronized; items=\(syncItemCount)")
            }
            applyMemberListOperations(update.ops, guildID: guildID)
            var seen = Set<UserID>()
            let members = (cachedMemberListItems[guildID] ?? []).compactMap { item -> Member? in
                guard let memberDTO = item?.member,
                      let member = try? memberDTO.domain(
                          currentUserID: currentUser?.id,
                          currentStatus: presenceStatus,
                          presence: item?.presence,
                          guildRoles: cachedGuildRoles[guildID] ?? [],
                          guildID: guildID
                      ),
                      seen.insert(member.id).inserted
                else { return nil }
                return member
            }
            cachedMembers[guildID] = members
            if guildID == pendingMemberGuildID {
                continuation?.yield(.membersChanged(guildID: guildID, members: members))
            }
        case "PRESENCE_UPDATE":
            guard let update = try? JSONDecoder().decode(PresenceUpdateDTO.self, from: data),
                  let guildID = GuildID(update.guildID), let userID = UserID(update.user.id),
                  let status = PresenceStatus(rawValue: update.status),
                  var members = cachedMembers[guildID],
                  let index = members.firstIndex(where: { $0.id == userID }) else { return }
            members[index].status = status
            if let activities = update.activities {
                members[index].customStatus = activities.first(where: { $0.type == 4 })?.displayText
                members[index].activityText = activities.first(where: { $0.type != 4 })?.displayText
                    ?? members[index].customStatus
            }
            cachedMembers[guildID] = members
            if guildID == pendingMemberGuildID {
                continuation?.yield(.membersChanged(guildID: guildID, members: members))
            }
        default:
            break
        }
    }

    private func applyMemberListOperations(_ operations: [GuildMemberListUpdateDTO.Operation], guildID: GuildID) {
        var items = cachedMemberListItems[guildID] ?? []
        for operation in operations {
            switch operation.op {
            case "SYNC":
                guard let range = operation.range, range.count == 2, let values = operation.items else { continue }
                let lower = max(0, range[0])
                let upper = max(lower, range[1])
                if items.count <= upper { items.append(contentsOf: repeatElement(nil, count: upper + 1 - items.count)) }
                for (offset, value) in values.enumerated() where lower + offset <= upper {
                    items[lower + offset] = value
                }
            case "INSERT":
                guard let index = operation.index, let item = operation.item else { continue }
                items.insert(item, at: min(max(0, index), items.count))
            case "UPDATE":
                guard let index = operation.index, index >= 0, let item = operation.item else { continue }
                if items.count <= index { items.append(contentsOf: repeatElement(nil, count: index + 1 - items.count)) }
                items[index] = item
            case "DELETE":
                guard let index = operation.index, items.indices.contains(index) else { continue }
                items.remove(at: index)
            case "INVALIDATE":
                guard let range = operation.range, range.count == 2, !items.isEmpty else { continue }
                let lower = max(0, range[0])
                let upper = min(items.count - 1, range[1])
                if lower <= upper {
                    for index in lower...upper { items[index] = nil }
                }
            default:
                continue
            }
        }
        cachedMemberListItems[guildID] = items
    }

    private func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil
    ) async throws -> Response {
        let (data, response) = try await perform(path, method: method, query: query, body: body)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                authorizationValue = nil
                throw ChatProviderError.unauthenticated
            }
            throw ChatProviderError.transport(status: response.statusCode, requestID: response.value(forHTTPHeaderField: "x-request-id"))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            gatewayLogger.error(
                "Discord response decoding failed for \(path, privacy: .public): \(String(reflecting: error), privacy: .public)"
            )
            throw error
        }
    }

    private func requestEmpty(_ path: String, method: String) async throws {
        let (_, response) = try await perform(path, method: method, query: [], body: nil)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                authorizationValue = nil
                throw ChatProviderError.unauthenticated
            }
            throw ChatProviderError.transport(status: response.statusCode, requestID: response.value(forHTTPHeaderField: "x-request-id"))
        }
    }

    private func perform(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: [String: JSONValue]?
    ) async throws -> (Data, HTTPURLResponse) {
        let routeKey = "\(method) \(path)"
        for attempt in 0..<6 {
            let requestDate = max(globalRateLimitDate, routeRateLimitDates[routeKey] ?? .distantPast)
            let delay = requestDate.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }

            var components = URLComponents(string: "https://discord.com/api/v\(DiscordProductionBaseline.july2026.apiVersion)\(path)")!
            if !query.isEmpty { components.queryItems = query }
            var request = URLRequest(url: components.url!)
            request.httpMethod = method
            request.timeoutInterval = 30
            let token = try await authorizationToken()
            request.setValue(token, forHTTPHeaderField: "Authorization")
            request.setValue("Swiftchat/0.1 (macOS; native Swift client)", forHTTPHeaderField: "User-Agent")
            let locale = Locale.preferredLanguages.first ?? "en-US"
            request.setValue(locale, forHTTPHeaderField: "X-Discord-Locale")
            request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Discord-Timezone")
            request.setValue(Locale.preferredLanguages.joined(separator: ","), forHTTPHeaderField: "Accept-Language")
            if let body {
                request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, rawResponse) = try await session.data(for: request)
            guard let response = rawResponse as? HTTPURLResponse else { throw ChatProviderError.invalidRequest("Discord returned an invalid HTTP response.") }

            if response.statusCode == 429 {
                let retryAfter = Self.retryAfter(from: data, response: response)
                let retryDate = Date.now.addingTimeInterval(retryAfter)
                if Self.isGlobalRateLimit(data: data, response: response) {
                    globalRateLimitDate = retryDate
                } else {
                    routeRateLimitDates[routeKey] = retryDate
                }
                if attempt == 5 { return (data, response) }
                continue
            }
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
               let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset-After").flatMap(Double.init) {
                routeRateLimitDates[routeKey] = .now.addingTimeInterval(max(0, reset))
            } else {
                routeRateLimitDates[routeKey] = nil
            }
            return (data, response)
        }
        throw ChatProviderError.invalidRequest("Discord rate limiting did not recover.")
    }

    private func authorizationToken() async throws -> String {
        if let authorizationValue { return authorizationValue }
        let credential = try await credentials.credential(for: handle)
        guard let value = String(data: credential, encoding: .utf8) else {
            throw ChatProviderError.unauthenticated
        }
        authorizationValue = value
        return value
    }

    private static func retryAfter(from data: Data, response: HTTPURLResponse) -> TimeInterval {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = object["retry_after"] as? NSNumber {
            return min(max(value.doubleValue, 0.25), 60) + 0.1
        }
        if let value = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) {
            return min(max(value, 0.25), 60) + 0.1
        }
        return 1.1
    }

    private static func isGlobalRateLimit(data: Data, response: HTTPURLResponse) -> Bool {
        if response.value(forHTTPHeaderField: "X-RateLimit-Global")?.lowercased() == "true" { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (object["global"] as? Bool) == true
    }
}

private struct ProfileCacheKey: Hashable {
    var userID: UserID
    var guildID: GuildID?
}

struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []
    var skippedCount = 0

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                skippedCount += 1
                _ = try? container.decode(JSONValue.self)
            }
        }
    }
}

private struct UserDTO: Decodable {
    struct AvatarDecorationDTO: Decodable { var asset: String? }
    struct CollectiblesDTO: Decodable {
        struct NameplateDTO: Decodable {
            struct AssetsDTO: Decodable {
                var staticImageURL: String?
                var animatedImageURL: String?
                var videoURL: String?
                enum CodingKeys: String, CodingKey {
                    case staticImageURL = "static_image_url"
                    case animatedImageURL = "animated_image_url"
                    case videoURL = "video_url"
                }
            }
            var asset: String?
            var label: String?
            var palette: String?
            var assets: AssetsDTO?
        }
        var nameplate: NameplateDTO?
    }
    struct PrimaryGuildDTO: Decodable {
        var identityGuildID: String?
        var identityEnabled: Bool?
        var tag: String?
        var badge: String?
        enum CodingKeys: String, CodingKey {
            case identityGuildID = "identity_guild_id", identityEnabled = "identity_enabled", tag, badge
        }
    }
    struct DisplayNameStyleDTO: Decodable {
        var fontID: Int?
        var effectID: Int?
        var colors: [UInt32]?
        enum CodingKeys: String, CodingKey { case fontID = "font_id", effectID = "effect_id", colors }
    }

    var id: String
    var username: String?
    var globalName: String?
    var avatar: String?
    var bot: Bool?
    var banner: String?
    var accentColor: UInt32?
    var bio: String?
    var publicFlags: UInt64?
    var avatarDecorationData: AvatarDecorationDTO?
    var collectibles: CollectiblesDTO?
    var primaryGuild: PrimaryGuildDTO?
    var displayNameStyles: DisplayNameStyleDTO?
    enum CodingKeys: String, CodingKey {
        case id, username, globalName = "global_name", avatar, bot, banner, accentColor = "accent_color", bio
        case publicFlags = "public_flags", avatarDecorationData = "avatar_decoration_data"
        case collectibles, primaryGuild = "primary_guild", displayNameStyles = "display_name_styles"
    }

    func domain() throws -> User {
        guard let id = UserID(id) else { throw ChatProviderError.invalidRequest("Discord returned an invalid user identifier.") }
        let avatarURL = avatar.flatMap { URL(string: "https://cdn.discordapp.com/avatars/\(id)/\($0).png?size=128") }
        let decorationURL = avatarDecorationData?.asset.flatMap {
            URL(string: "https://cdn.discordapp.com/avatar-decoration-presets/\($0).png?size=160")
        }
        let nameplate = collectibles?.nameplate.flatMap { value -> Nameplate? in
            guard let asset = value.asset else { return nil }
            let path = asset.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return Nameplate(
                staticURL: value.assets?.staticImageURL.flatMap(URL.init)
                    ?? URL(string: "https://cdn.discordapp.com/assets/collectibles/\(path)/static.png"),
                animatedURL: value.assets?.animatedImageURL.flatMap(URL.init)
                    ?? value.assets?.videoURL.flatMap(URL.init)
                    ?? URL(string: "https://cdn.discordapp.com/assets/collectibles/\(path)/asset.webm"),
                label: value.label ?? "",
                palette: value.palette ?? "none"
            )
        }
        let guildIdentity: PrimaryGuildIdentity? = primaryGuild.flatMap { value in
            guard value.identityEnabled != false else { return nil }
            let guildID = value.identityGuildID.flatMap(GuildID.init)
            let badgeURL = guildID.flatMap { guildID in
                value.badge.flatMap { URL(string: "https://cdn.discordapp.com/guild-tag-badges/\(guildID)/\($0).png?size=32") }
            }
            return PrimaryGuildIdentity(guildID: guildID, tag: value.tag, badgeURL: badgeURL)
        }
        let nameStyle = displayNameStyles.map {
            DisplayNameStyle(fontID: $0.fontID ?? 11, effectID: $0.effectID ?? 1, colors: $0.colors ?? [])
        }
        return User(
            id: id,
            username: username ?? id.description,
            displayName: globalName ?? username ?? id.description,
            avatarURL: avatarURL,
            isBot: bot ?? false,
            avatarDecorationURL: decorationURL,
            nameplate: nameplate,
            primaryGuild: guildIdentity,
            displayNameStyle: nameStyle,
            publicFlags: publicFlags ?? 0
        )
    }
}

private struct ProfileMetadataDTO: Decodable {
    struct EffectDTO: Decodable {
        var id: String?
        var skuID: String?
        var resolvedID: String? { id ?? skuID }
        enum CodingKeys: String, CodingKey { case id, skuID = "sku_id" }
    }
    var bio: String?
    var pronouns: String?
    var banner: String?
    var accentColor: UInt32?
    var themeColors: [UInt32]?
    var profileEffect: EffectDTO?
    enum CodingKeys: String, CodingKey {
        case bio, pronouns, banner, accentColor = "accent_color", themeColors = "theme_colors"
        case profileEffect = "profile_effect"
    }
}

private struct ProfileBadgeDTO: Decodable {
    var id: String
    var description: String?
    var icon: String?
    var link: String?

    var domain: ProfileBadge {
        ProfileBadge(
            id: id,
            description: description ?? id,
            iconURL: icon.flatMap { URL(string: "https://cdn.discordapp.com/badge-icons/\($0).png") },
            linkURL: link.flatMap(URL.init)
        )
    }
}

private struct MutualGuildDTO: Decodable {
    var id: String
    var nick: String?
}

private struct ConnectedAccountDTO: Decodable {
    var id: String?
    var type: String
    var name: String?
    var verified: Bool?

    var domain: ConnectedAccount {
        let accountID = id ?? name ?? type
        let displayName = name ?? type.localizedCapitalized
        return ConnectedAccount(
            accountID: accountID,
            type: type,
            name: displayName,
            isVerified: verified ?? false,
            profileURL: Self.profileURL(type: type, accountID: accountID, name: displayName)
        )
    }

    private static func profileURL(type: String, accountID: String, name: String) -> URL? {
        let encodedID = accountID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? accountID
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let value: String? = switch type.lowercased() {
        case "domain": name.contains("://") ? name : "https://\(name)"
        case "github": "https://github.com/\(encodedName)"
        case "instagram": "https://www.instagram.com/\(encodedName)"
        case "reddit": "https://www.reddit.com/user/\(encodedName)"
        case "roblox": "https://www.roblox.com/users/\(encodedID)/profile"
        case "spotify": "https://open.spotify.com/user/\(encodedID)"
        case "steam": "https://steamcommunity.com/profiles/\(encodedID)"
        case "tiktok": "https://www.tiktok.com/@\(encodedName)"
        case "twitch": "https://www.twitch.tv/\(encodedName)"
        case "twitter", "x": "https://x.com/\(encodedName)"
        case "youtube": "https://www.youtube.com/channel/\(encodedID)"
        case "facebook": "https://www.facebook.com/\(encodedID)"
        case "bluesky": "https://bsky.app/profile/\(encodedName)"
        case "mastodon": name.hasPrefix("@") ? nil : "https://mastodon.social/@\(encodedName)"
        case "soundcloud": "https://soundcloud.com/\(encodedName)"
        default: serviceHomeURL(type: type)
        }
        return value.flatMap(URL.init)
    }

    private static func serviceHomeURL(type: String) -> String? {
        switch type.lowercased() {
        case "amazon-music": "https://music.amazon.com"
        case "battlenet": "https://battle.net"
        case "bungie": "https://www.bungie.net"
        case "crunchyroll": "https://www.crunchyroll.com"
        case "ebay": "https://www.ebay.com"
        case "epicgames": "https://www.epicgames.com"
        case "leagueoflegends": "https://www.leagueoflegends.com"
        case "paypal": "https://www.paypal.com"
        case "playstation", "playstation-stg": "https://www.playstation.com"
        case "riotgames": "https://www.riotgames.com"
        case "xbox": "https://www.xbox.com"
        default: nil
        }
    }
}

private struct ProfileGuildMemberDTO: Decodable {
    var nick: String?
    var roles: [String]?
    var avatar: String?
    var banner: String?
    var bio: String?
}

private struct ProfileEffectConfigDTO: Decodable {
    struct AnimationDTO: Decodable {
        struct PositionDTO: Decodable {
            var x: Int?
            var y: Int?
        }
        struct SourceDTO: Decodable { var src: String? }

        var src: String?
        var loop: Bool?
        var height: Int?
        var width: Int?
        var duration: Int?
        var start: Int?
        var loopDelay: Int?
        var position: PositionDTO?
        var zIndex: Int?
        var randomizedSources: LossyList<SourceDTO>?

        var domain: ProfileEffectAnimation? {
            let source = randomizedSources?.elements.compactMap(\.src).first ?? src
            guard let source, let sourceURL = URL(string: source) else { return nil }
            return ProfileEffectAnimation(
                sourceURL: sourceURL,
                isLooping: loop ?? true,
                width: width,
                height: height,
                durationMilliseconds: duration ?? 0,
                startMilliseconds: start ?? 0,
                loopDelayMilliseconds: loopDelay ?? 0,
                positionX: position?.x ?? 0,
                positionY: position?.y ?? 0,
                zIndex: zIndex ?? 0
            )
        }
    }

    var type: Int?
    var id: String?
    var skuID: String?
    var title: String?
    var accessibilityLabel: String?
    var reducedMotionSrc: String?
    var staticFrameSrc: String?
    var effects: LossyList<AnimationDTO>?
    enum CodingKeys: String, CodingKey {
        case type, id, skuID = "sku_id", title, accessibilityLabel, reducedMotionSrc, staticFrameSrc, effects
    }

    var domain: ProfileEffect {
        ProfileEffect(
            id: id ?? skuID ?? "unknown-effect",
            title: title,
            accessibilityLabel: accessibilityLabel,
            staticURL: staticFrameSrc.flatMap(URL.init),
            reducedMotionURL: reducedMotionSrc.flatMap(URL.init),
            animations: (effects?.elements ?? []).compactMap(\.domain).sorted { $0.zIndex < $1.zIndex }
        )
    }
}

private struct ProfileEffectsDTO: Decodable {
    var profileEffectConfigs: LossyList<ProfileEffectConfigDTO>?
    enum CodingKeys: String, CodingKey { case profileEffectConfigs = "profile_effect_configs" }
}

private struct CollectibleProductDTO: Decodable {
    var items: LossyList<ProfileEffectConfigDTO>?
}

private struct UserProfileDTO: Decodable {
    var user: UserDTO
    var userProfile: ProfileMetadataDTO?
    var guildMember: ProfileGuildMemberDTO?
    var guildMemberProfile: ProfileMetadataDTO?
    var badges: LossyList<ProfileBadgeDTO>?
    var guildBadges: LossyList<ProfileBadgeDTO>?
    var mutualGuilds: LossyList<MutualGuildDTO>?
    var mutualFriends: LossyList<UserDTO>?
    var mutualFriendsCount: Int?
    var connectedAccounts: LossyList<ConnectedAccountDTO>?
    var premiumSince: String?
    var premiumGuildSince: String?
    var legacyUsername: String?
    enum CodingKeys: String, CodingKey {
        case user, userProfile = "user_profile", guildMember = "guild_member"
        case guildMemberProfile = "guild_member_profile", badges, guildBadges = "guild_badges"
        case mutualGuilds = "mutual_guilds", mutualFriends = "mutual_friends"
        case mutualFriendsCount = "mutual_friends_count", connectedAccounts = "connected_accounts"
        case premiumSince = "premium_since", premiumGuildSince = "premium_guild_since"
        case legacyUsername = "legacy_username"
    }

    func domain(
        guildID: GuildID?,
        guilds: [GuildID: Guild],
        guildRoles: [GuildRoleDTO],
        effectConfig: ProfileEffectConfigDTO?
    ) throws -> UserProfile {
        var domainUser = try user.domain()
        let displayName = guildMember?.nick.flatMap { $0.isEmpty ? nil : $0 } ?? domainUser.displayName
        let guildAvatarURL = guildID.flatMap { guildID in
            guildMember?.avatar.flatMap {
                URL(string: "https://cdn.discordapp.com/guilds/\(guildID)/users/\(domainUser.id)/avatars/\($0).png?size=256")
            }
        }
        let avatarURL = guildAvatarURL ?? domainUser.avatarURL
        domainUser.displayName = displayName
        domainUser.avatarURL = avatarURL

        let globalMetadata = userProfile
        let guildMetadata = guildMemberProfile
        let bannerHash = guildMetadata?.banner ?? guildMember?.banner ?? globalMetadata?.banner ?? user.banner
        let usesGuildBanner = guildID != nil && (guildMetadata?.banner != nil || guildMember?.banner != nil)
        let bannerURL: URL? = bannerHash.flatMap { hash in
            if usesGuildBanner, let guildID {
                return URL(string: "https://cdn.discordapp.com/guilds/\(guildID)/users/\(domainUser.id)/banners/\(hash).png?size=600")
            }
            return URL(string: "https://cdn.discordapp.com/banners/\(domainUser.id)/\(hash).png?size=600")
        }

        let roleIDs = Set(guildMember?.roles ?? [])
        let roles = guildRoles
            .filter { roleIDs.contains($0.id) }
            .sorted { $0.position > $1.position }
            .compactMap(\.domain)
        let mutualServers = (mutualGuilds?.elements ?? []).compactMap { value -> MutualGuild? in
            guard let id = GuildID(value.id), let guild = guilds[id] else { return nil }
            return MutualGuild(id: id, name: guild.name, iconURL: guild.iconURL, nickname: value.nick)
        }
        let friends = (mutualFriends?.elements ?? []).compactMap { try? $0.domain() }
        let allBadges = (badges?.elements ?? []) + (guildBadges?.elements ?? [])
        var seenBadgeIDs = Set<String>()
        let uniqueBadges = allBadges.map(\.domain).filter { seenBadgeIDs.insert($0.id).inserted }
        let effectID = guildMetadata?.profileEffect?.resolvedID ?? globalMetadata?.profileEffect?.resolvedID
        let effect = effectConfig?.domain ?? effectID.map { ProfileEffect(id: $0) }

        return UserProfile(
            user: domainUser,
            displayName: displayName,
            avatarURL: avatarURL,
            bannerURL: bannerURL,
            accentHex: guildMetadata?.accentColor ?? globalMetadata?.accentColor ?? user.accentColor,
            themeHexes: guildMetadata?.themeColors ?? globalMetadata?.themeColors ?? [],
            bio: Self.firstNonEmpty(guildMetadata?.bio, guildMember?.bio, globalMetadata?.bio, user.bio),
            pronouns: Self.firstNonEmpty(guildMetadata?.pronouns, globalMetadata?.pronouns),
            effect: effect,
            badges: uniqueBadges,
            mutualGuilds: mutualServers,
            mutualFriends: friends,
            mutualFriendsCount: mutualFriendsCount ?? friends.count,
            roles: roles,
            connectedAccounts: (connectedAccounts?.elements ?? []).map(\.domain),
            premiumSince: premiumSince.flatMap(DiscordDate.parse),
            premiumGuildSince: premiumGuildSince.flatMap(DiscordDate.parse),
            legacyUsername: legacyUsername
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : value
        }.first
    }
}

private struct GuildDTO: Decodable {
    var id: String
    var name: String
    var icon: String?

    func domain() throws -> Guild {
        guard let id = GuildID(id) else { throw ChatProviderError.invalidRequest("Discord returned an invalid guild identifier.") }
        let iconURL = icon.flatMap { URL(string: "https://cdn.discordapp.com/icons/\(id)/\($0).png?size=128") }
        return Guild(id: id, name: name, iconURL: iconURL)
    }
}

private struct ChannelDTO: Decodable {
    var id: String
    var guildID: String?
    var name: String?
    var topic: String?
    var type: Int
    var parentID: String?
    var position: Int?
    var recipients: [UserDTO]?
    enum CodingKeys: String, CodingKey { case id, guildID = "guild_id", name, topic, type, parentID = "parent_id", position, recipients }

    func domain(guildID fallbackGuildID: GuildID?, categoryName: String? = nil, categoryPosition: Int = 0) throws -> Channel {
        guard let id = ChannelID(id) else { throw ChatProviderError.invalidRequest("Discord returned an invalid channel identifier.") }
        let guild = guildID.flatMap(GuildID.init) ?? fallbackGuildID
        let users = try recipients?.map { try $0.domain() } ?? []
        let kind: ChannelKindValue = switch type {
        case 1: .directMessage
        case 3: .groupDirectMessage
        case 2, 13: .voice
        case 5: .announcement
        case 15: .forum
        default: .text
        }
        let resolvedName = name ?? users.map(\.displayName).joined(separator: ", ")
        return Channel(
            id: id,
            guildID: guild,
            name: resolvedName.isEmpty ? "Direct Message" : resolvedName,
            topic: topic,
            kind: kind,
            category: categoryName,
            categoryID: parentID.flatMap(ChannelID.init),
            position: position ?? 0,
            categoryPosition: categoryPosition,
            recipients: users
        )
    }
}

private struct GuildMemberDTO: Decodable {
    struct PresenceDTO: Decodable {
        struct ActivityDTO: Decodable {
            struct EmojiDTO: Decodable {
                var name: String?
                var id: String?
                var animated: Bool?
            }
            var name: String?
            var type: Int?
            var state: String?
            var emoji: EmojiDTO?

            var displayText: String? {
                let emojiPrefix = emoji.flatMap { emoji -> String? in
                    guard let name = emoji.name else { return nil }
                    if let id = emoji.id {
                        return "<\(emoji.animated == true ? "a" : ""):\(name):\(id)> "
                    }
                    return "\(name) "
                } ?? ""
                if type == 4, let state, !state.isEmpty { return emojiPrefix + state }
                return state.flatMap { $0.isEmpty ? nil : $0 } ?? name
            }
        }
        var status: String?
        var activities: [ActivityDTO]?
    }
    var user: UserDTO
    var nick: String?
    var roles: [String]?
    var presence: PresenceDTO?
    var avatar: String?
    var banner: String?
    var bio: String?

    func domain(
        currentUserID: UserID?,
        currentStatus: PresenceStatus,
        presence overridePresence: PresenceDTO? = nil,
        guildRoles: [GuildRoleDTO] = [],
        guildID: GuildID? = nil
    ) throws -> Member {
        var domainUser = try user.domain()
        if let nick, !nick.isEmpty { domainUser.displayName = nick }
        let guildAvatarURL: URL? = avatar.flatMap { avatarHash in
            guard let guildID else { return nil }
            return URL(string: "https://cdn.discordapp.com/guilds/\(guildID)/users/\(domainUser.id)/avatars/\(avatarHash).png?size=128")
        }
        if let guildAvatarURL { domainUser.avatarURL = guildAvatarURL }
        let status = domainUser.id == currentUserID
            ? currentStatus
            : (overridePresence ?? presence)?.status.flatMap(PresenceStatus.init(rawValue:)) ?? .offline
        let memberRoleIDs = Set(roles ?? [])
        let categoryRole = guildRoles
            .filter { $0.hoist && memberRoleIDs.contains($0.id) }
            .max { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.id < rhs.id
            }
        let domainRoles = guildRoles
            .filter { memberRoleIDs.contains($0.id) }
            .sorted { $0.position > $1.position }
            .compactMap(\.domain)
        let activities = (overridePresence ?? presence)?.activities ?? []
        let customStatus = activities.first(where: { $0.type == 4 })?.displayText
        return Member(
            user: domainUser,
            roleName: categoryRole?.name ?? "Member",
            status: status,
            rolePosition: categoryRole?.position,
            isRoleCategory: categoryRole != nil,
            roles: domainRoles,
            guildAvatarURL: guildAvatarURL,
            activityText: activities.first(where: { $0.type != 4 })?.displayText ?? customStatus,
            customStatus: customStatus
        )
    }
}

private struct GuildRoleDTO: Decodable {
    var id: String
    var name: String
    var position: Int
    var hoist: Bool
    var color: UInt32?
    var icon: String?
    var unicodeEmoji: String?
    enum CodingKeys: String, CodingKey { case id, name, position, hoist, color, icon, unicodeEmoji = "unicode_emoji" }

    var domain: GuildRole? {
        guard let id = RoleID(id) else { return nil }
        let iconURL = icon.flatMap { URL(string: "https://cdn.discordapp.com/role-icons/\(id)/\($0).png?size=32") }
        return GuildRole(
            id: id,
            name: name,
            position: position,
            colorHex: color.flatMap { $0 == 0 ? nil : $0 },
            iconURL: iconURL,
            unicodeEmoji: unicodeEmoji
        )
    }
}

private struct GuildMemberSearchResultDTO: Decodable { var member: GuildMemberDTO }

private struct MessageDeleteDTO: Decodable {
    var id: String
    var channelID: String
    enum CodingKeys: String, CodingKey { case id, channelID = "channel_id" }
}

private struct MessageUpdateDTO: Decodable {
    var id: String
    var channelID: String
    var content: String?
    var editedTimestamp: String?
    var attachments: [AttachmentDTO]?
    enum CodingKeys: String, CodingKey {
        case id, channelID = "channel_id", content, editedTimestamp = "edited_timestamp", attachments
    }
}

private struct GuildMemberListUpdateDTO: Decodable {
    struct Operation: Decodable {
        var op: String
        var range: [Int]?
        var index: Int?
        var items: [Item]?
        var item: Item?
    }
    struct Item: Decodable {
        var member: GuildMemberDTO?
        var presence: GuildMemberDTO.PresenceDTO?
    }
    var guildID: String
    var ops: [Operation]
    enum CodingKeys: String, CodingKey { case guildID = "guild_id", ops }
}

enum DiscordGatewayPayloadFactory {
    static func guildSubscriptions(guildID: GuildID, channelID: ChannelID?) -> [String: Any] {
        let channels: [String: Any] = channelID.map { [$0.description: [[0, 99]]] } ?? [:]
        return [
            "op": 37,
            "d": [
                "subscriptions": [
                    guildID.description: [
                        "typing": true,
                        "activities": true,
                        "threads": true,
                        "channels": channels,
                    ] as [String: Any],
                ],
            ] as [String: Any],
        ]
    }
}

private struct PresenceUpdateDTO: Decodable {
    struct PartialUser: Decodable { var id: String }
    var guildID: String
    var user: PartialUser
    var status: String
    var activities: [GuildMemberDTO.PresenceDTO.ActivityDTO]?
    enum CodingKeys: String, CodingKey { case guildID = "guild_id", user, status, activities }
}

private struct AttachmentReservationDTO: Decodable {
    var attachments: [AttachmentSlotDTO]
}

private struct AttachmentSlotDTO: Decodable {
    var id: Int
    var uploadURL: String
    var uploadFilename: String
    enum CodingKeys: String, CodingKey { case id, uploadURL = "upload_url", uploadFilename = "upload_filename" }
}

private struct MessageDTO: Decodable {
    struct ReferenceDTO: Decodable {
        var messageID: String?
        enum CodingKeys: String, CodingKey { case messageID = "message_id" }
    }

    struct ReferencedMessageDTO: Decodable {
        var id: String
        var author: UserDTO?
        var content: String?

        func domain() -> MessageReplyPreview? {
            guard let messageID = MessageID(id), let author, let user = try? author.domain() else { return nil }
            return MessageReplyPreview(messageID: messageID, author: user, content: content ?? "")
        }
    }

    var id: String
    var channelID: String
    var author: UserDTO?
    var content: String?
    var timestamp: String?
    var editedTimestamp: String?
    var attachments: LossyList<AttachmentDTO>?
    var reactions: LossyList<ReactionDTO>?
    var nonce: StringOrIntegerDTO?
    var messageReference: ReferenceDTO?
    var referencedMessage: ReferencedMessageDTO?
    enum CodingKeys: String, CodingKey {
        case id, channelID = "channel_id", author, content, timestamp
        case editedTimestamp = "edited_timestamp", attachments, reactions, nonce
        case messageReference = "message_reference", referencedMessage = "referenced_message"
    }

    func domain() throws -> Message {
        guard let id = MessageID(id), let channelID = ChannelID(channelID) else {
            throw ChatProviderError.invalidRequest("Discord returned an invalid message identifier.")
        }
        guard let author else {
            throw ChatProviderError.invalidRequest("Discord returned a message without an author.")
        }
        return Message(
            id: id, channelID: channelID, author: try author.domain(), content: content ?? "",
            timestamp: timestamp.flatMap(DiscordDate.parse) ?? .now,
            editedTimestamp: editedTimestamp.flatMap(DiscordDate.parse),
            replyTo: messageReference?.messageID.flatMap(MessageID.init) ?? referencedMessage.flatMap { MessageID($0.id) },
            replyPreview: referencedMessage?.domain(),
            attachments: attachments?.elements.compactMap { try? $0.domain() } ?? [],
            reactions: reactions?.elements.map(\.domain) ?? [],
            nonce: nonce?.value
        )
    }
}

private struct StringOrIntegerDTO: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { value = string }
        else { value = String(try container.decode(UInt64.self)) }
    }
}

private struct AttachmentDTO: Decodable {
    var id: String
    var filename: String
    var url: String
    var proxyURL: String?
    var contentType: String?
    var width: Int?
    var height: Int?
    var size: Int
    var description: String?
    enum CodingKeys: String, CodingKey { case id, filename, url, proxyURL = "proxy_url", contentType = "content_type", width, height, size, description }

    func domain() throws -> Attachment {
        guard let url = URL(string: url) else { throw ChatProviderError.invalidRequest("Discord returned an invalid attachment URL.") }
        return Attachment(id: id, filename: filename, url: url, proxyURL: proxyURL.flatMap(URL.init), mediaType: contentType, width: width, height: height, size: size, description: description)
    }
}

private struct ReactionDTO: Decodable {
    struct EmojiDTO: Decodable { var id: String?; var name: String? }
    var count: Int?
    var me: Bool?
    var emoji: EmojiDTO?

    var domain: Reaction {
        let value = emoji?.id.map { "<:\(emoji?.name ?? "emoji"):\($0)>" } ?? (emoji?.name ?? "?")
        return Reaction(emoji: value, count: count ?? 0, didCurrentUserReact: me ?? false)
    }
}

private enum DiscordDate {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
