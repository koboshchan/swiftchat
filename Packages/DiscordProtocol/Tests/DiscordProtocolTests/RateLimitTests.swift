import SwiftchatModels
import Foundation
import Testing
@testable import DiscordProtocol

@Test func bootstrapRetries429AndDoesNotBurstGuildChannelRequests() async throws {
    RateLimitURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RateLimitURLProtocol.self]
    let credentials = TestCredentialStore()
    let provider = DiscordRESTProvider(
        credentials: credentials,
        handle: CredentialHandle(accountID: "1"),
        session: URLSession(configuration: configuration)
    )

    let snapshot = try await provider.bootstrap()
    #expect(snapshot.currentUser.id == UserID(rawValue: 1))
    #expect(snapshot.guilds.count == 1)
    #expect(snapshot.channels.isEmpty)
    #expect(RateLimitURLProtocol.guildListAttempts == 2)
    #expect(RateLimitURLProtocol.guildChannelRequests == 0)

    let channels = try await provider.channels(in: GuildID(rawValue: 100))
    #expect(channels.first?.name == "general")
    #expect(channels.first?.category == "CHAT")
    #expect(RateLimitURLProtocol.guildChannelRequests == 1)

    let draft = SendMessageDraft(channelID: ChannelID(rawValue: 200), content: "hello")
    let sent = try await provider.send(draft)
    #expect(sent.content == "hello")
    #expect(draft.nonce.count <= 25)
    #expect(RateLimitURLProtocol.sentNonce == draft.nonce)

    let reply = try await provider.send(SendMessageDraft(
        channelID: ChannelID(rawValue: 200),
        content: "reply",
        replyTo: MessageID(rawValue: 299)
    ))
    #expect(reply.replyTo == MessageID(rawValue: 299))
    #expect(reply.replyPreview?.author.displayName == "Original Author")
    #expect(reply.replyPreview?.content == "original message")

    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("swiftchat-upload-test.txt")
    try Data("attachment".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }
    _ = try await provider.send(SendMessageDraft(channelID: ChannelID(rawValue: 200), content: "with file", attachmentURLs: [fileURL]))
    #expect(RateLimitURLProtocol.uploadHadAuthorization == false)
    #expect(RateLimitURLProtocol.sentUploadedFilename == "discord-upload-token")
    #expect(await credentials.credentialReadCount == 1)
}

private actor TestCredentialStore: CredentialStore {
    private(set) var credentialReadCount = 0

    func store(_ credential: Data, accountID: String) async throws -> CredentialHandle { CredentialHandle(accountID: accountID) }
    func credential(for handle: CredentialHandle) async throws -> Data {
        credentialReadCount += 1
        return Data("test-session-credential-value".utf8)
    }
    func remove(_ handle: CredentialHandle) async throws {}
    func handles() async throws -> [CredentialHandle] { [CredentialHandle(accountID: "1")] }
}

private final class RateLimitURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var guildListAttempts = 0
    nonisolated(unsafe) static var guildChannelRequests = 0
    nonisolated(unsafe) static var sentNonce: String?
    nonisolated(unsafe) static var uploadHadAuthorization = false
    nonisolated(unsafe) static var sentUploadedFilename: String?

    static func reset() {
        guildListAttempts = 0
        guildChannelRequests = 0
        sentNonce = nil
        uploadHadAuthorization = false
        sentUploadedFilename = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let status: Int
        let json: String
        switch path {
        case "/api/v9/users/@me":
            status = 200
            json = #"{"id":"1","username":"tester","global_name":"Tester","avatar":null}"#
        case "/api/v9/users/@me/guilds":
            Self.guildListAttempts += 1
            if Self.guildListAttempts == 1 {
                status = 429
                json = #"{"retry_after":0.01,"global":false}"#
            } else {
                status = 200
                json = #"[{"id":"100","name":"Guild","icon":null}]"#
            }
        case "/api/v9/users/@me/channels":
            status = 200
            json = "[]"
        case "/api/v9/guilds/100/channels":
            Self.guildChannelRequests += 1
            status = 200
            json = #"[{"id":"199","guild_id":"100","name":"CHAT","type":4,"position":1},{"id":"200","guild_id":"100","name":"general","topic":null,"type":0,"parent_id":"199","position":2}]"#
        case "/api/v9/channels/200/attachments":
            status = 200
            json = #"{"attachments":[{"id":0,"upload_url":"https://upload.example/test","upload_filename":"discord-upload-token"}]}"#
        case "/test":
            Self.uploadHadAuthorization = request.value(forHTTPHeaderField: "Authorization") != nil
            status = 200
            json = "{}"
        case "/api/v9/channels/200/messages":
            let body = Self.requestBody(request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            Self.sentNonce = body?["nonce"] as? String
            Self.sentUploadedFilename = ((body?["attachments"] as? [[String: Any]])?.first)?["uploaded_filename"] as? String
            status = 200
            if (body?["message_reference"] as? [String: Any])?["message_id"] != nil {
                json = #"{"id":"301","channel_id":"200","author":{"id":"1","username":"tester","global_name":"Tester","avatar":null},"content":"reply","timestamp":"2026-07-11T20:01:00.000Z","edited_timestamp":null,"message_reference":{"message_id":"299"},"referenced_message":{"id":"299","author":{"id":"2","username":"original","global_name":"Original Author","avatar":null},"content":"original message"},"attachments":[],"reactions":[]}"#
            } else {
                json = #"{"id":"300","channel_id":"200","author":{"id":"1","username":"tester","global_name":"Tester","avatar":null},"content":"hello","timestamp":"2026-07-11T20:00:00.000Z","edited_timestamp":null,"attachments":[],"reactions":[]}"#
            }
        default:
            status = 404
            json = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
