import SwiftUI
import CartelCore

/// Renders a `Loadable` as spinner / error / empty / content, so no screen has
/// to reimplement the four-way switch.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    var emptyMessage: String = "Nothing here yet."
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            LoadingPlaceholder()
        case let .failed(error):
            ErrorStateView(error: error, retry: retry)
        case let .loaded(value):
            if let collection = value as? any Collection, collection.isEmpty {
                EmptyStateView(message: emptyMessage)
            } else {
                content(value)
            }
        }
    }
}

struct LoadingPlaceholder: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            ProgressView()
            Text("Loading…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityLabel("Loading")
    }
}

struct EmptyStateView: View {
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView(message, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// Error state with the recovery step spelled out, plus a retry button.
struct ErrorStateView: View {
    let error: CartelError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(error.errorDescription ?? "Something went wrong.")
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var title: String {
        switch error {
        case .notAuthorized: "Can't reach your league"
        case .notConfigured: "Not set up yet"
        case .transport: "You're offline"
        case .server, .decoding: "Something went wrong"
        }
    }

    private var symbol: String {
        switch error {
        case .notAuthorized: "lock.slash"
        case .notConfigured: "gearshape"
        case .transport: "wifi.slash"
        case .server, .decoding: "exclamationmark.triangle"
        }
    }
}

/// Banner shown when a screen is displaying sample data rather than the real
/// league, so nobody mistakes the mock standings for actual results.
struct SampleDataBanner: View {
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "info.circle.fill")
            Text(detail)
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(Theme.Spacing.medium)
        .background(Color.brand.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.card))
    }
}

#Preview("Error") {
    ErrorStateView(error: .notAuthorized, retry: {})
}

#Preview("Empty") {
    EmptyStateView(message: "No polls yet.")
}
