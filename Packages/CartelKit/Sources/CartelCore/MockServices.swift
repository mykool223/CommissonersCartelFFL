import Foundation

/// In-memory `LeagueDataSource`. Stateless, so a plain struct is enough.
public struct MockLeagueDataSource: LeagueDataSource {
    /// Artificial latency, so loading states are visible while developing.
    public let latency: Duration
    /// When set, every call throws this instead of returning data. Useful for
    /// building and previewing error states.
    public let failure: CartelError?

    public init(latency: Duration = .milliseconds(250), failure: CartelError? = nil) {
        self.latency = latency
        self.failure = failure
    }

    private func simulate() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
        if let failure { throw failure }
    }

    public func league() async throws -> League {
        try await simulate()
        return MockData.league
    }

    public func managers() async throws -> [Manager] {
        try await simulate()
        return MockData.managers
    }

    public func teams() async throws -> [Team] {
        try await simulate()
        return MockData.teams
    }

    public func matchups(week: Int) async throws -> [Matchup] {
        try await simulate()
        return MockData.matchups(week: week)
    }
}

/// In-memory `ContentRepository` that remembers votes for the lifetime of the
/// process, so the poll UI behaves correctly without a backend.
///
/// An actor rather than a struct because `vote` mutates shared state.
public actor MockContentRepository: ContentRepository {
    private var polls: [Poll]
    private let latency: Duration
    private let failure: CartelError?

    public init(latency: Duration = .milliseconds(250), failure: CartelError? = nil) {
        self.polls = MockData.polls
        self.latency = latency
        self.failure = failure
    }

    private func simulate() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
        if let failure { throw failure }
    }

    public func newsPosts(season: Int, limit: Int) async throws -> [NewsPost] {
        try await simulate()
        return Array(
            MockData.newsPosts
                .filter { $0.season == season }
                .sorted { $0.publishedAt > $1.publishedAt }
                .prefix(limit)
        )
    }

    public func recaps(season: Int, week: Int) async throws -> [Recap] {
        try await simulate()
        return MockData.recaps(week: week).filter { $0.season == season }
    }

    public func polls(season: Int) async throws -> [Poll] {
        try await simulate()
        return polls
            .filter { $0.season == season }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func externalArticles(limit: Int) async throws -> [ExternalArticle] {
        try await simulate()
        return Array(
            MockData.externalArticles
                .sorted { $0.publishedAt > $1.publishedAt }
                .prefix(limit)
        )
    }

    public func vote(pollID: UUID, optionID: UUID) async throws {
        try await simulate()
        guard let index = polls.firstIndex(where: { $0.id == pollID }) else {
            throw CartelError.notConfigured("No poll with id \(pollID).")
        }
        guard polls[index].options.contains(where: { $0.id == optionID }) else {
            throw CartelError.notConfigured("Option \(optionID) is not on that poll.")
        }
        polls[index] = polls[index].applyingVote(optionID: optionID)
    }
}
