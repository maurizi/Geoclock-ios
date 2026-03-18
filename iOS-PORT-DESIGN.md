# Geoclock iOS — Full Design

## Context

Geoclock is an Android alarm clock app that fires alarms based on geofence entry + time of day. With AlarmKit (iOS 26, WWDC 2025), Apple now allows third-party apps to schedule system-level alarms with full lock screen UI, Focus/Silent mode bypass, snooze, and Dynamic Island integration. Combined with CoreLocation's background geofence monitoring, the full Geoclock concept is now portable to iOS.

**Minimum deployment target**: iOS 26

---

## Core Architecture

**Language/UI**: Swift + SwiftUI (with MapKit via `Map` view)
**Data**: SwiftData (modern persistence, replaces Core Data / UserDefaults+Codable)
**Alarm**: AlarmKit (`AlarmManager`, `AlarmConfiguration`)
**Location**: CoreLocation (`CLLocationManager`, `CLCircularRegion`)
**Search**: MapKit (`MKLocalSearch`, `MKLocalSearchCompleter`)

No Google dependencies. All Apple-native frameworks.

---

## Data Model

```swift
@Model
class GeoAlarm {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var radius: Int              // meters (50–500)
    var place: String?           // reverse-geocoded or search result name
    var hour: Int?               // 0–23, nil = no time set
    var minute: Int?             // 0–59
    var days: Set<Weekday>?      // nil/empty = one-shot
    var enabled: Bool
    var ringtoneURL: URL?        // local sound file URL
    var isInsideGeofence: Bool   // tracked by geofence callbacks

    var coordinate: CLLocationCoordinate2D { ... }
}
```

SwiftData handles persistence automatically. No manual JSON serialization needed (replaces SharedPreferences + GSON).

---

## Alarm Lifecycle — The Core Flow

This is the critical path and the direct equivalent of the Android flow:

```
┌─────────────────────────────────────────────────────────┐
│ 1. User creates alarm (location + time + days + radius) │
│ 2. App registers CLCircularRegion with CLLocationManager│
│ 3. User goes about their day, app is suspended          │
├─────────────────────────────────────────────────────────┤
│ 4. iOS wakes app: didEnterRegion callback (~10s)        │
│ 5. App calculates next alarm time for this GeoAlarm     │
│ 6. App calls AlarmManager.schedule(AlarmConfiguration)  │
│ 7. App suspends again                                   │
├─────────────────────────────────────────────────────────┤
│ 8. At scheduled time, iOS fires the alarm:              │
│    - Lock screen full-screen snooze/stop UI             │
│    - Alarm sound plays (bypasses Silent + Focus)        │
│    - Dynamic Island shows alarm info                    │
│    - Apple Watch alerts                                 │
├─────────────────────────────────────────────────────────┤
│ 9. iOS wakes app: didExitRegion callback                │
│ 10. App cancels any pending AlarmKit alarm for this     │
│     GeoAlarm (user left the area)                       │
└─────────────────────────────────────────────────────────┘
```

### Android → iOS mapping for this flow

| Step | Android | iOS |
|------|---------|-----|
| Geofence registration | `GeofencingClient.addGeofences()` | `CLLocationManager.startMonitoring(for: CLCircularRegion)` |
| Geofence enter callback | `GeofenceReceiver` (BroadcastReceiver) | `CLLocationManagerDelegate.locationManager(_:didEnterRegion:)` |
| Schedule alarm | `AlarmManager.setAlarmClock()` | `AlarmManager.schedule(AlarmConfiguration)` (AlarmKit) |
| Alarm fires | `AlarmClockReceiver` → `AlarmRingingService` | System handles everything (lock screen UI, audio, snooze) |
| Geofence exit | `GeofenceReceiver` EXIT | `locationManager(_:didExitRegion:)` |
| Cancel alarm | `AlarmManager.cancel()` | `AlarmManager.cancel(identifier:)` |
| Snooze | `AlarmRingingService.scheduleSnooze()` → manual reschedule | System-provided snooze button (built into AlarmKit UI) |
| Reboot recovery | `InitializationReceiver` BOOT_COMPLETED → re-register | iOS re-delivers geofence events automatically — no code needed |

---

## Screen-by-Screen Design

### 1. Main Screen (≈ MapActivity)

