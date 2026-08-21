import Foundation
import CartelCore

/// The four states every async screen can be in.
///
/// Screens switch over this rather than juggling separate `isLoading` /
/// `error` / `items` properties, which is how "spinner forever" and "empty
/// list that was actually an error" bugs happen.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(CartelError)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    var error: CartelError? {
        if case let .failed(error) = self { return error }
        return nil
    }

    /// True only for the very first load. A pull-to-refresh keeps the old
    /// content on screen instead of flashing back to a spinner.
    var isInitialLoad: Bool {
        switch self {
        case .idle, .loading: return true
        case .loaded, .failed: return false
        }
    }
}

extension Loadable where Value: Collection {
    var isEmptyResult: Bool {
        guard case let .loaded(value) = self else { return false }
        return value.isEmpty
    }
}

/// Runs an async throwing operation and folds the result into `Loadable`.
///
/// Returns the new state rather than taking `inout` state: passing an
/// actor-isolated stored property as `inout` to an `async` function is rejected
/// under Swift 6 concurrency, because the call can suspend and let something
/// else touch the property mid-write.
///
/// A `nil` return means the task was cancelled — the view is going away, so the
/// caller should leave whatever is on screen alone rather than blanking it.
@MainActor
func loadState<Value>(_ operation: () async throws -> Value) async -> Loadable<Value>? {
    do {
        return .loaded(try await operation())
    } catch let error as CartelError {
        return .failed(error)
    } catch is CancellationError {
        return nil
    } catch {
        return .failed(.transport(error.localizedDescription))
    }
}
