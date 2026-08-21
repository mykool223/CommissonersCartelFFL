import Foundation

/// A league poll. Options and vote tallies arrive together so a single fetch
/// can render the whole card.
public struct Poll: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let question: String
    public let options: [PollOption]
    public let season: Int
    public let week: Int?
    public let createdByName: String
    public let createdAt: Date
    /// When voting stops. Nil means the poll stays open indefinitely.
    public let closesAt: Date?
    /// Option the signed-in member picked, if they have voted.
    public let myVoteOptionID: UUID?

    public init(
        id: UUID,
        question: String,
        options: [PollOption],
        season: Int,
        week: Int? = nil,
        createdByName: String,
        createdAt: Date,
        closesAt: Date? = nil,
        myVoteOptionID: UUID? = nil
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.season = season
        self.week = week
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.closesAt = closesAt
        self.myVoteOptionID = myVoteOptionID
    }

    public var hasVoted: Bool { myVoteOptionID != nil }

    public func isClosed(asOf now: Date) -> Bool {
        guard let closesAt else { return false }
        return now >= closesAt
    }

    public var totalVotes: Int {
        options.reduce(0) { $0 + $1.voteCount }
    }

    /// Share of the vote for one option, 0...1. Zero when nobody has voted.
    public func share(of option: PollOption) -> Double {
        let total = totalVotes
        guard total > 0 else { return 0 }
        return Double(option.voteCount) / Double(total)
    }

    /// Options tied for the most votes. Empty when there are no votes yet.
    public var leadingOptions: [PollOption] {
        guard let top = options.map(\.voteCount).max(), top > 0 else { return [] }
        return options.filter { $0.voteCount == top }
    }

    /// Returns a copy with the vote applied locally, so the UI can update
    /// before the server round-trip finishes.
    public func applyingVote(optionID: UUID) -> Poll {
        let updated = options.map { option -> PollOption in
            var count = option.voteCount
            if option.id == myVoteOptionID { count -= 1 }
            if option.id == optionID { count += 1 }
            return PollOption(id: option.id, label: option.label, voteCount: max(0, count))
        }
        return Poll(
            id: id,
            question: question,
            options: updated,
            season: season,
            week: week,
            createdByName: createdByName,
            createdAt: createdAt,
            closesAt: closesAt,
            myVoteOptionID: optionID
        )
    }
}

public struct PollOption: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let label: String
    public let voteCount: Int

    public init(id: UUID, label: String, voteCount: Int = 0) {
        self.id = id
        self.label = label
        self.voteCount = voteCount
    }
}
