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
