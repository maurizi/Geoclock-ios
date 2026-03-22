import ActivityKit
import AlarmKit
import Combine
import Foundation
import SwiftUI

struct GeoAlarmMetadata: AlarmMetadata {
    var placeName: String
    var alarmTime: String
}

@MainActor
class AlarmScheduler: ObservableObject, AlarmScheduling {
    @Published var isAuthorized = false

    func requestAuthorization() async {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            isAuthorized = state == .authorized
        } catch {
            print("AlarmKit authorization failed: \(error)")
        }
    }

    func scheduleAlarm(for alarm: GeoAlarm) async throws {
        guard let nextFireDate = alarm.calculateNextAlarmTime() else { return }

        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: alarm.displayName),
                secondaryButton: AlarmButton(text: "Snooze", textColor: .blue, systemImageName: "zzz"),
                secondaryButtonBehavior: .countdown
            )
        )

        let metadata = GeoAlarmMetadata(
            placeName: alarm.displayName,
            alarmTime: nextFireDate.formatted(date: .omitted, time: .shortened)
        )

        let attributes = AlarmAttributes<GeoAlarmMetadata>(
            presentation: presentation,
            metadata: metadata,
            tintColor: .blue
        )

        let sound: AlertConfiguration.AlertSound
        if let ringtoneURL = alarm.ringtoneURL {
            sound = .named(ringtoneURL)
        } else {
            sound = .default
        }

        let schedule: Alarm.Schedule
        if alarm.isNonRepeating {
            schedule = .fixed(nextFireDate)
        } else if let days = alarm.days, !days.isEmpty, let hour = alarm.hour, let minute = alarm.minute {
            let weekdays = days.map { $0.localeWeekday }
            let relative = Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: hour, minute: minute),
                repeats: .weekly(weekdays)
            )
            schedule = .relative(relative)
        } else {
            schedule = .fixed(nextFireDate)
        }

        let config: AlarmManager.AlarmConfiguration<GeoAlarmMetadata> = .init(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: 5 * 60),
            schedule: schedule,
            attributes: attributes,
            sound: sound
        )

        _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: config)
    }

    func cancelAlarm(for alarm: GeoAlarm) {
        try? AlarmManager.shared.cancel(id: alarm.id)
    }
}

extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}
