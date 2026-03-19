import CoreLocation
import Foundation
@testable import Geoclock
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct GeofenceManagerTests {

    // swiftlint:disable:next large_tuple
    private func makeSUT() -> (GeofenceManager, MockAlarmScheduler, MockNotificationScheduler, ModelContext) {
        let manager = GeofenceManager()
        let scheduler = MockAlarmScheduler()
        let notifications = MockNotificationScheduler()
        let context = makeTestModelContext()
        manager.configure(modelContext: context, alarmScheduler: scheduler, notificationManager: notifications)
        return (manager, scheduler, notifications, context)
    }

    private func makeAlarm(
        context: ModelContext,
        latitude: Double = 40.7580,
        longitude: Double = -73.9855,
        radius: Int = 200,
        hour: Int = 8,
        minute: Int = 0,
        enabled: Bool = true,
        isInsideGeofence: Bool = false,
        days: Set<Weekday>? = nil,
        time: Int? = nil
    ) -> GeoAlarm {
        let alarm = GeoAlarm(
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            place: "Test Place",
            hour: hour,
            minute: minute,
            days: days,
            enabled: enabled,
            isInsideGeofence: isInsideGeofence,
            time: time
        )
        context.insert(alarm)
        // swiftlint:disable:next force_try
        try! context.save()
        return alarm
    }

    // MARK: - registerGeofence

    @Test func registerGeofence_insideRadius_schedulesAlarm() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context)

        // Set user location to the same spot as the alarm (inside radius)
        manager.userLocation = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        manager.registerGeofence(for: alarm)

        // Wait briefly for the Task to complete
        try await Task.sleep(for: .milliseconds(100))

        #expect(scheduler.scheduledAlarmIDs.contains(alarm.id))
        #expect(notifications.scheduledIDs.contains(alarm.id))
    }

    @Test func registerGeofence_outsideRadius_doesNotSchedule() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context)

        // Set user location far away
        manager.userLocation = CLLocationCoordinate2D(latitude: 41.0, longitude: -74.0)

        manager.registerGeofence(for: alarm)

        try await Task.sleep(for: .milliseconds(100))

        #expect(scheduler.scheduledAlarmIDs.isEmpty)
        #expect(notifications.scheduledIDs.isEmpty)
    }

    @Test func registerGeofence_savesIsInsideGeofence() async throws {
        let (manager, _, _, context) = makeSUT()
        let alarm = makeAlarm(context: context)

        #expect(!alarm.isInsideGeofence)

        // Set user location inside the geofence
        manager.userLocation = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        manager.registerGeofence(for: alarm)

        #expect(alarm.isInsideGeofence)

        // Verify the context was saved (fetch fresh to confirm persistence)
        let descriptor = FetchDescriptor<GeoAlarm>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.first?.isInsideGeofence == true)
    }

    @Test func registerGeofence_noUserLocation_skipsCheck() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context)

        // userLocation is nil by default
        manager.registerGeofence(for: alarm)

        try await Task.sleep(for: .milliseconds(100))

        #expect(scheduler.scheduledAlarmIDs.isEmpty)
        #expect(notifications.scheduledIDs.isEmpty)
        #expect(!alarm.isInsideGeofence)
    }

    // MARK: - updateInsideGeofenceStatus

    @Test func updateStatus_enterTransition_schedules() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context, isInsideGeofence: false)

        // Set user location inside the geofence
        manager.userLocation = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        manager.updateInsideGeofenceStatus()

        try await Task.sleep(for: .milliseconds(100))

        #expect(alarm.isInsideGeofence)
        #expect(scheduler.scheduledAlarmIDs.contains(alarm.id))
        #expect(notifications.scheduledIDs.contains(alarm.id))
    }

    @Test func updateStatus_exitTransition_cancels() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context, isInsideGeofence: true)

        // Set user location far away
        manager.userLocation = CLLocationCoordinate2D(latitude: 41.0, longitude: -74.0)

        manager.updateInsideGeofenceStatus()

        #expect(!alarm.isInsideGeofence)
        #expect(scheduler.cancelledAlarmIDs.contains(alarm.id))
        #expect(notifications.cancelledIDs.contains(alarm.id))
    }

    @Test func updateStatus_stillInside_schedulesAlarm() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        // Alarm already marked as inside (simulating app restart with persisted state)
        let alarm = makeAlarm(context: context, isInsideGeofence: true)

        // User is still at the same location
        manager.userLocation = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        manager.updateInsideGeofenceStatus()

        try await Task.sleep(for: .milliseconds(100))

        #expect(alarm.isInsideGeofence)
        #expect(scheduler.scheduledAlarmIDs.contains(alarm.id))
        #expect(notifications.scheduledIDs.contains(alarm.id))
    }

    @Test func updateStatus_stillOutside_noAction() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context, isInsideGeofence: false)

        // User is far away
        manager.userLocation = CLLocationCoordinate2D(latitude: 41.0, longitude: -74.0)

        manager.updateInsideGeofenceStatus()

        try await Task.sleep(for: .milliseconds(100))

        #expect(!alarm.isInsideGeofence)
        #expect(scheduler.scheduledAlarmIDs.isEmpty)
        #expect(scheduler.cancelledAlarmIDs.isEmpty)
        #expect(notifications.scheduledIDs.isEmpty)
        #expect(notifications.cancelledIDs.isEmpty)
    }

    // MARK: - handleAlarmEnabled / handleAlarmDisabled

    @Test func handleAlarmEnabled_registersGeofence() async throws {
        let (manager, scheduler, _, context) = makeSUT()
        let alarm = makeAlarm(context: context)

        // In test environment, authorization is .notDetermined so alarm goes to pending
        // After that, ensureAlwaysAuthorization is called and AlarmKit auth is requested
        manager.handleAlarmEnabled(alarm)

        try await Task.sleep(for: .milliseconds(100))

        // Verify AlarmKit authorization was requested (mock starts authorized)
        #expect(scheduler.isAuthorized)
    }

    @Test func handleAlarmDisabled_cancelsEverything() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context)

        // First register, then disable
        manager.handleAlarmEnabled(alarm)
        manager.handleAlarmDisabled(alarm)

        #expect(scheduler.cancelledAlarmIDs.contains(alarm.id))
        #expect(notifications.cancelledIDs.contains(alarm.id))
    }

    // MARK: - reregisterGeofences

    @Test func reregisterGeofences_enabledOnly() async throws {
        let (manager, scheduler, _, context) = makeSUT()
        let enabledAlarm = makeAlarm(context: context, latitude: 40.7580, longitude: -73.9855)
        let disabledAlarm = makeAlarm(context: context, latitude: 40.760, longitude: -73.980, enabled: false)

        // Set user location inside the enabled alarm's geofence
        manager.userLocation = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        manager.reregisterGeofences()

        try await Task.sleep(for: .milliseconds(100))

        // Enabled alarm inside radius should have been scheduled
        #expect(scheduler.scheduledAlarmIDs.contains(enabledAlarm.id))
        // Disabled alarm should not have been scheduled
        #expect(!scheduler.scheduledAlarmIDs.contains(disabledAlarm.id))
    }

    // MARK: - disableExpiredAlarms

    @Test func disableExpiredAlarms_disablesAndCancels() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let pastMs = Int((Date.now.timeIntervalSince1970 - 3600) * 1000)
        let alarm = makeAlarm(context: context, time: pastMs)

        #expect(alarm.enabled)
        #expect(alarm.isExpired)

        manager.reregisterGeofences()

        #expect(!alarm.enabled)
        #expect(scheduler.cancelledAlarmIDs.contains(alarm.id))
        #expect(notifications.cancelledIDs.contains(alarm.id))
    }

    @Test func disableExpiredAlarms_skipsRepeating() async throws {
        let (manager, scheduler, _, context) = makeSUT()
        let pastMs = Int((Date.now.timeIntervalSince1970 - 3600) * 1000)
        let alarm = makeAlarm(context: context, days: [.monday, .friday], time: pastMs)

        #expect(alarm.enabled)
        #expect(!alarm.isExpired) // Repeating alarms never expire

        manager.reregisterGeofences()

        #expect(alarm.enabled) // Should still be enabled
        #expect(!scheduler.cancelledAlarmIDs.contains(alarm.id))
    }

    // MARK: - CLLocationManagerDelegate region events

    @Test func didEnterRegion_schedulesAlarm() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context)

        let region = CLCircularRegion(
            center: alarm.coordinate,
            radius: CLLocationDistance(alarm.radius),
            identifier: alarm.id.uuidString
        )

        manager.locationManager(manager.locationManager, didEnterRegion: region)

        try await Task.sleep(for: .milliseconds(100))

        #expect(alarm.isInsideGeofence)
        #expect(scheduler.scheduledAlarmIDs.contains(alarm.id))
        #expect(notifications.scheduledIDs.contains(alarm.id))
    }

    @Test func didExitRegion_cancelsAlarm() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context, isInsideGeofence: true)

        let region = CLCircularRegion(
            center: alarm.coordinate,
            radius: CLLocationDistance(alarm.radius),
            identifier: alarm.id.uuidString
        )

        manager.locationManager(manager.locationManager, didExitRegion: region)

        #expect(!alarm.isInsideGeofence)
        #expect(scheduler.cancelledAlarmIDs.contains(alarm.id))
        #expect(notifications.cancelledIDs.contains(alarm.id))
    }

    @Test func didEnterRegion_disabledAlarm_noSchedule() async throws {
        let (manager, scheduler, notifications, context) = makeSUT()
        let alarm = makeAlarm(context: context, enabled: false)

        let region = CLCircularRegion(
            center: alarm.coordinate,
            radius: CLLocationDistance(alarm.radius),
            identifier: alarm.id.uuidString
        )

        manager.locationManager(manager.locationManager, didEnterRegion: region)

        try await Task.sleep(for: .milliseconds(100))

        #expect(alarm.isInsideGeofence) // Still set to true
        #expect(scheduler.scheduledAlarmIDs.isEmpty) // But not scheduled
        #expect(notifications.scheduledIDs.isEmpty)
    }
}