Split view layout, same concept as Android:

- **Top**: `Map` view (MapKit SwiftUI) showing alarm geofences as `MapCircle` overlays
  - Collapsed height ~160pt, expands on alarm tap
  - Gestures disabled in collapsed mode
  - User location dot shown
- **Bottom**: `List` of alarm cards in a `ScrollView`
  - Grouped by "Within range" / "Out of range" sections (same logic as `AlarmListAdapter.rebuildItems`)
  - Each card: time, days summary, distance to edge, place name, radius label, enable toggle
  - Swipe-to-delete
- **FAB**: "+" button → opens add alarm sheet

```swift
struct MainView: View {
    @Query var alarms: [GeoAlarm]
    @State private var mapExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            MapSection(alarms: alarms, expanded: $mapExpanded)
            AlarmListSection(alarms: alarms, onTap: { alarm in mapExpanded = true })
        }
        .overlay(alignment: .bottomTrailing) { AddAlarmButton() }
    }
}
```

### 2. Alarm Edit Sheet (≈ GeoAlarmFragment)

Presented as a `.sheet` modal:

- Location preview + "Change" button → pushes LocationPickerView
- `DatePicker` for time (hour:minute wheel style)
- Day-of-week toggle buttons (M T W Th F Sa Su)
- Radius shown as label (set in location picker)
- Ringtone picker (system sound picker or bundled sounds)
- Save / Delete / Cancel buttons

### 3. Location Picker (≈ LocationPickerActivity)

Full-screen map with:

- `Map` view with draggable annotation (pin)
- `MKCircle` overlay showing geofence radius
- Radius slider (50–500m)
- Search bar using `MKLocalSearchCompleter` for autocomplete, `MKLocalSearch` for results
  - Replaces Google Places Autocomplete — no API key needed
- "My Location" button to center on current position
- Confirm button returns coordinate + radius + place name

### 4. Alarm Ringing (system-managed via AlarmKit)

**This screen doesn't need to be built.** AlarmKit provides the system alarm UI:
- Full-screen lock screen presentation with Stop and Snooze buttons
- Dynamic Island compact/expanded views
- Apple Watch mirroring
- The app provides: alarm sound, display metadata via `AlarmMetadata`

The app defines a Live Activity via `AlarmMetadata` conformance to customize what's shown:
```swift
struct GeoAlarmMetadata: AlarmMetadata {
    var placeName: String
    var alarmTime: String
}
```

---

## Key Services

### GeofenceManager

Replaces `LocationServiceGoogle` + `GeofenceReceiver` + `InitializationReceiver`.

```swift
class GeofenceManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let alarmScheduler: AlarmScheduler

    func registerGeofence(for alarm: GeoAlarm) {
        let region = CLCircularRegion(
            center: alarm.coordinate,
            radius: CLLocationDistance(alarm.radius),
            identifier: alarm.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
    }

    func removeGeofence(for alarm: GeoAlarm) {
        // find monitored region by identifier, stopMonitoring
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // Find matching GeoAlarm by region.identifier
        // Calculate next alarm time
        // Call alarmScheduler.scheduleAlarm(for:)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // Cancel any pending AlarmKit alarm for this GeoAlarm
        alarmScheduler.cancelAlarm(for: region.identifier)
    }
}
```

**Key difference from Android**: No `InitializationReceiver` / BOOT_COMPLETED equivalent needed. iOS automatically re-delivers geofence monitoring after reboot. The `CLLocationManagerDelegate` callbacks fire again.

