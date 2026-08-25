import SwiftUI
import CartelCore

/// League news and player news, chosen from the navigation title.
///
/// They were one scroll originally, which buried the commissioner's writing
/// under forty injury blurbs. They are separate destinations now.
enum NewsSection: String, TabSection {
    case league
    case activity
    case players
    case analysis

    var title: String {
        switch self {
        case .league: "League news"
        case .activity: "Activity"
        case .players: "Player news"
        case .analysis: "Analysis"
        }
    }

    var systemImage: String {
        switch self {
        case .league: "newspaper"
        case .activity: "arrow.left.arrow.right"
        case .players: "figure.american.football"
        case .analysis: "text.book.closed"
        }
    }
}

struct NewsFeedView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = NewsFeedViewModel()
    @State private var section: NewsSection = .initial(default: .league)

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .league: leagueNews
                case .activity: activity
                case .players: playerNews
                case .analysis: AnalysisView()
                }
            }
            .screenStyle()
            .sectionPicker($section)
            .navigationDestination(for: NewsPost.self) { NewsPostDetailView(post: $0) }
            .refreshable { await model.load(using: environment, showSpinner: false) }
            // Reloads when a session lands, so signing in picks up
            // anything the signed-out read could not see.
            .task(id: environment.session?.userID) {
                await model.load(using: environment)
            }
        }
    }

    private var leagueNews: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.medium) {
                LeagueCrest(size: 132)
                    .padding(.bottom, Theme.Spacing.tight)

                // First screen anyone sees, so this is where to explain the
                // navigation. Disappears for good once dismissed.
                SectionsHint()

                if environment.isUsingMockContent {
                    SampleDataBanner(
                        detail: "Showing sample posts. Connect Supabase in Settings to publish real ones."
                    )
                }

                LoadableView(
                    state: model.state,
                    emptyMessage: "No posts yet. The commissioner has been quiet.",
                    retry: { await model.load(using: environment) }
                ) { posts in
                    ForEach(posts) { post in
                        NavigationLink(value: post) {
                            NewsPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Spacing.large)
        }
    }

    private var activity: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.small) {
                if model.activity.isEmpty {
                    EmptyStateView(
                        message: "Nothing has moved yet. Adds, drops and trades turn up here.",
                        systemImage: "arrow.left.arrow.right"
                    )
                } else {
                    ForEach(model.activity) { item in
                        ActivityCard(item: item)
                    }
                }
            }
            .padding(Theme.Spacing.large)
        }
    }

    private var playerNews: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.medium) {
                if model.playerNews.isEmpty {
                    EmptyStateView(
                        message: "No player news yet today.",
                        systemImage: "figure.american.football"
                    )
                } else {
                    ForEach(model.playerNews) { item in
                        PlayerNewsCard(item: item)
                    }
                }
            }
            .padding(Theme.Spacing.large)
        }
    }
}

private struct ActivityCard: View {
    let item: LeagueActivity

    var body: some View {
        Card {
            HStack {
                Text(item.kind.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.brand)
                Spacer(minLength: 0)
                Text(item.occurredAt.shortDateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(item.headline)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NewsPostCard: View {
    let post: NewsPost

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.small) {
                if let week = post.week {
                    Pill(text: "Week \(week)", tint: .brand)
                }
                Text(post.publishedAt.shortDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(post.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(post.excerpt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text("by \(post.authorName)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct PlayerNewsCard: View {
    let item: PlayerNews

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                PlayerHeadshot(url: item.headshotURL, name: item.playerName)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    HStack(spacing: Theme.Spacing.small) {
                        Text(item.playerName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let detail = item.positionAndTeam {
                            Text(detail)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.brand)
                        }
                        Spacer(minLength: 0)
                        Text(item.publishedAt.relativeText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(item.headline)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    // The blurb itself, read in place.
                    if let blurb = item.blurb {
                        Text(blurb)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Player headshot, falling back to initials on a tinted circle.
private struct PlayerHeadshot: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44

    @State private var image: UIImage?

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else {
                InitialsAvatar(initials: initials, size: size)
            }
        }
        .task(id: url) {
            guard let url else { return }
            // Headshots are on a public CDN, so no auth headers are needed —
            // but the shared cache still avoids refetching on every scroll.
            image = await LogoCache.shared.image(for: url, headers: [:])
        }
    }
}

#Preview {
    NewsFeedView()
        .environment(AppEnvironment.preview)
}

#Preview("Error") {
    NewsFeedView()
        .environment(AppEnvironment.previewFailing())
}
