import Foundation

struct DaysSummary {
    static func summary(for days: Set<Weekday>?) -> String {
        guard let days, !days.isEmpty else {
            return String(localized: "Once")
        }

        if days.count == 7 {
            return String(localized: "Every day")
        }

        if days == Weekday.weekdays {
            return String(localized: "Weekdays")
        }

        if days == Weekday.weekends {
            return String(localized: "Weekends")
        }

        return days.sorted().map(\.shortLabel).joined(separator: ", ")
    }
}
