import CoreLocation
import MapKit

enum AddressFormatter {
    static func shortAddress(from item: MKMapItem) -> String? {
        if let short = item.address?.shortAddress, !short.isEmpty {
            return short
        }
        return item.name
    }

    static func shortAddress(from placemark: CLPlacemark) -> String? {
        // "123 Main St" style
        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                return "\(number) \(street)"
            }
            return street
        }
        // City fallback
        if let locality = placemark.locality {
            return locality
        }
        // Generic name fallback
        return placemark.name
    }
}
