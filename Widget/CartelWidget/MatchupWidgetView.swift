import SwiftUI
import WidgetKit

struct MatchupWidgetView: View {
    let entry: MatchupEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.week > 0 {
                Text("WEEK \(entry.week)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tint)
            }

            if let mine = entry.mine, let theirs = entry.theirs {
                side(mine)
                side(theirs)
                if let message = entry.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.message ?? "Nothing to show.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func side(_ side: MatchupEntry.Side) -> some View {
        HStack {
            Text(side.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            // Scores are hidden entirely before kickoff elsewhere in the app;
            // here the status line says so instead, because a widget with two
            // blanks reads as broken.
            Text(side.points, format: .number.precision(.fractionLength(1)))
                .font(.callout.weight(side.isLeading ? .bold : .regular))
                .foregroundStyle(side.isLeading ? Color.green : .primary)
        }
    }
}
