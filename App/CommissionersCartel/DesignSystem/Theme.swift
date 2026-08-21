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
    /// Brand tint, defined in Assets.xcassets so it can be tuned per appearance.
    static let brand = Color("AccentColor")

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let screenBackground = Color(.systemGroupedBackground)

    static let win = Color.green
    static let loss = Color.red
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
            }
    }
}

extension View {
    /// Standard screen padding + grouped background.
    func screenStyle() -> some View {
        self.background(Color.screenBackground)
    }
}
