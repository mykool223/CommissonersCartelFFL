import Foundation

/// Which NFL season "now" belongs to.
///
/// This lives in CartelCore rather than the app target because both the app's
/// configuration *and* the sample data need it, and having two copies of the
/// rule is how you end up asking for one season and holding data for another.
public enum Season {
    /// The season rolls over in the spring: in January and February, "this
    /// season" is still the one that started last calendar year.
    public static func current(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let year = components.year, let month = components.month else { return 2025 }
        return month < 3 ? year - 1 : year
    }
}


/// Parses the ISO-8601 timestamps sports feeds actually emit.
///
/// `Date.ISO8601FormatStyle` requires seconds, and ESPN's scoreboard omits
/// them — it sends `2026-08-21T23:00Z`. Parsing that with the stock style fails
/// silently, which is how a fallback date ends up on screen looking like a real
/// kickoff time.
public enum FlexibleISO8601 {
    public static func date(from raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let style = Date.ISO8601FormatStyle()
        if let date = try? style.parse(trimmed) { return date }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse(trimmed) { return date }

        // Insert the missing ":00" seconds field and try again.
        if let padded = paddingSeconds(in: trimmed),
           let date = try? style.parse(padded) {
            return date
        }
        return nil
    }

    /// Turns "2026-08-21T23:00Z" into "2026-08-21T23:00:00Z", leaving anything
    /// that already has seconds alone.
    private static func paddingSeconds(in raw: String) -> String? {
        // yyyy-MM-ddTHH:mm followed directly by a zone designator.
        let pattern = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})(Z|[+-]\d{2}:?\d{2})$/
        guard let match = raw.wholeMatch(of: pattern) else { return nil }
        return "\(match.1):00\(match.2)"
    }
}
