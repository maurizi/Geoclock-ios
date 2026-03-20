import ActivityKit
import AlarmKit
import CoreLocation
import Foundation
@testable import Geoclock
import SwiftUI
import Testing

@MainActor
struct GeoAlarmTests {

    @Test func calculateNextAlarmTime_nonRepeating_futureToday() async throws {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 8, minute: 0))!

        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, hour: 10, minute: 30)

        let nextTime = alarm.calculateNextAlarmTime(from: now)
        #expect(nextTime != nil)

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextTime!)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 13)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
    }

    @Test func calculateNextAlarmTime_nonRepeating_pastToday_goesToTomorrow() async throws {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 12, minute: 0))!

        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, hour: 8, minute: 0)

        let nextTime = alarm.calculateNextAlarmTime(from: now)
        #expect(nextTime != nil)

        let components = calendar.dateComponents([.day, .hour, .minute], from: nextTime!)
        #expect(components.day == 14)
        #expect(components.hour == 8)
        #expect(components.minute == 0)
    }

    @Test func calculateNextAlarmTime_noHourMinute_returnsNil() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0)
        #expect(alarm.calculateNextAlarmTime() == nil)
    }

    // MARK: - Repeating alarm edge cases

    @Test func calculateNextAlarmTime_repeating_todaysDayButPastTime() async throws {
        let calendar = Calendar.current
        // 2026-03-13 is a Friday
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 14, minute: 0))!

        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, hour: 8, minute: 0, days: [.friday])

        let nextTime = alarm.calculateNextAlarmTime(from: now)
        #expect(nextTime != nil)

        // Should go to next Friday (March 20)
        let components = calendar.dateComponents([.month, .day, .hour, .minute, .weekday], from: nextTime!)
        #expect(components.month == 3)
        #expect(components.day == 20)
        #expect(components.hour == 8)
        #expect(components.minute == 0)
        #expect(components.weekday == Weekday.friday.calendarWeekday)
    }

    @Test func calculateNextAlarmTime_repeating_singleDay() async throws {
        let calendar = Calendar.current
        // 2026-03-13 is a Friday, alarm is Monday-only
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 8, minute: 0))!

        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, hour: 9, minute: 0, days: [.monday])

        let nextTime = alarm.calculateNextAlarmTime(from: now)
        #expect(nextTime != nil)

        // Next Monday is March 16
        let components = calendar.dateComponents([.month, .day, .weekday], from: nextTime!)
        #expect(components.month == 3)
        #expect(components.day == 16)
        #expect(components.weekday == Weekday.monday.calendarWeekday)
    }

    @Test func calculateNextAlarmTime_repeating_weekBoundaryWrap() async throws {
        let calendar = Calendar.current
        // 2026-03-14 is a Saturday, alarm is Sunday+Monday
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 10, minute: 0))!

        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, hour: 7, minute: 0, days: [.sunday, .monday])

        let nextTime = alarm.calculateNextAlarmTime(from: now)
        #expect(nextTime != nil)

        // Next Sunday is March 15
        let components = calendar.dateComponents([.month, .day, .weekday], from: nextTime!)
        #expect(components.month == 3)
        #expect(components.day == 15)
        #expect(components.weekday == Weekday.sunday.calendarWeekday)
    }

    // MARK: - isExpired

    @Test func isExpired_nonRepeating_pastTime() async throws {
        let pastMs = Int((Date.now.timeIntervalSince1970 - 3600) * 1000)
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, time: pastMs)
        #expect(alarm.isExpired)
    }

    @Test func isExpired_nonRepeating_futureTime() async throws {
        let futureMs = Int((Date.now.timeIntervalSince1970 + 3600) * 1000)
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, time: futureMs)
        #expect(!alarm.isExpired)
    }

    @Test func isExpired_repeating_neverExpires() async throws {
        let pastMs = Int((Date.now.timeIntervalSince1970 - 3600) * 1000)
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, days: [.monday, .friday], time: pastMs)
        #expect(!alarm.isExpired)
    }

    @Test func isExpired_nilTime() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0)
        #expect(!alarm.isExpired)
    }

    // MARK: - isNonRepeating

    @Test func isNonRepeating_noDays() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0)
        #expect(alarm.isNonRepeating)
    }

    @Test func isNonRepeating_emptyDays() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, days: [])
        #expect(alarm.isNonRepeating)
    }

    @Test func isNonRepeating_withDays() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, days: [.monday, .wednesday])
        #expect(!alarm.isNonRepeating)
    }

    @Test func radiusSizeLabel() async throws {
        #expect(GeoAlarm.radiusSizeLabel(for: 50) == String(localized: "Nearby"))
        #expect(GeoAlarm.radiusSizeLabel(for: 100) == String(localized: "Nearby"))
        #expect(GeoAlarm.radiusSizeLabel(for: 150) == String(localized: "Small area"))
        #expect(GeoAlarm.radiusSizeLabel(for: 250) == String(localized: "Medium area"))
        #expect(GeoAlarm.radiusSizeLabel(for: 350) == String(localized: "Large area"))
        #expect(GeoAlarm.radiusSizeLabel(for: 500) == String(localized: "Wide area"))
    }

    @Test func displayName_withPlace() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, place: "Home")
        #expect(alarm.displayName == "Home")
    }

    @Test func displayName_withoutPlace() async throws {
        let alarm = GeoAlarm(latitude: 40.1234, longitude: -74.5678)
        #expect(alarm.displayName == "40.1234, -74.5678")
    }

    @Test func daysSummary_weekdays() async throws {
        #expect(DaysSummary.summary(for: Weekday.weekdays) == String(localized: "Weekdays"))
    }

    @Test func daysSummary_weekends() async throws {
        #expect(DaysSummary.summary(for: Weekday.weekends) == String(localized: "Weekends"))
    }

    @Test func daysSummary_everyDay() async throws {
        #expect(DaysSummary.summary(for: Set(Weekday.allCases)) == String(localized: "Every day"))
    }

    @Test func daysSummary_once() async throws {
        #expect(DaysSummary.summary(for: nil) == String(localized: "Once"))
        #expect(DaysSummary.summary(for: []) == String(localized: "Once"))
    }

    @Test func daysSummary_custom() async throws {
        let days: Set<Weekday> = [.monday, .wednesday, .friday]
        #expect(DaysSummary.summary(for: days) == "M, W, F")
    }

    @Test func weekday_shortLabels() async throws {
        #expect(Weekday.sunday.shortLabel == "S")
        #expect(Weekday.monday.shortLabel == "M")
        #expect(Weekday.thursday.shortLabel == "Th")
        #expect(Weekday.saturday.shortLabel == "Sa")
    }

    // MARK: - DistanceFormatter

    @Test func distanceToEdge_atBoundary() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, radius: 200)
        // Create a location exactly at the center
        let center = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        let distance = DistanceFormatter.distanceToEdge(from: center, to: alarm)
        #expect(distance == -200.0)
    }

    @Test func distanceToEdge_inside() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, radius: 1000)
        // Roughly 100m north
        let nearby = CLLocationCoordinate2D(latitude: 40.0009, longitude: -74.0)
        let distance = DistanceFormatter.distanceToEdge(from: nearby, to: alarm)
        #expect(distance < 0) // Inside → negative
    }

    @Test func distanceToEdge_outside() async throws {
        let alarm = GeoAlarm(latitude: 40.0, longitude: -74.0, radius: 100)
        // Roughly 1km north
        let far = CLLocationCoordinate2D(latitude: 40.009, longitude: -74.0)
        let distance = DistanceFormatter.distanceToEdge(from: far, to: alarm)
        #expect(distance > 0) // Outside → positive
    }

    // MARK: - AlarmKit integration

    // AlarmKit throws Code=1 on the simulator — these tests verify behavior on real devices only.

}

