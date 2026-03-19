import SwiftData
import SwiftUI
import UserNotifications

@main
struct GeoclockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var geofenceManager = GeofenceManager()
    @StateObject private var alarmScheduler = AlarmScheduler()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            GeoAlarm.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(geofenceManager)
                .environmentObject(alarmScheduler)
                .task {
                    alarmScheduler.configure(modelContainer: sharedModelContainer)
                    await alarmScheduler.requestAuthorization()
                    NotificationManager.shared.configure(
                        modelContainer: sharedModelContainer,
                        geofenceManager: geofenceManager,
                        alarmScheduler: alarmScheduler
                    )
                    await NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.registerCategories()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == "CANCEL_ALARM",
           let alarmId = response.notification.request.content.userInfo["alarmId"] as? String {
            NotificationManager.shared.handleCancelAction(alarmId: alarmId)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
