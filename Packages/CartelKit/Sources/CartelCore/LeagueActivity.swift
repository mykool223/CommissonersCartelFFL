import Foundation

/// An add, drop, waiver claim or completed trade, collected from ESPN.
///
/// Stored rather than fetched live: ESPN returns a transaction as team ids and
/// player ids with no names, and resolving those costs an extra request per
/// batch. An hourly job does that once for everybody.
public struct LeagueActivity: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case add, drop, waiver, trade

        public var label: String {
            switch self {
            case .add: "ADD"
            case .drop: "DROP"
            case .waiver: "WAIVER"
            case .trade: "TRADE"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let headline: String
    public let detail: String?
    public let occurredAt: Date

    public init(id: UUID, kind: Kind, headline: String, detail: String?, occurredAt: Date) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.detail = detail
        self.occurredAt = occurredAt
    }
}
