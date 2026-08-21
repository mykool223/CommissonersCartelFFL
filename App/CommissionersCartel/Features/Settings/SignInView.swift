import SwiftUI
import CartelCore

/// Magic-link sign-in.
///
/// No passwords: a twelve-person league does not need everyone choosing,
/// forgetting and resetting one, and a password that never exists cannot leak.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var phase: Phase = .entering
    @FocusState private var emailFocused: Bool

    private enum Phase: Equatable {
        case entering
        case sending
        /// The link is out; the app is waiting for it to be tapped.
        case sent
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.large) {
                    LeagueCrest(size: 112)
                        .padding(.top, Theme.Spacing.section)

                    switch phase {
                    case .sent: sentState
                    default: entryState
                    }
                }
                .padding(Theme.Spacing.large)
                .frame(maxWidth: .infinity)
            }
            .screenStyle()
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        // Dismisses itself the moment the callback lands, so tapping the link
        // returns straight to the app rather than to this screen again.
        .onChange(of: environment.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    private var entryState: some View {
        VStack(spacing: Theme.Spacing.large) {
            VStack(spacing: Theme.Spacing.small) {
                Text("Twelve seats at the table")
                    .font(.title3.bold())
                Text("""
                Enter your email and we'll send you a link. Tap it and you're in \
                — no password to remember.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Card {
                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .onSubmit { Task { await send() } }
            }

            if case let .failed(message) = phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.loss)
                    .multilineTextAlignment(.leading)
            }

            Button {
                Task { await send() }
            } label: {
                HStack(spacing: Theme.Spacing.small) {
                    if phase == .sending { ProgressView().tint(.white) }
                    Text(phase == .sending ? "Sending…" : "Send me a link")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isPlausibleEmail || phase == .sending)
        }
        .onAppear { emailFocused = true }
    }

    private var sentState: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44))
                .foregroundStyle(Color.brand)

            VStack(spacing: Theme.Spacing.small) {
                Text("Check your email")
                    .font(.title3.bold())
                Text("We sent a link to \(email). Tap it on this device and you'll be signed in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // The link only works on the device it is opened on, and that trips
            // people up often enough to say out loud.
            Text("Open the email on your phone, not a computer.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Use a different address") {
                phase = .entering
            }
            .buttonStyle(.bordered)
        }
    }

    /// Deliberately loose: the server is the real judge of whether an address
    /// exists, and a strict regex mostly rejects valid addresses.
    private var isPlausibleEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.count >= 5 && !trimmed.hasSuffix("@")
    }

    private func send() async {
        guard isPlausibleEmail else { return }
        emailFocused = false
        phase = .sending
        do {
            try await environment.sendMagicLink(to: email)
            phase = .sent
        } catch let error as CartelError {
            phase = .failed(error.errorDescription ?? "Couldn't send the link.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment.preview)
}
