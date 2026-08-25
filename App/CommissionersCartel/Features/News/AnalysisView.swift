import SwiftUI
import CartelCore

/// Player news and analysis from FantasyPros.
///
/// Their headline and a short extract of their read; the full piece opens on
/// their site. Their writing is theirs, and a link is the honest way to pass
/// somebody else's work along — as well as the one our licence supports.
struct AnalysisView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var items: [AnalysisItem] = []
    @State private var hasLoaded = false
    @State private var reading: AnalysisItem?

    var body: some View {
        Group {
            if items.isEmpty {
                if hasLoaded {
                    ContentUnavailableView(
                        "No articles yet",
                        systemImage: "text.book.closed",
                        description: Text("FantasyPros articles appear here through the day.")
                    )
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    ForEach(items) { item in
                        Button {
                            reading = item
                        } label: {
                            Card {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: Theme.Spacing.small) {
                                        if let author = item.author {
                                            Text(author.uppercased())
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(Color.brand)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        Text(item.publishedAt, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.leading)

                                    if let excerpt = item.excerpt {
                                        // An extract, not the whole piece.
                                        Text(excerpt)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                    }

                                    Text("Read on FantasyPros")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.brand)
                                        .padding(.top, 2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Text("From FantasyPros. Articles open here in the app.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.small)
                }
                .padding(Theme.Spacing.large)
                }
            }
        }
        .sheet(item: $reading) { item in
            ArticleReader(url: item.link).ignoresSafeArea()
        }
        .task { await load() }
    }

    private func load() async {
        defer { hasLoaded = true }
        items = (try? await environment.content.analysis(limit: 60)) ?? []
    }
}
