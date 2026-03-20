import ActivityKit
import AlarmKit
import Combine
import Foundation
import SwiftData
import SwiftUI

struct GeoAlarmMetadata: AlarmMetadata {
    var placeName: String
    var alarmTime: String
}

@MainActor
class AlarmScheduler: ObservableObject, AlarmScheduling {
    @Published var isAuthorized = false

    private var modelContainer: ModelContainer?
    private var alarmUpdatesTask: Task<Void, Never>?

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        startObservingAlarmUpdates()
    }

    func requestAuthorization() async {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            isAuthorized = state == .authorized
            print("[Geoclock] AlarmKit authorization: \(state), isAuthorized=\(isAuthorized)")
        } catch {
            print("[Geoclock] AlarmKit authorization FAILED: \(error)")
        }
    }

    func scheduleAlarm(for alarm: GeoAlarm) async throws {
        guard let nextFireDate = alarm.calculateNextAlarmTime() else { return }

        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: alarm.displayName)
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
            schedule = .relative(.init(
                time: .init(hour: alarm.hour!, minute: alarm.minute!),
                repeats: .never
            ))
        } else if let days = alarm.days, !days.isEmpty, let hour = alarm.hour, let minute = alarm.minute {
            let weekdays = days.map { $0.localeWeekday }
            schedule = .relative(.init(
                time: .init(hour: hour, minute: minute),
                repeats: .weekly(weekdays)
            ))
        } else {
            schedule = .fixed(nextFireDate)
        }

        let config = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            sound: sound
        )

        let scheduled = try await AlarmManager.shared.schedule(id: alarm.id, configuration: config)
        print("[Geoclock] AlarmKit scheduled alarm id=\(alarm.id) state=\(scheduled.state) for '\(alarm.displayName)'")
    }

    func cancelAlarm(for alarm: GeoAlarm) {
        try? AlarmManager.shared.cancel(id: alarm.id)
    }

    // MARK: - Observe alarm lifecycle

    private func startObservingAlarmUpdates() {
        alarmUpdatesTask?.cancel()
        alarmUpdatesTask = Task {
            for await activeAlarms in AlarmManager.shared.alarmUpdates {
                await handleAlarmUpdates(activeAlarms)
            }
        }
    }

    private func handleAlarmUpdates(_ activeAlarms: [Alarm]) async {
        guard let modelContainer else { return }

        let activeIDs = Set(activeAlarms.map(\.id))
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GeoAlarm>(
            predicate: #Predicate { $0.enabled == true }
        )

        guard let enabledAlarms = try? context.fetch(descriptor) else { return }

        for alarm in enabledAlarms where alarm.isNonRepeating {
            // An alarm missing from alarmUpdates is no longer scheduled (fired and done)
            if !activeIDs.contains(alarm.id), alarm.isInsideGeofence {
                alarm.enabled = false
                try? context.save()
            }
        }
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
