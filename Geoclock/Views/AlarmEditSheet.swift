import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct AlarmEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var geofenceManager: GeofenceManager
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    let alarm: GeoAlarm?

    @State private var hour: Int
    @State private var minute: Int
    @State private var days: Set<Weekday>
    @State private var radius: Int
    @State private var latitude: Double
    @State private var longitude: Double
    @State private var place: String
    @State private var enabled: Bool
    @State private var showingLocationPicker = false

    private var isNew: Bool { alarm == nil }

    init(alarm: GeoAlarm?, userLocation: CLLocationCoordinate2D? = nil) {
        self.alarm = alarm
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        _hour = State(initialValue: alarm?.hour ?? now.hour ?? 8)
        _minute = State(initialValue: alarm?.minute ?? now.minute ?? 0)
        _days = State(initialValue: alarm?.days ?? [])
        _radius = State(initialValue: alarm?.radius ?? 200)
        _latitude = State(initialValue: alarm?.latitude ?? userLocation?.latitude ?? 0)
        _longitude = State(initialValue: alarm?.longitude ?? userLocation?.longitude ?? 0)
        _place = State(initialValue: alarm?.place ?? "")
        _enabled = State(initialValue: alarm?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                locationSection
                timeSection
                daysSection

                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) {
                            deleteAlarm()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add alarm" : "Edit alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAlarm() }
                }
            }
            .onAppear {
                if place.isEmpty && (latitude != 0 || longitude != 0) {
                    reverseGeocodeCoordinates()
                }
            }
            .fullScreenCover(isPresented: $showingLocationPicker) {
                LocationPickerView(
                    latitude: $latitude,
                    longitude: $longitude,
                    radius: $radius,
                    place: $place
                )
            }
        }
    }

    // MARK: - Sections

    private var locationSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    if !place.isEmpty {
                        Text(place)
                        Text(GeoAlarm.radiusSizeLabel(for: radius))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if latitude != 0 || longitude != 0 {
                        Text(String(format: "%.4f, %.4f", latitude, longitude))
                            .foregroundStyle(.secondary)
                        Text(GeoAlarm.radiusSizeLabel(for: radius))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No location set")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Change") {
                    showingLocationPicker = true
                }
            }
        } header: {
            Text("Location")
        }
    }

    private var timeSection: some View {
        Section("Time") {
            TimeWheel(hour: $hour, minute: $minute)
        }
    }

    private var daysSection: some View {
        Section("Repeats on") {
            DayPicker(selectedDays: $days)
        }
    }

    // MARK: - Actions

    private func saveAlarm() {
        if let alarm {
            alarm.hour = hour
            alarm.minute = minute
            alarm.days = days.isEmpty ? nil : days
            alarm.radius = radius
            alarm.latitude = latitude
            alarm.longitude = longitude
            alarm.place = place.isEmpty ? nil : place
            alarm.enabled = enabled

            if enabled, let nextTime = alarm.calculateNextAlarmTime() {
                alarm.time = Int(nextTime.timeIntervalSince1970 * 1000)
            }

            geofenceManager.removeGeofence(for: alarm)
            if enabled {
                geofenceManager.registerGeofence(for: alarm)
            }
        } else {
            let newAlarm = GeoAlarm(
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                place: place.isEmpty ? nil : place,
                hour: hour,
                minute: minute,
                days: days.isEmpty ? nil : days,
                enabled: enabled
            )

            if enabled, let nextTime = newAlarm.calculateNextAlarmTime() {
                newAlarm.time = Int(nextTime.timeIntervalSince1970 * 1000)
            }

            modelContext.insert(newAlarm)

            if enabled {
                geofenceManager.registerGeofence(for: newAlarm)
            }

            // Reverse geocode if no place name
            if place.isEmpty {
                reverseGeocode(newAlarm)
            }
        }

        dismiss()
    }

    private func deleteAlarm() {
        if let alarm {
            geofenceManager.removeGeofence(for: alarm)
            alarmScheduler.cancelAlarm(for: alarm)
            NotificationManager.shared.cancelUpcomingNotification(for: alarm)
            modelContext.delete(alarm)
        }
        dismiss()
    }

    private func reverseGeocode(_ alarm: GeoAlarm) {
        let location = CLLocation(latitude: alarm.latitude, longitude: alarm.longitude)
        Task {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = (try? await request.mapItems)?.first else { return }
            alarm.place = AddressFormatter.shortAddress(from: item)
        }
    }

    private func reverseGeocodeCoordinates() {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        Task {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = (try? await request.mapItems)?.first else { return }
            place = AddressFormatter.shortAddress(from: item) ?? ""
        }
    }
}
