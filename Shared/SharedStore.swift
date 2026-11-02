import Foundation

/// The sliver of state the widget needs from the app.
///
/// A widget runs in its own process with no session and no Keychain access, so
/// it cannot ask who you are. The app writes the answer here — an app group
/// both processes can read — and the widget fetches everything else itself.
///
/// Deliberately tiny: an id, a name and a borrowed token, no scores. Cached
/// scores go stale silently, which is worse than a widget that fetches its own.
public enum SharedStore {
    public static let appGroup = "group.com.commissionerscartel.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private enum Key {
        static let teamID = "claimedTeamID"
        static let teamName = "claimedTeamName"
        static let proxyToken = "proxyAccessToken"
        static let proxyTokenExpiry = "proxyAccessTokenExpiry"
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

    /// The signed-in member's access token, lent to the widget so it can get
    /// past the members-only ESPN proxy (#15). The app writes it whenever it
    /// uses one; nil clears it, as signing out must.
    ///
    /// Only the short-lived access token, never the refresh token: if the
    /// widget refreshed too, the two processes would race to spend the same
    /// refresh token and Supabase would end the session.
    public static func shareProxyToken(_ token: String?, expiresAt: Date?) {
        if let token, let expiresAt {
            defaults?.set(token, forKey: Key.proxyToken)
            defaults?.set(expiresAt, forKey: Key.proxyTokenExpiry)
        } else {
            defaults?.removeObject(forKey: Key.proxyToken)
            defaults?.removeObject(forKey: Key.proxyTokenExpiry)
        }
    }

    /// The lent token, if it is still good at `date`. A minute's margin, so a
    /// token does not expire between being read and reaching the proxy.
    public static func proxyToken(validAt date: Date) -> String? {
        guard let token = defaults?.string(forKey: Key.proxyToken),
              let expiry = defaults?.object(forKey: Key.proxyTokenExpiry) as? Date,
              expiry.timeIntervalSince(date) > 60
        else { return nil }
        return token
    }
}
