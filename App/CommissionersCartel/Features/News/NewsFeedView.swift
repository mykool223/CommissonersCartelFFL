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

                    if !model.articles.isEmpty {
                        AroundTheLeagueSection(articles: model.articles)
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

/// Outside headlines, below the league's own posts.
///
/// Rows are visually lighter than a league post and open the publisher's page
/// rather than a detail screen — the app stores only the headline and excerpt,
/// never the article itself.
private struct AroundTheLeagueSection: View {
    let articles: [ExternalArticle]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.small) {
                Text("Around the league")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let source = articles.first?.sourceName {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.tight)
            .padding(.top, Theme.Spacing.medium)

            ForEach(articles) { article in
                Link(destination: article.url) {
                    ArticleRow(article: article)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ArticleRow: View {
    let article: ExternalArticle

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(article.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    if let excerpt = article.excerpt {
                        Text(excerpt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    HStack(spacing: Theme.Spacing.tight) {
                        Text(article.publishedAt.relativeText)
                        if let author = article.author {
                            Text("· \(author)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                // Signals that this leaves the app.
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brand)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(article.sourceName) in your browser")
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
