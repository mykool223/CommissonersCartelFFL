import SwiftUI
import CartelCore

/// The league's trophy case.
///
/// Empty until the first week is in the books, and deliberately says so rather
/// than showing a blank screen — there is no history to import, so an empty
/// case is the correct state rather than a failure.
struct TrophyCaseView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = TrophyCaseViewModel()

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                LoadingPlaceholder()
            case let .failed(error):
                ErrorStateView(error: error) { Task { await model.load(using: environment) } }
            case let .loaded(trophies):
                if trophies.isEmpty {
                    EmptyStateView(
                        message: "The case is empty. The first trophy goes to whoever posts "
                            + "the highest score in week one.",
                        systemImage: "trophy"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.small) {
                            ForEach(trophies) { entry in
                                TrophyRowView(entry: entry)
                            }
                        }
                        .padding(Theme.Spacing.large)
                    }
                }
            }
        }
        .task(id: environment.season) { await model.load(using: environment) }
    }
}

private struct TrophyRowView: View {
    let entry: TrophyCaseViewModel.Entry

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.medium) {
                TeamLogoView(
                    logoURL: entry.team?.logoURL,
                    fallbackInitials: entry.team?.abbreviation ?? "?",
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.trophy.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brand)
                    Text(entry.team?.name ?? "Team \(entry.trophy.teamID)")
                        .font(.subheadline.weight(.semibold))
                    if let detail = entry.trophy.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.brand)
            }
        }
    }
}
