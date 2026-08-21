import Foundation
import OSLog
import Security

/// Keychain-backed string storage for the ESPN session cookies.
///
/// These are credentials for a real ESPN account, so they must not go anywhere
/// near UserDefaults — that file is readable from a device backup.
enum KeychainStore {
    enum Key: String {
        case espnS2 = "espn_s2"
        case espnSWID = "espn_swid"
    }

    private static let service = "com.commissionerscartel.credentials"

    private static let log = Logger(
        subsystem: "com.commissionerscartel.app", category: "keychain"
    )

    static func string(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Writes the value, or removes the entry when `value` is nil or empty.
    @discardableResult
    static func set(_ value: String?, for key: Key) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        guard let value, !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            let ok = status == errSecSuccess || status == errSecItemNotFound
            if !ok { log.error("Keychain delete for \(key.rawValue) failed: \(status)") }
            return ok
        }

        let data = Data(value.utf8)
        // Try an update first; fall back to adding when there's nothing to update.
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        var insert = base
        insert[kSecValueData as String] = data
        // Cookies are only needed while the app is in use, and should not sync
        // to the user's other devices.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            // Never swallow this. -34018 (errSecMissingEntitlement) in
            // particular means the build has no keychain-access-group — which
            // happens when signing is disabled — and every save silently does
            // nothing while the UI reports success.
            log.error("Keychain save for \(key.rawValue) failed: \(status)")
            return false
        }
        return true
    }

    static var espnCredentials: (espnS2: String, swid: String)? {
        guard let s2 = string(for: .espnS2), let swid = string(for: .espnSWID) else { return nil }
        return (s2, swid)
    }
}

#if DEBUG
extension KeychainStore {
    /// Seeds ESPN credentials from `-espnS2 <value> -espnSWID <value>` launch
    /// arguments, so a simulator run can reach a private league without anyone
    /// typing into Settings.
    ///
    /// Debug builds only. Launch arguments are visible in the process list, so
    /// this must never be a path a shipping build can take.
    static func seedFromLaunchArgumentsIfNeeded() {
        if let value = launchArgument("espnS2") {
            let ok = set(value, for: .espnS2)
            log.notice("Seeded espn_s2 from launch arguments: \(ok)")
        }
        if let value = launchArgument("espnSWID") {
            let ok = set(value, for: .espnSWID)
            log.notice("Seeded SWID from launch arguments: \(ok)")
        }
    }

    /// Reads `-name value` straight out of `argv`.
    ///
    /// Deliberately not UserDefaults: it parses argument values that look like
    /// old-style property lists, and a brace-wrapped SWID (`{ABC-123}`) is
    /// exactly that syntax. It comes back as a dictionary, so `string(forKey:)`
    /// returns nil and the credential is silently dropped.
    private static func launchArgument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(name)"),
              arguments.index(after: index) < arguments.endIndex
        else { return nil }
        let value = arguments[arguments.index(after: index)]
        return value.isEmpty ? nil : value
    }
}
#endif
