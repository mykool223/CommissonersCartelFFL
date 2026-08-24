import Foundation

/// The sliver of state the widget needs from the app.
///
/// A widget runs in its own process with no session and no Keychain access, so
/// it cannot ask who you are. The app writes the answer here — an app group
/// both processes can read — and the widget fetches everything else itself.
///
/// Deliberately tiny: an id and a name, no scores. Cached scores go stale
/// silently, which is worse than a widget that fetches its own.
public enum SharedStore {
    public static let appGroup = "group.com.commissionerscartel.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private enum Key {
        static let teamID = "claimedTeamID"
        static let teamName = "claimedTeamName"
    }

    public static var claimedTeamID: Int? {
        get {
            guard let value = defaults?.object(forKey: Key.teamID) as? Int else { return nil }
            return value
        }
        set {
            if let newValue { defaults?.set(newValue, forKey: Key.teamID) }
            else { defaults?.removeObject(forKey: Key.teamID) }
        }
    }

    public static var claimedTeamName: String? {
        get { defaults?.string(forKey: Key.teamName) }
        set { defaults?.set(newValue, forKey: Key.teamName) }
    }
}
