import SwiftUI

/// One-time explanation that tab titles are menus.
///
/// The chevron next to the navigation title is the only clue that a tab holds
/// more than one screen, and it is easy to read as decoration. Eleven people
/// arriving at once would otherwise each have to discover it — or not, and
/// conclude half the app is missing.
///
/// Dismissal is per device and permanent; there is nothing here worth seeing
/// twice.
struct SectionsHint: View {
    @AppStorage("hasSeenSectionsHint") private var hasSeenHint = false

    private static let sections: [(tab: String, image: String, screens: String)] = [
        ("News", "newspaper", "League news · Activity · Player news"),
        ("Matchups", "sportscourt", "Scoreboard · Weekly recap · Standings · NFL scores · Coach"),
        ("Members", "person.3", "Members · League thread · Messages · Trophy case"),
    ]

    var body: some View {
        if !hasSeenHint {
            Card {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    Text("Tap the title to switch screens")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brand)
                    Spacer(minLength: 0)
                }

                Text("Most tabs hold more than one screen. Tap the name at the top to switch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    ForEach(Self.sections, id: \.tab) { section in
                        HStack(alignment: .top, spacing: Theme.Spacing.small) {
                            Image(systemName: section.image)
                                .font(.caption)
                                .foregroundStyle(Color.brand)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.tab)
                                    .font(.caption.weight(.semibold))
                                Text(section.screens)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, Theme.Spacing.tight)

                Button("Got it") {
                    withAnimation { hasSeenHint = true }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, Theme.Spacing.tight)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

#Preview {
    ScrollView {
        SectionsHint().padding()
    }
}
