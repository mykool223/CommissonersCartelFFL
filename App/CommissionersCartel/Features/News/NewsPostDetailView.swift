import SwiftUI
import CartelCore

struct NewsPostDetailView: View {
    let post: NewsPost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    if let week = post.week {
                        Pill(text: "Week \(week)", tint: .brand)
                    }
                    Text(post.title)
                        .font(.title2.bold())
                    Text("\(post.authorName) · \(post.publishedAt.shortDateText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let url = post.coverImageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Color.cardBackground)
                            .frame(height: 180)
                    }
                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                }

                Text(post.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
        }
        .screenStyle()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        NewsPostDetailView(post: MockData.newsPosts[0])
    }
}
