import Foundation

@MainActor
protocol AlarmScheduling {
    var isAuthorized: Bool { get }
    func requestAuthorization() async
    func scheduleAlarm(for alarm: GeoAlarm) async throws
    func cancelAlarm(for alarm: GeoAlarm)
}

protocol NotificationScheduling {
    func scheduleUpcomingNotification(for alarm: GeoAlarm)
    func cancelUpcomingNotification(for alarm: GeoAlarm)
}
