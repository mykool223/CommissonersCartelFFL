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
            .screenStyle()
            .navigationTitle("League News")
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

#Preview {
    NewsFeedView()
        .environment(AppEnvironment.preview)
}

#Preview("Error") {
    NewsFeedView()
        .environment(AppEnvironment.previewFailing())
}
