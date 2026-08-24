import SwiftUI

/// Shown to somebody who is signed in but has no profile.
///
/// This state used to be silent: sign-in succeeded, then nothing worked and
/// nothing said why. Two members sat locked out for days because of it. The
/// commissioner is told separately, but the person stuck looking at the screen
/// deserves to know too.
struct NotOnTheRosterView: View {
    let email: String?

    var body: some View {
        ContentUnavailableView {
            Label("Not on the roster", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(
                "You're signed in as \(email ?? "this account"), but that address "
                + "isn't on the league list. Ask the commissioner to add it — "
                + "they've been told."
            )
        }
    }
}
