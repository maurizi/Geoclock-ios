import Foundation
@testable import Geoclock
import SwiftData

@MainActor
class MockAlarmScheduler: AlarmScheduling {
    var isAuthorized = true
    var scheduledAlarmIDs: [UUID] = []
    var cancelledAlarmIDs: [UUID] = []

    func requestAuthorization() async {}

    func scheduleAlarm(for alarm: GeoAlarm) async throws {
        scheduledAlarmIDs.append(alarm.id)
    }

    func cancelAlarm(for alarm: GeoAlarm) {
        cancelledAlarmIDs.append(alarm.id)
    }
}

class MockNotificationScheduler: NotificationScheduling {
    var scheduledIDs: [UUID] = []
    var cancelledIDs: [UUID] = []

    func scheduleUpcomingNotification(for alarm: GeoAlarm) {
        scheduledIDs.append(alarm.id)
    }

    func cancelUpcomingNotification(for alarm: GeoAlarm) {
        cancelledIDs.append(alarm.id)
    }
}

func makeTestModelContext() -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: GeoAlarm.self, configurations: config)
    return ModelContext(container)
}
