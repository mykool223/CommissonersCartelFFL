import SwiftUI

/// Shared visual constants. Everything resolves from system semantic colours,
/// so dark mode and Dynamic Type work without any per-screen handling.
enum Theme {
    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let section: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 14
        static let pill: CGFloat = 999
    }
}

extension Color {
    /// Brand tint, sampled from the league crest and defined in
    /// Assets.xcassets. Deliberately different per appearance: the crest's
    /// bright gold (#D8B868) fails contrast against a white background, so
    /// light mode uses a deeper gold (#8A6A24) and dark mode gets the bright one.
    static let brand = Color("AccentColor")

    /// Crest golds, for use *on black* — where the contrast problem above
    /// doesn't apply. Fixed values, not appearance-dependent.
    static let crestGold = Color(red: 0xD8 / 255, green: 0xB8 / 255, blue: 0x68 / 255)
    static let crestGoldShadow = Color(red: 0x78 / 255, green: 0x58 / 255, blue: 0x28 / 255)
    /// The crest artwork's own field. Measured from the source PNG's border
    /// ring — it is #0D0D0D, not pure black. Painting the surround #000000
    /// leaves the crest's square edge faintly visible against it.
    static let crestField = Color(red: 0x0D / 255, green: 0x0D / 255, blue: 0x0D / 255)

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let screenBackground = Color(.systemGroupedBackground)

    static let win = Color.green
    static let loss = Color.red
}

/// The league crest.
///
/// The artwork has a solid black background rather than transparency, so it is
/// deliberately framed as a rounded badge sitting on its own black field. Drawn
/// straight onto a light-mode screen it would read as a stray black square.
struct LeagueCrest: View {
    var size: CGFloat = 120

    private var cornerRadius: CGFloat { size * 0.18 }

    var body: some View {
        Image("LeagueLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.crestField)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.crestGoldShadow, lineWidth: 1)
            }
            .accessibilityLabel("Commissioners Cartel")
    }
}

/// Rounded container used for every content block in the app.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .background(Color.cardBackground, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

/// Small capsule label — week numbers, "Final", "Closed".
struct Pill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.tight)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// Circle with a manager's initials, used wherever there's no avatar image.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color.brand.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.brand)
                    // Team abbreviations run to four characters; shrink to fit
                    // rather than truncating something already abbreviated.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * 0.1)
            }
    }
}

extension View {
    /// Standard screen padding + grouped background.
    func screenStyle() -> some View {
        self.background(Color.screenBackground)
    }
}
