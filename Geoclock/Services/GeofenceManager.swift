import Combine
import CoreLocation
import Foundation
import SwiftData

class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private var modelContext: ModelContext?
    private var alarmScheduler: (any AlarmScheduling)?
    private var pendingGeofenceAlarms: [GeoAlarm] = []

    var monitoredRegionCount: Int {
        locationManager.monitoredRegions.count
    }

    static let maxGeofences = 20

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    private var notificationManager: (any NotificationScheduling)?

    func configure(
        modelContext: ModelContext,
        alarmScheduler: any AlarmScheduling,
        notificationManager: (any NotificationScheduling)? = nil
    ) {
        self.modelContext = modelContext
        self.alarmScheduler = alarmScheduler
        self.notificationManager = notificationManager
    }

    // MARK: - Authorization

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func ensureAlwaysAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        default:
            break
        }
    }

    // MARK: - Location

    func requestLocation() {
        locationManager.requestLocation()
    }

    // MARK: - Geofence management

    func registerGeofence(for alarm: GeoAlarm) {
        let region = CLCircularRegion(
            center: alarm.coordinate,
            radius: CLLocationDistance(alarm.radius),
            identifier: alarm.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)

        // Check if user is already inside this geofence
        if let userLocation {
            let alarmLocation = CLLocation(latitude: alarm.coordinate.latitude, longitude: alarm.coordinate.longitude)
            let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            let distance = userCLLocation.distance(from: alarmLocation)
            alarm.isInsideGeofence = distance <= Double(alarm.radius)

            if alarm.isInsideGeofence, alarm.enabled {
                notificationManager?.scheduleUpcomingNotification(for: alarm)
                Task {
                    do {
                        try await alarmScheduler?.scheduleAlarm(for: alarm)
                        print("[Geoclock] Alarm scheduled via registerGeofence for '\(alarm.displayName)'")
                    } catch {
                        print("[Geoclock] ERROR scheduling alarm in registerGeofence: \(error)")
                    }
                }
            }

            try? modelContext?.save()
        }
    }

    func removeGeofence(for alarm: GeoAlarm) {
        for region in locationManager.monitoredRegions where region.identifier == alarm.id.uuidString {
            locationManager.stopMonitoring(for: region)
            break
        }
    }

    func removeAllGeofences() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    // MARK: - App launch sync

    func reregisterGeofences() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<GeoAlarm>()
        guard let allAlarms = try? modelContext.fetch(descriptor) else { return }

        // Re-register geofences for all enabled alarms
        for alarm in allAlarms where alarm.enabled {
            registerGeofence(for: alarm)
        }

        // Disable expired non-repeating alarms
        disableExpiredAlarms(allAlarms)
    }

    func updateInsideGeofenceStatus() {
        guard let modelContext, let userLocation else { return }

        let descriptor = FetchDescriptor<GeoAlarm>()
        guard let allAlarms = try? modelContext.fetch(descriptor) else { return }

        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)

        for alarm in allAlarms {
            let alarmLocation = CLLocation(latitude: alarm.coordinate.latitude, longitude: alarm.coordinate.longitude)
            let distance = userCLLocation.distance(from: alarmLocation)
            let wasInside = alarm.isInsideGeofence
            let isNowInside = distance <= Double(alarm.radius)
            alarm.isInsideGeofence = isNowInside

            if alarm.enabled {
                if isNowInside && !wasInside {
                    // Enter transition — schedule
                    notificationManager?.scheduleUpcomingNotification(for: alarm)
                    Task {
                        do {
                            try await alarmScheduler?.scheduleAlarm(for: alarm)
                            print("[Geoclock] Alarm scheduled on enter for '\(alarm.displayName)'")
                        } catch {
                            print("[Geoclock] ERROR scheduling alarm on enter: \(error)")
                        }
                    }
                } else if isNowInside && wasInside {
                    // Still inside (e.g. app restart) — ensure alarm is scheduled
                    notificationManager?.scheduleUpcomingNotification(for: alarm)
                    Task {
                        do {
                            try await alarmScheduler?.scheduleAlarm(for: alarm)
                            print("[Geoclock] Alarm scheduled on still-inside for '\(alarm.displayName)'")
                        } catch {
                            print("[Geoclock] ERROR scheduling alarm on still-inside: \(error)")
                        }
                    }
                } else if !isNowInside && wasInside {
                    // Exit transition — cancel
                    alarmScheduler?.cancelAlarm(for: alarm)
                    notificationManager?.cancelUpcomingNotification(for: alarm)
                }
            }
        }
        try? modelContext.save()
    }

    private func disableExpiredAlarms(_ alarms: [GeoAlarm]) {
        for alarm in alarms where alarm.enabled && alarm.isExpired {
            alarm.enabled = false
            removeGeofence(for: alarm)
            alarmScheduler?.cancelAlarm(for: alarm)
            notificationManager?.cancelUpcomingNotification(for: alarm)
        }
        try? modelContext?.save()
    }

    // MARK: - Toggle handlers

    func handleAlarmEnabled(_ alarm: GeoAlarm) {
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            registerGeofence(for: alarm)
        } else {
            pendingGeofenceAlarms.append(alarm)
        }

        ensureAlwaysAuthorization()

        Task {
            if !(alarmScheduler?.isAuthorized ?? false) {
                await alarmScheduler?.requestAuthorization()
            }
        }
    }

    func handleAlarmDisabled(_ alarm: GeoAlarm) {
        removeGeofence(for: alarm)
        alarmScheduler?.cancelAlarm(for: alarm)
        notificationManager?.cancelUpcomingNotification(for: alarm)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last?.coordinate
        updateInsideGeofenceStatus()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        // Flush pending geofence registrations when authorization improves
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            let pending = pendingGeofenceAlarms
            pendingGeofenceAlarms.removeAll()
            for alarm in pending where alarm.enabled {
                registerGeofence(for: alarm)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let modelContext, let alarmScheduler else { return }
        guard let uuid = UUID(uuidString: region.identifier) else { return }

        let descriptor = FetchDescriptor<GeoAlarm>(
            predicate: #Predicate { $0.id == uuid }
        )

        guard let alarm = try? modelContext.fetch(descriptor).first else { return }

        alarm.isInsideGeofence = true
        try? modelContext.save()

        if alarm.enabled {
            notificationManager?.scheduleUpcomingNotification(for: alarm)
            Task {
                do {
                    try await alarmScheduler.scheduleAlarm(for: alarm)
                    print("[Geoclock] Alarm scheduled on didEnterRegion for '\(alarm.displayName)'")
                } catch {
                    print("[Geoclock] ERROR scheduling alarm on didEnterRegion: \(error)")
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let modelContext, let alarmScheduler else { return }
        guard let uuid = UUID(uuidString: region.identifier) else { return }

        let descriptor = FetchDescriptor<GeoAlarm>(
            predicate: #Predicate { $0.id == uuid }
        )

        guard let alarm = try? modelContext.fetch(descriptor).first else { return }

        alarm.isInsideGeofence = false
        try? modelContext.save()

        alarmScheduler.cancelAlarm(for: alarm)
        notificationManager?.cancelUpcomingNotification(for: alarm)
    }
}
