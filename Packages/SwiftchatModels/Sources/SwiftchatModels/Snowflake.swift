import Foundation

public struct Snowflake<Kind>: RawRepresentable, Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init?(_ value: String) {
        guard let rawValue = UInt64(value) else { return nil }
        self.rawValue = rawValue
    }

    public var description: String {
        String(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let value = UInt64(string) {
            rawValue = value
        } else {
            rawValue = try container.decode(UInt64.self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(rawValue))
    }
}

public enum AccountKind: Sendable {}
public enum UserKind: Sendable {}
public enum GuildKind: Sendable {}
public enum ChannelKind: Sendable {}
public enum MessageKind: Sendable {}
public enum RoleKind: Sendable {}

public typealias AccountID = Snowflake<AccountKind>
public typealias UserID = Snowflake<UserKind>
public typealias GuildID = Snowflake<GuildKind>
public typealias ChannelID = Snowflake<ChannelKind>
public typealias MessageID = Snowflake<MessageKind>
public typealias RoleID = Snowflake<RoleKind>
