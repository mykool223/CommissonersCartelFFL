import Foundation

/// A human in the league. ESPN calls these "members" and keys them by SWID,
/// a brace-wrapped UUID string such as `{1A2B...}`.
public struct Manager: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let displayName: String
    public let firstName: String?
    public let lastName: String?
    /// True for the league manager(s). Drives commissioner-only UI.
    public let isCommissioner: Bool

    public init(
        id: String,
        displayName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        isCommissioner: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.isCommissioner = isCommissioner
    }

    /// Real name when ESPN has one, otherwise the display name.
    ///
    /// Each part is trimmed before joining: ESPN's name fields frequently carry
    /// trailing spaces, which join into "Danny  Adams" with a visible double gap.
    public var fullName: String {
        let parts = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? displayName.trimmingCharacters(in: .whitespacesAndNewlines) : parts.joined(separator: " ")
    }

    /// First initial of the full name, for avatar placeholders.
    public var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}