// MARK: - AlarmKit integration (XCTest wrapper for Device Farm compatibility)

// AlarmKit throws Code=1 on the simulator — these tests run on real devices only.
// Uses XCTestCase instead of Swift Testing @Test so Device Farm can discover them.

#if !targetEnvironment(simulator)
import XCTest

final class AlarmKitTests: XCTestCase {
    @MainActor
    func testAlarmKit_scheduleAndCancel() async throws {
        let alarmId = UUID()

        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: "Test Alarm"
            )
        )
        let metadata = GeoAlarmMetadata(placeName: "Test", alarmTime: "8:00 AM")
        let attributes = AlarmAttributes<GeoAlarmMetadata>(
            presentation: presentation,
            metadata: metadata,
            tintColor: .blue
        )

        // Schedule 1 hour from now
        let futureTime = Calendar.current.dateComponents([.hour, .minute], from: Date.now.addingTimeInterval(3600))
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: futureTime.hour!, minute: futureTime.minute!),
            repeats: .never
        ))

        let config = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            sound: .default
        )

        let alarm = try await AlarmManager.shared.schedule(id: alarmId, configuration: config)
        XCTAssertEqual(alarm.state, .scheduled)

        let alarms = try AlarmManager.shared.alarms
        XCTAssertTrue(alarms.contains { $0.id == alarmId })

        try AlarmManager.shared.cancel(id: alarmId)
    }
}
#endif
