import Foundation

extension Double {
    /// Fantasy points always read to one decimal: "121.4".
    var pointsText: String {
        formatted(.number.precision(.fractionLength(1)))
    }

    /// Signed differential: "+182.2" / "-45.7".
    var signedPointsText: String {
        formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
    }
}

extension Date {
    /// "Nov 16" for this year, "Nov 16, 2024" otherwise.
    var shortDateText: String {
        Calendar.current.isDate(self, equalTo: .now, toGranularity: .year)
            ? formatted(.dateTime.month(.abbreviated).day())
            : formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "2 days ago"
    var relativeText: String {
        formatted(.relative(presentation: .named))
    }
}
