import Foundation
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
            return status == errSecSuccess || status == errSecItemNotFound
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
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static var espnCredentials: (espnS2: String, swid: String)? {
        guard let s2 = string(for: .espnS2), let swid = string(for: .espnSWID) else { return nil }
        return (s2, swid)
    }
}
