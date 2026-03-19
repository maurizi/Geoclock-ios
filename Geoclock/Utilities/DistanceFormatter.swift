import CoreLocation
import Foundation

struct DistanceFormatter {
    static func formatEdgeDistance(meters: Double) -> String {
        let useImperial = Locale.current.measurementSystem == .us || Locale.current.measurementSystem == .uk

        if useImperial {
            let feet = meters * 3.28084
            if feet < 5280 {
                return String(format: "%dft away", Int(feet))
            } else {
                return String(format: "%.1fmi away", feet / 5280)
            }
        }

        if meters < 1000 {
            return String(format: "%dm away", Int(meters))
        } else {
            return String(format: "%.1fkm away", meters / 1000)
        }
    }

    /// Distance from the user's location to the edge of the geofence (negative if inside)
    static func distanceToEdge(from location: CLLocationCoordinate2D, to alarm: GeoAlarm) -> Double {
        let alarmLocation = CLLocation(latitude: alarm.latitude, longitude: alarm.longitude)
        let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let centerDistance = userLocation.distance(from: alarmLocation)
        return centerDistance - Double(alarm.radius)
    }
}
