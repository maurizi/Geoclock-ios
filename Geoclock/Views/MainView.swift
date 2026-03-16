import SwiftUI
import SwiftData
import MapKit

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GeoAlarm.hour) private var alarms: [GeoAlarm]
    @EnvironmentObject private var geofenceManager: GeofenceManager
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    @State private var mapExpanded = false
    @State private var selectedAlarm: GeoAlarm?
    @State private var showingAddSheet = false
    @State private var mapCameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var alarmToDelete: GeoAlarm?
    @State private var showingPermissionAlert = false

    private var alarmsInRange: [GeoAlarm] {
        alarms.filter(\.isInsideGeofence)
    }

    private var alarmsOutOfRange: [GeoAlarm] {
        alarms.filter { !$0.isInsideGeofence }
    }

    var body: some View {
        VStack(spacing: 0) {
            mapSection
            Divider()
            alarmList
        }
        .overlay(alignment: .bottomTrailing) {
            addButton
        }
        .overlay(alignment: .bottomLeading) {
            geofenceLimitIndicator
        }
        .sheet(isPresented: $showingAddSheet) {
            AlarmEditSheet(alarm: nil, userLocation: geofenceManager.userLocation)
        }
        .sheet(item: $selectedAlarm) { alarm in
            AlarmEditSheet(alarm: alarm)
        }
        .confirmationDialog(
            "Delete alarm?",
            isPresented: .init(
                get: { alarmToDelete != nil },
                set: { if !$0 { alarmToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let alarm = alarmToDelete {
                    deleteAlarm(alarm)
                }
            }
        } message: {
            Text("This alarm will be permanently removed.")
        }
        .onAppear {
            geofenceManager.configure(modelContext: modelContext, alarmScheduler: alarmScheduler)
            geofenceManager.requestWhenInUseAuthorization()
            geofenceManager.requestLocation()
            geofenceManager.reregisterGeofences()
        }
        .alert(permissionAlertTitle, isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(permissionAlertMessage)
        }
        .onChange(of: geofenceManager.authorizationStatus) { _, _ in
            updatePermissionAlert()
        }
        .onChange(of: alarms.count) { _, _ in
            updatePermissionAlert()
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $mapCameraPosition) {
            UserAnnotation()

            ForEach(alarms, id: \.id) { alarm in
                MapCircle(center: alarm.coordinate, radius: CLLocationDistance(alarm.radius))
                    .foregroundStyle(alarm.enabled ? .blue.opacity(0.15) : .gray.opacity(0.1))
                    .stroke(alarm.enabled ? .blue.opacity(0.4) : .gray.opacity(0.3), lineWidth: 1)

                Annotation(alarm.displayName, coordinate: alarm.coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .frame(height: mapExpanded ? 250 : 120)
        .animation(.easeInOut(duration: 0.3), value: mapExpanded)
    }

    // MARK: - Alarm list

    private var alarmList: some View {
        Group {
            if alarms.isEmpty {
                emptyState
            } else {
                List {
                    if !alarmsInRange.isEmpty {
                        Section("Within range") {
                            ForEach(alarmsInRange, id: \.id) { alarm in
                                alarmRow(alarm)
                            }
                        }
                    }

                    if !alarmsOutOfRange.isEmpty {
                        Section("Out of range") {
                            ForEach(alarmsOutOfRange, id: \.id) { alarm in
                                alarmRow(alarm)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Permission alert

    private var permissionAlertTitle: String {
        switch geofenceManager.authorizationStatus {
        case .denied, .restricted:
            return "Location Access Required"
        case .authorizedWhenInUse:
            return "Always-On Location Needed"
        default:
            return ""
        }
    }

    private var permissionAlertMessage: String {
        switch geofenceManager.authorizationStatus {
        case .denied, .restricted:
            return "Geoclock needs location access to know when you're near your alarm locations."
        case .authorizedWhenInUse:
            return "Geoclock needs to check your location in the background to trigger alarms when you arrive at a place. Please change location access to \"Always\" in Settings."
        default:
            return ""
        }
    }

    private func updatePermissionAlert() {
        let status = geofenceManager.authorizationStatus
        let needsAlert = (status == .denied || status == .restricted || status == .authorizedWhenInUse)
        showingPermissionAlert = needsAlert && !alarms.isEmpty
    }

    private func alarmRow(_ alarm: GeoAlarm) -> some View {
        AlarmCardView(alarm: alarm, userLocation: geofenceManager.userLocation) { enabled in
            if enabled {
                geofenceManager.handleAlarmEnabled(alarm)
            } else {
                geofenceManager.handleAlarmDisabled(alarm)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedAlarm = alarm
            mapExpanded = true
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                alarmToDelete = alarm
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "alarm")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No alarms yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Tap + to add your first location alarm")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - FAB

    private var addButton: some View {
        Button {
            showingAddSheet = true
            mapExpanded = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(.blue))
                .shadow(radius: 4, y: 2)
        }
        .padding(16)
    }

    // MARK: - Geofence limit indicator

    private var geofenceLimitIndicator: some View {
        Group {
            let enabledCount = alarms.filter(\.enabled).count
            if enabledCount > 0 {
                Text("\(enabledCount)/\(GeofenceManager.maxGeofences) alarms")
                    .font(.caption2)
                    .foregroundStyle(enabledCount >= GeofenceManager.maxGeofences ? .red : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(16)
            }
        }
    }

    private func deleteAlarm(_ alarm: GeoAlarm) {
        geofenceManager.removeGeofence(for: alarm)
        alarmScheduler.cancelAlarm(for: alarm)
        modelContext.delete(alarm)
    }
}
