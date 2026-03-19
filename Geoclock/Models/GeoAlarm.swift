import CoreLocation
import Foundation
import SwiftData

enum Weekday: Int, Codable, CaseIterable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var shortLabel: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "Th"
        case .friday: "F"
        case .saturday: "Sa"
        }
    }

    /// Maps to Calendar weekday component (1 = Sunday … 7 = Saturday)
    var calendarWeekday: Int { rawValue }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekends: Set<Weekday> = [.saturday, .sunday]
}

@Model
final class GeoAlarm {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var radius: Int
    var place: String?
    var hour: Int?
    var minute: Int?
    var days: Set<Weekday>?
    var enabled: Bool
    var ringtoneURL: String?
    var isInsideGeofence: Bool
    /// Epoch milliseconds of next scheduled alarm fire time (mirrors Android `time` field)
    var time: Int?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        radius: Int = 200,
        place: String? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        days: Set<Weekday>? = nil,
        enabled: Bool = true,
        ringtoneURL: String? = nil,
        isInsideGeofence: Bool = false,
        time: Int? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.place = place
        self.hour = hour
        self.minute = minute
        self.days = days
        self.enabled = enabled
        self.ringtoneURL = ringtoneURL
        self.isInsideGeofence = isInsideGeofence
        self.time = time
    }

    var isNonRepeating: Bool {
        days == nil || days!.isEmpty
    }

    var isExpired: Bool {
        guard isNonRepeating, let time else { return false }
        return Date(timeIntervalSince1970: Double(time) / 1000.0) < .now
    }

    var displayName: String {
        place ?? String(format: "%.4f, %.4f", latitude, longitude)
    }

    static func radiusSizeLabel(for radius: Int) -> String {
        switch radius {
        case ...100: String(localized: "Nearby")
        case ...200: String(localized: "Small area")
        case ...300: String(localized: "Medium area")
        case ...400: String(localized: "Large area")
        default:     String(localized: "Wide area")
        }
    }

    // MARK: - Alarm time calculation

    func calculateNextAlarmTime(from now: Date = .now) -> Date? {
        guard let hour, let minute else { return nil }

        let calendar = Calendar.current

        if isNonRepeating {
            return nextNonRepeatingDate(hour: hour, minute: minute, from: now, calendar: calendar)
        } else {
            return nextRepeatingDate(hour: hour, minute: minute, from: now, calendar: calendar)
        }
    }

    private func nextNonRepeatingDate(hour: Int, minute: Int, from now: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let candidate = calendar.date(from: components)!
        if candidate > now {
            return candidate
        }
        return calendar.date(byAdding: .day, value: 1, to: candidate)!
    }

    private func nextRepeatingDate(hour: Int, minute: Int, from now: Date, calendar: Calendar) -> Date {
        guard let days, !days.isEmpty else {
            return nextNonRepeatingDate(hour: hour, minute: minute, from: now, calendar: calendar)
        }

        let currentWeekday = calendar.component(.weekday, from: now)
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = hour
        todayComponents.minute = minute
        todayComponents.second = 0
        let todayAlarmTime = calendar.date(from: todayComponents)!

        // Check if today's weekday matches and alarm time is in the future
        if let todayWeekday = Weekday(rawValue: currentWeekday),
           days.contains(todayWeekday),
           todayAlarmTime > now {
            return todayAlarmTime
        }

        // Find the next matching weekday
        // Sort days: first those after today's weekday, then those before/equal (wrapping around)
        let sortedDays = days.sorted()
        let afterToday = sortedDays.filter { $0.calendarWeekday > currentWeekday }
        let todayAndBefore = sortedDays.filter { $0.calendarWeekday <= currentWeekday }
        let orderedDays = afterToday + todayAndBefore

        guard let nextDay = orderedDays.first else {
            return nextNonRepeatingDate(hour: hour, minute: minute, from: now, calendar: calendar)
        }

        // Find the next occurrence of nextDay
        let nextDate = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: nextDay.calendarWeekday),
            matchingPolicy: .nextTime
        )!
        return nextDate
    }
}
