import Foundation
import SwiftData
import UserNotifications

class NotificationManager: NotificationScheduling {
    static let shared = NotificationManager()

    private static let upcomingCategory = "UPCOMING_ALARM"
    private static let cancelAction = "CANCEL_ALARM"
    private static let leadTimeSeconds: TimeInterval = 15 * 60

    private var modelContainer: ModelContainer?
    private var geofenceManager: GeofenceManager?
    private var alarmScheduler: AlarmScheduler?

    private init() {}

    func configure(modelContainer: ModelContainer, geofenceManager: GeofenceManager, alarmScheduler: AlarmScheduler) {
        self.modelContainer = modelContainer
        self.geofenceManager = geofenceManager
        self.alarmScheduler = alarmScheduler
    }

    func requestAuthorization() async {
        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    func registerCategories() {
        let cancelAction = UNNotificationAction(
            identifier: Self.cancelAction,
            title: "Cancel alarm",
            options: .destructive
        )
        let category = UNNotificationCategory(
            identifier: Self.upcomingCategory,
            actions: [cancelAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func scheduleUpcomingNotification(for alarm: GeoAlarm) {
        guard let nextFireDate = alarm.calculateNextAlarmTime() else { return }

        let leadTime = nextFireDate.timeIntervalSinceNow - Self.leadTimeSeconds
        let triggerInterval = max(leadTime, 1)

        let content = UNMutableNotificationContent()
        let formattedTime = nextFireDate.formatted(date: .omitted, time: .shortened)
        content.title = "Alarm at \(formattedTime)"
        content.body = alarm.displayName
        content.categoryIdentifier = Self.upcomingCategory
        content.userInfo = ["alarmId": alarm.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "upcoming-\(alarm.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func cancelUpcomingNotification(for alarm: GeoAlarm) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["upcoming-\(alarm.id.uuidString)"]
        )
    }

    @MainActor
    func handleCancelAction(alarmId: String) {
        guard let modelContainer, let geofenceManager, let alarmScheduler else { return }
        guard let uuid = UUID(uuidString: alarmId) else { return }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GeoAlarm>(
            predicate: #Predicate { $0.id == uuid }
        )

        guard let alarm = try? context.fetch(descriptor).first else { return }

        alarm.enabled = false
        try? context.save()

        geofenceManager.handleAlarmDisabled(alarm)
        alarmScheduler.cancelAlarm(for: alarm)
    }
}
