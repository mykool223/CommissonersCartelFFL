import SwiftUI
import CartelCore

/// The inbox: one row per person you have a conversation with.
struct DirectMessagesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = DirectMessagesViewModel()
    @State private var open: Conversation?

    var body: some View {
        Group {
            if !environment.isSignedIn {
                EmptyStateView(
                    message: "Sign in under Settings to send and read private messages.",
                    systemImage: "lock"
                )
            } else if !environment.isLeagueMember {
                NotOnTheRosterView(email: environment.session?.email)
            } else if model.isLoading && model.conversations.isEmpty {
                LoadingPlaceholder()
            } else if model.conversations.isEmpty {
                EmptyStateView(
                    message: "No private messages yet. Open somebody's page from the "
                        + "roster and start one.",
                    systemImage: "envelope"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.small) {
                        ForEach(model.conversations) { conversation in
                            Button {
                                open = conversation
                            } label: {
                                Card {
                                    HStack(spacing: Theme.Spacing.small) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(conversation.displayName)
                                                .font(.subheadline.weight(
                                                    conversation.unread > 0 ? .bold : .semibold
                                                ))
                                            Text(conversation.lastMessage)
                                                .font(.footnote)
                                                .foregroundStyle(
                                                    conversation.unread > 0 ? .primary : .secondary
                                                )
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if conversation.unread > 0 {
                                            // A count rather than a plain dot:
                                            // "one waiting" and "nine waiting"
                                            // are different situations.
                                            Text("\(conversation.unread)")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red, in: Capsule())
                                                .accessibilityLabel(
                                                    "\(conversation.unread) unread"
                                                )
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.large)
                }
            }
        }
        .task(id: environment.session?.userID) { await model.load(using: environment) }
        .navigationDestination(item: $open) { conversation in
            ConversationView(conversation: conversation, model: model)
        }
    }
}

/// One conversation. Yours on the right, theirs on the left.
struct ConversationView: View {
    let conversation: Conversation
    let model: DirectMessagesViewModel

    @Environment(AppEnvironment.self) private var environment
    @State private var draft = ""

    private var messages: [DirectMessage] {
        model.messages.filter {
            $0.counterpart(of: environment.session?.userID) == conversation.userID
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.small) {
                        ForEach(messages) { message in
                            let mine = message.senderID == environment.session?.userID
                            HStack {
                                if mine { Spacer(minLength: 40) }
                                Card {
                                    Text(message.body)
                                        .font(.callout)
                                        .foregroundStyle(mine ? Color.brand : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if !mine { Spacer(minLength: 40) }
                            }
                            .id(message.id)
                        }
                    }
                    .padding(Theme.Spacing.large)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            HStack(spacing: Theme.Spacing.small) {
                TextField("Message \(conversation.displayName)", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    let body = draft
                    draft = ""
                    Task { await model.send(to: conversation.userID, body: body, using: environment) }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Theme.Spacing.medium)
        }
        .navigationTitle(conversation.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Opening it is what counts as reading it.
        .task { await model.markRead(with: conversation.userID, using: environment) }
    }
}
