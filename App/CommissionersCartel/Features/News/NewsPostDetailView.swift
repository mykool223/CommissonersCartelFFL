import SwiftUI
import CartelCore

struct NewsPostDetailView: View {
    let post: NewsPost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                // Above the headline and centred, so a post with a face
                // opens on it. A square image is an avatar rather than a
                // photograph, so it is drawn as one instead of being stretched
                // across the column.
                if let url = post.coverImageURL {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 128, maxHeight: 128)
                            .clipShape(.circle)
                    } placeholder: {
                        Circle()
                            .fill(Color.cardBackground)
                            .frame(width: 128, height: 128)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

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