**Region limit**: iOS allows 20 monitored regions (vs Android's 100). Sufficient for a personal alarm app.

### AlarmScheduler

Replaces `ActiveAlarmManager` + `AlarmClockReceiver` + `AlarmRingingService`.

```swift
class AlarmScheduler {
    private let alarmManager = AlarmManager()

    func scheduleAlarm(for alarm: GeoAlarm) async throws {
        let nextFireDate = alarm.calculateNextAlarmTime()

        let config = AlarmManager.AlarmConfiguration(
            schedule: .date(nextFireDate, timeZone: .current),
            sound: alarm.ringtoneURL.map { .custom($0) } ?? .default,
            metadata: GeoAlarmMetadata(
                placeName: alarm.place ?? "Alarm",
                alarmTime: nextFireDate.formatted(date: .omitted, time: .shortened)
            )
        )

        try await alarmManager.schedule(config, identifier: alarm.id.uuidString)
    }

    func cancelAlarm(for identifier: String) {
        alarmManager.cancel(identifier: identifier)
    }
}
```

**Key difference from Android**: No `AlarmRingingService`, no `AlarmRingingActivity`, no notification channel setup, no foreground service, no vibration management, no lock screen flags. AlarmKit handles all of this at the system level. This is a massive simplification.

**Snooze**: System-provided. No `SNOOZE_DURATION_MS`, no manual reschedule logic. The AlarmKit snooze button on the lock screen just works.

### Alarm Time Calculation

Port directly from `GeoAlarm.calculateAlarmTime()` — the logic is pure date math:

```swift
extension GeoAlarm {
    func calculateNextAlarmTime(from now: Date = .now) -> Date {
        guard let hour, let minute else { return now }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let days, !days.isEmpty else {
            // One-shot: today if in future, else tomorrow
            let candidate = calendar.date(from: components)!
            return candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)!
        }

        // Repeating: find soonest matching weekday
        // (same logic as Android's GeoAlarm.calculateAlarmTime)
        ...
    }
}
```

---

## Permissions

| Permission | When requested | iOS API |
|---|---|---|
| AlarmKit | First alarm save | `AlarmManager.requestAuthorization()` — requires `NSAlarmKitUsageDescription` in Info.plist |
| Location (When In Use) | App launch | `CLLocationManager.requestWhenInUseAuthorization()` |
| Location (Always) | First alarm enable | `CLLocationManager.requestAlwaysAuthorization()` — required for background geofencing |

**Compared to Android's 14 permissions**, iOS needs just 3 authorization requests. No exact alarm permission, no notification permission (AlarmKit handles that), no foreground service permission, no boot receiver, no vibrate permission, no full-screen intent permission.

---

## What's Simpler on iOS

| Concern | Android complexity | iOS equivalent |
|---|---|---|
| Alarm ringing UI | Custom `AlarmRingingActivity` + lock screen flags + keyguard dismiss | AlarmKit system UI (zero code) |
| Audio playback | `AlarmRingingService` foreground service + `RingtoneManager` + `VibratorManager` | AlarmKit handles audio + haptics |
| Snooze | Manual `AlarmManager.setAlarmClock()` reschedule + broadcast receiver | System snooze button (zero code) |
| DND bypass | Automatic with `setAlarmClock` but requires exact alarm permission dance | AlarmKit alarms bypass Focus by default |
| Notification channels | 2 channels, builder pattern, importance levels | Not needed — AlarmKit is not a notification |
| Boot recovery | `InitializationReceiver` + `JobIntentService` + re-register all geofences | Automatic — iOS re-delivers region events |
| Upcoming notification | `NotificationReceiver` + `AlarmManager.set()` 15min before | Could use `UNNotificationRequest` but optional |
| Permissions | 14 manifest permissions, 4 runtime request chains | 3 authorizations |

---

## What's Different / Harder on iOS

| Concern | Notes |
|---|---|
| **20 geofence limit** | iOS caps `CLCircularRegion` monitoring at 20 (vs Android's 100). Fine for personal use but worth showing a count in the UI. |
| **AlarmKit is system-managed** | The alarm "doesn't wake up your app" — you can't run custom code when it fires. No streaming audio, no custom animation. The app provides metadata + sound file, the system does the rest. |
| **No swipe-dismiss detection** | AlarmKit v1 doesn't call the stop intent when the user swipes an alarm away, so the app can't distinguish "snoozed" from "dismissed." |
| **Local sounds only** | No Spotify/streaming integration for alarm sounds. Must be bundled or downloaded sound files. |
| **No custom ringing UI** | Can't build a custom full-screen alarm screen. The system UI is what the user sees. Live Activity / Dynamic Island customization is the extent of it. |

---

## Project Structure

```
Geoclock-iOS/
├── GeoclockApp.swift               # App entry, SwiftData container setup
├── Models/
│   └── GeoAlarm.swift              # @Model, calculateNextAlarmTime()
├── Services/
│   ├── GeofenceManager.swift       # CLLocationManager delegate, region monitoring
│   └── AlarmScheduler.swift        # AlarmKit AlarmManager wrapper
├── Views/
│   ├── MainView.swift              # Split map + alarm list
│   ├── AlarmCardView.swift         # Single alarm card (time, days, distance, toggle)
│   ├── AlarmEditSheet.swift        # Add/edit alarm modal
│   ├── LocationPickerView.swift    # Full-screen map picker + search + radius
│   └── Components/
│       ├── DayPicker.swift         # M T W Th F Sa Su toggle row
│       └── RadiusSlider.swift      # 50–500m slider with label
├── Utilities/
│   ├── DistanceFormatter.swift     # Metric/imperial via Locale.current.measurementSystem
│   ├── DaysSummary.swift           # "Weekdays", "Every day", "Mon, Wed, Fri"
│   └── ReverseGeocoder.swift       # CLGeocoder async wrapper
├── LiveActivity/
│   └── AlarmLiveActivity.swift     # AlarmMetadata conformance, Live Activity UI
├── Info.plist                       # NSAlarmKitUsageDescription, NSLocationAlwaysAndWhenInUseUsageDescription
└── Assets.xcassets/
    └── AlarmSounds/                # Bundled alarm sound files
```

---

## Component Mapping Summary

| Android Class | iOS Equivalent | Framework |
|---|---|---|
| `GeoAlarm` (Lombok @Value) | `GeoAlarm` (SwiftData @Model) | SwiftData |
| `MapActivity` | `MainView` | SwiftUI + MapKit |
| `LocationPickerActivity` | `LocationPickerView` | SwiftUI + MapKit |
| `GeoAlarmFragment` | `AlarmEditSheet` | SwiftUI |
| `AlarmRingingActivity` | *Not needed* | AlarmKit system UI |
| `AlarmRingingService` | *Not needed* | AlarmKit system audio |
| `AlarmListAdapter` | `AlarmCardView` + `List` | SwiftUI |
| `LocationServiceGoogle` | `GeofenceManager` | CoreLocation |
| `ActiveAlarmManager` | `AlarmScheduler` | AlarmKit |
| `GeofenceReceiver` | `GeofenceManager` (delegate methods) | CoreLocation |
| `AlarmClockReceiver` | *Not needed* | AlarmKit |
| `NotificationReceiver` | Optional `UNNotificationRequest` | UserNotifications |
| `InitializationReceiver` | *Not needed* | iOS auto-recovers |
| `PermissionHelper` | Inline in `GeofenceManager` / `AlarmScheduler` | CoreLocation, AlarmKit |
| `GeoClockApplication` (ACRA) | Xcode Organizer crash reports or Sentry | — |

---

## Known AlarmKit Limitations (v1)

These are worth tracking as Apple iterates on the API:

1. **No app wake on alarm fire** — can't run custom code when alarm rings
2. **Local sounds only** — no streaming, file must be on-device
3. **No swipe-dismiss detection** — stop intent not called on swipe
4. **System-controlled UI** — can customize Live Activity content but not the alarm presentation itself
5. **New framework** — iOS 26 only, no backport possible, limited real-world testing so far

---

## Effort Estimate Comparison

The iOS version is substantially **less code** than the Android version because AlarmKit eliminates the entire alarm ringing subsystem:

| Layer | Android | iOS |
|---|---|---|
| Model + persistence | `GeoAlarm.java` (Lombok + GSON + SharedPreferences) | `GeoAlarm.swift` (SwiftData — simpler) |
| Geofencing | `LocationServiceGoogle` + `GeofenceReceiver` + `InitializationReceiver` + `InitializationService` | `GeofenceManager` (single class) |
| Alarm scheduling | `ActiveAlarmManager` + `AlarmClockReceiver` + `NotificationReceiver` | `AlarmScheduler` (single class) |
| Alarm ringing | `AlarmRingingService` + `AlarmRingingActivity` + 2 notification channels | *Zero code* — AlarmKit |
| UI screens | 3 activities + 1 fragment + 6 XML layouts + adapter | 4 SwiftUI views |
| Permissions | `PermissionHelper` + 14 manifest entries + 4 runtime chains | 3 Info.plist keys + 3 inline requests |
| **Total classes** | **~17 Java classes** | **~10 Swift files** |
