import Foundation
import Observation
import CartelCore

@Observable
@MainActor
final class PickemViewModel {
    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var games: [PickemGame] = []
    private(set) var standings: [PickemStanding] = []
    private(set) var isSaving = false
    private(set) var saveError: String?
    private(set) var week = 1

    /// The signed-in member's picks, by event.
    private var mine: [String: PickemPick] = [:]
    private var userID: UUID?

    func load(using environment: AppEnvironment, showSpinner: Bool = true) async {
        guard let userID = environment.session?.userID else {
            state = .failed("Sign in from Settings to play.")
            return
        }
        self.userID = userID
        if showSpinner, state == .idle { state = .loading }

        let season = environment.season
        week = Self.currentWeek()

        do {
            games = try await environment.content.pickemGames(season: season, week: week)
            let picks = try await environment.content.pickemPicks(season: season, week: week)
            mine = Dictionary(
                uniqueKeysWithValues: picks.filter { $0.userID == userID }
                    .map { ($0.eventID, $0) })
            // The table is a nicety; losing it should not lose the board.
            standings = (try? await environment.content.pickemStandings(
                season: season, week: week)) ?? []
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func pick(for game: PickemGame) -> PickemPick? { mine[game.eventID] }

    /// Weights not already spent, plus whatever this game currently holds.
    func availableWeights(for game: PickemGame) -> [Int] {
        let spent = Set(mine.values.filter { $0.eventID != game.eventID }
            .map(\.confidence))
        return (1...max(games.count, 1)).filter { !spent.contains($0) }.reversed()
    }

    /// Picking a team assigns the highest weight still unspent, so working
    /// down from the game you are surest about is one tap each.
    func choose(team: String, in game: PickemGame) {
        guard let userID, !game.isLocked else { return }
        let confidence = mine[game.eventID]?.confidence
            ?? availableWeights(for: game).first
            ?? 1
        mine[game.eventID] = PickemPick(
            userID: userID, eventID: game.eventID,
            chosenAbbreviation: team, confidence: confidence)
        save()
    }

    func weigh(_ game: PickemGame, at confidence: Int) {
        guard let userID, let existing = mine[game.eventID], !game.isLocked else { return }
        // Whoever held this weight swaps into the one being vacated, so the
        // set stays a permutation without the member having to tidy up.
        if let clash = mine.values.first(where: {
            $0.confidence == confidence && $0.eventID != game.eventID
        }) {
            mine[clash.eventID] = PickemPick(
                userID: userID, eventID: clash.eventID,
                chosenAbbreviation: clash.chosenAbbreviation,
                confidence: existing.confidence)
        }
        mine[game.eventID] = PickemPick(
            userID: userID, eventID: game.eventID,
            chosenAbbreviation: existing.chosenAbbreviation, confidence: confidence)
        save()
    }

    var summary: String {
        let made = mine.count
        let open = games.filter { !$0.isLocked }.count
        if open == 0 { return "Every game has started. Picks are locked." }
        if made == games.count {
            return "All \(games.count) picked. Tap the points to reweigh, any time before kickoff."
        }
        return "\(made) of \(games.count) picked. Tap a team to pick it, "
            + "then tap the points to change what it is worth."
    }

    private var saveTask: Task<Void, Never>?

    /// Saves shortly after the last change rather than on every tap: picking
    /// sixteen games is sixteen writes otherwise, and the set is only valid
    /// as a whole anyway.
    private func save() {
        saveTask?.cancel()
        saveError = nil
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private var environmentForSaving: AppEnvironment?

    func attach(environment: AppEnvironment) { environmentForSaving = environment }

    private func flush() async {
        guard let environment = environmentForSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Only games still open: the database refuses the rest anyway, and
            // sending them would fail the whole write.
            let open = Set(games.filter { !$0.isLocked }.map(\.eventID))
            try await environment.content.savePickemPicks(
                season: environment.season, week: week,
                picks: mine.values.filter { open.contains($0.eventID) })
        } catch {
            saveError = "Couldn't save that pick. It will retry when you change another."
        }
    }

    /// Week 1 begins on the first Tuesday of September; clamped to 1-18.
    /// Matches the same calculation in the scripts.
    static func currentWeek(today: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let year = calendar.component(.month, from: today) >= 6
            ? calendar.component(.year, from: today)
            : calendar.component(.year, from: today) - 1
        guard let september = calendar.date(from: DateComponents(year: year, month: 9, day: 1))
        else { return 1 }
        let weekday = calendar.component(.weekday, from: september)   // Sunday == 1
        let untilTuesday = (3 - weekday + 7) % 7
        guard let kickoff = calendar.date(byAdding: .day, value: untilTuesday, to: september)
        else { return 1 }
        if today < kickoff { return 1 }
        let days = calendar.dateComponents([.day], from: kickoff, to: today).day ?? 0
        return min(18, days / 7 + 1)
    }
}
