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
    @State private var code = ""
    @State private var phase: Phase = .entering
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

    private enum Phase: Equatable {
        case entering
        case sending
        /// The link and code are out; waiting for either to be used.
        case sent
        case verifying
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.large) {
                    LeagueCrest(size: 112)
                        .padding(.top, Theme.Spacing.section)

                    switch phase {
                    case .sent, .verifying: sentState
                    case .failed where !code.isEmpty: sentState
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
                Text("We sent a link and a 6-digit code to \(email).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // The league sends from a plain address with no domain behind it,
            // so there is no SPF or DKIM vouching for the mail and providers
            // routinely bin the first one.
            Card {
                Label {
                    Text("Look in your junk folder")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.brand)
                }
                Text("The first one usually lands there. Mark it \u{201C}Not junk\u{201D} and the rest will come through.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // The link only works on the device holding the app. The code works
            // anywhere, which is the fix for reading email on a laptop.
            Card {
                Text("Tap the link on this phone — or type the code")
                    .font(.subheadline.weight(.semibold))

                TextField("000000", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .focused($codeFocused)
                    .padding(.vertical, Theme.Spacing.small)
                    .onChange(of: code) { _, value in
                        // Six digits is the whole code; submit without making
                        // anyone hunt for a button.
                        let digits = value.filter(\.isNumber)
                        if digits.count >= 6 { Task { await submitCode() } }
                    }

                if case let .failed(message) = phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.loss)
                }

                Button {
                    Task { await submitCode() }
                } label: {
                    HStack {
                        if phase == .verifying { ProgressView() }
                        Text(phase == .verifying ? "Checking\u{2026}" : "Sign in with code")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.filter(\.isNumber).count < 6 || phase == .verifying)
            }

            Button("Use a different address") {
                code = ""
                phase = .entering
            }
            .buttonStyle(.bordered)
        }
    }

    private func submitCode() async {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 6, phase != .verifying else { return }
        codeFocused = false
        phase = .verifying
        do {
            try await environment.signIn(email: email, code: digits)
            // The sheet dismisses itself on isSignedIn changing.
        } catch let error as CartelError {
            phase = .failed(error.errorDescription ?? "That code didn't work.")
        } catch {
            phase = .failed(error.localizedDescription)
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
