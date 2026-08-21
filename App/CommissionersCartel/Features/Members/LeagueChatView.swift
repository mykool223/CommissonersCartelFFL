import SwiftUI
import CartelCore

/// The league's message thread.
///
/// Members-only, unlike league news: news is broadcast, this is a conversation.
struct LeagueChatView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = LeagueChatViewModel()
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !environment.isSignedIn {
                signedOutState
            } else {
                thread
                composer
            }
        }
        // Keyed on the session, not a bare .task. Session restoration happens
        // on the root view and finishes *after* this view first appears, so a
        // plain .task reads isSignedIn == false, loads nothing, and never
        // retries — an empty thread on every cold launch.
        .task(id: environment.session?.userID) {
            await model.load(using: environment)
        }
    }

    private var signedOutState: some View {
        ContentUnavailableView {
            Label("Members only", systemImage: "lock")
        } description: {
            Text("Sign in from Settings to read and post in the league thread.")
        }
        .frame(maxHeight: .infinity)
    }

    /// Signed in, but the address is not on the roster. Without this the thread
    /// would just look empty, which reads as a bug rather than a rule.
    private var notAMemberState: some View {
        ContentUnavailableView {
            Label("Not on the roster", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("You're signed in as \(environment.session?.email ?? "this account"), but that address isn't on the league list. Ask the commissioner to add you.")
        }
        .frame(maxHeight: .infinity)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    if model.messages.isEmpty, !model.isLoading {
                        EmptyStateView(
                            message: "Nothing said yet. Somebody start something.",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                    }
                    ForEach(model.messages) { message in
                        MessageRow(
                            message: message,
                            isMine: message.isMine(environment.session?.userID)
                        ) {
                            await model.delete(message, using: environment)
                        }
                        .id(message.id)
                    }
                }
                .padding(Theme.Spacing.large)
            }
            // Land on the newest message, the way any thread should open.
            .onChange(of: model.messages.count) { _, _ in
                guard let last = model.messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: Theme.Spacing.small) {
            if let error = model.postError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.loss)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Theme.Spacing.small) {
                TextField("Say something", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .background(Color.cardBackground, in: .capsule)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(!canSend)
            }
        }
        .padding(Theme.Spacing.medium)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isSending
    }

    private func send() async {
        guard canSend else { return }
        let body = draft
        // Cleared straight away so the field is ready for the next line; the
        // view model puts it back if the post fails.
        draft = ""
        if let restored = await model.post(body, using: environment) {
            draft = restored
        }
    }
}

private struct MessageRow: View {
    let message: LeagueMessage
    let isMine: Bool
    let onDelete: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            if isMine { Spacer(minLength: 40) }

            if !isMine {
                InitialsAvatar(initials: message.initials, size: 30)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                // Named on every message, including your own. A twelve-person
                // thread is not a two-way chat — leaving your own posts
                // unlabelled makes a run of them look anonymous.
                HStack(spacing: Theme.Spacing.tight) {
                    Text(message.authorName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(message.createdAt.relativeText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(isMine ? .white : .primary)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .background(
                        isMine ? Color.brand : Color.cardBackground,
                        in: .rect(cornerRadius: Theme.Radius.card)
                    )
            }

            if !isMine { Spacer(minLength: 40) }
        }
        .contextMenu {
            if isMine {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await onDelete() }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
