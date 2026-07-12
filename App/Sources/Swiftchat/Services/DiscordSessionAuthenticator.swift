import DiscordProtocol
import Foundation

actor DiscordSessionAuthenticator {
    private let credentials: any CredentialStore
    private let session: URLSession

    init(credentials: any CredentialStore = KeychainCredentialStore(), session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func validateAndStore(token: String) async throws -> CredentialHandle {
        let normalized = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \n\r\t"))
        guard normalized.count > 20 else { throw AuthenticationError.invalidCredential }
        var request = URLRequest(url: URL(string: "https://discord.com/api/v10/users/@me")!)
        request.timeoutInterval = 20
        request.setValue(normalized, forHTTPHeaderField: "Authorization")
        request.setValue("Swiftchat/0.1 (macOS; native Swift client)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw AuthenticationError.rejected
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountID = object["id"] as? String,
              UInt64(accountID) != nil else { throw AuthenticationError.invalidResponse }
        var credentialData = Data(normalized.utf8)
        defer { credentialData.resetBytes(in: credentialData.indices) }
        return try await credentials.store(credentialData, accountID: accountID)
    }
}

enum AuthenticationError: LocalizedError {
    case invalidCredential, rejected, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidCredential: "Discord sign-in completed, but no valid session credential was found."
        case .rejected: "Discord rejected the captured web session. Sign in again and retry."
        case .invalidResponse: "Discord returned an invalid account response."
        }
    }
}
