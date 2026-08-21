import SwiftUI
import CartelCore

/// The league's front page: commissioner posts, newest first.
struct NewsFeedView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = NewsFeedViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    // Masthead. Scrolls away rather than pinning, so it sets the
                    // tone without permanently costing a third of the screen.
                    LeagueCrest(size: 132)
                        .padding(.bottom, Theme.Spacing.tight)

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

                    if !model.playerNews.isEmpty {
                        PlayerNewsSection(items: model.playerNews)
                    }
                }
                .padding(Theme.Spacing.large)
            }
            .screenStyle()
            .navigationTitle("League News")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: NewsPost.self) { NewsPostDetailView(post: $0) }
            .refreshable { await model.load(using: environment, showSpinner: false) }
            .task { await model.load(using: environment) }
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

/// Player news, below the league's own posts.
///
/// Blurbs are shown inline rather than as links out — the whole point is to
/// read them without leaving the app. The publisher is not named on screen at
/// the league's request; `PlayerNews.sourceName` and `sourceURL` still carry
/// the attribution, and the longer analysis is deliberately not stored.
private struct PlayerNewsSection: View {
    let items: [PlayerNews]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Player news")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.tight)
                .padding(.top, Theme.Spacing.medium)

            ForEach(items) { item in
                PlayerNewsCard(item: item)
            }
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
