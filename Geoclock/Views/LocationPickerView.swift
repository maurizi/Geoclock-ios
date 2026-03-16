import SwiftUI
import Combine
import MapKit

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var geofenceManager: GeofenceManager

    @Binding var latitude: Double
    @Binding var longitude: Double
    @Binding var radius: Int
    @Binding var place: String

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchCompleterResults: [MKLocalSearchCompletion] = []
    @State private var showingSearchResults = false
    @StateObject private var searchCompleter = SearchCompleter()

    private var pinCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mapView
                pinOverlay
                radiusControls
            }
            .searchable(text: $searchText, prompt: "Search for a place")
            .searchSuggestions {
                ForEach(searchCompleter.results, id: \.self) { completion in
                    Button {
                        performSearch(for: completion)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(completion.title)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchCompleter.queryFragment = newValue
            }
            .navigationTitle("Pick location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        centerOnUser()
                    } label: {
                        Image(systemName: "location.fill")
                    }
                }
            }
            .onAppear {
                if latitude == 0 && longitude == 0 {
                    if let loc = geofenceManager.userLocation {
                        latitude = loc.latitude
                        longitude = loc.longitude
                        cameraPosition = .region(MKCoordinateRegion(
                            center: loc,
                            latitudinalMeters: Double(radius) * 4,
                            longitudinalMeters: Double(radius) * 4
                        ))
                    } else {
                        cameraPosition = .userLocation(fallback: .automatic)
                    }
                } else {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: pinCoordinate,
                        latitudinalMeters: Double(radius) * 4,
                        longitudinalMeters: Double(radius) * 4
                    ))
                }
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                MapCircle(center: pinCoordinate, radius: CLLocationDistance(radius))
                    .foregroundStyle(.blue.opacity(0.15))
                    .stroke(.blue.opacity(0.4), lineWidth: 1)

                Annotation("", coordinate: pinCoordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    latitude = coordinate.latitude
                    longitude = coordinate.longitude
                    reverseGeocodePin()
                }
            }
        }
    }

    private var pinOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if !place.isEmpty {
                    Text(place)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            }
            .padding(.bottom, 100)
        }
    }

    // MARK: - Radius

    private var radiusControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 4) {
                Text(GeoAlarm.radiusSizeLabel(for: radius))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Small")
                        .font(.caption2)
                    Slider(
                        value: Binding(
                            get: { Double(radius) },
                            set: { radius = Int($0) }
                        ),
                        in: 50...500,
                        step: 50
                    )
                    Text("Large")
                        .font(.caption2)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }

    // MARK: - Search

    private func performSearch(for completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first,
                  let location = item.placemark.location else { return }
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            place = item.name ?? completion.title
            cameraPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: Double(radius) * 4,
                longitudinalMeters: Double(radius) * 4
            ))
            searchText = ""
            dismissSearch()
        }
    }

    private func centerOnUser() {
        if let loc = geofenceManager.userLocation {
            latitude = loc.latitude
            longitude = loc.longitude
            cameraPosition = .region(MKCoordinateRegion(
                center: loc,
                latitudinalMeters: Double(radius) * 4,
                longitudinalMeters: Double(radius) * 4
            ))
            reverseGeocodePin()
        }
    }

    private func reverseGeocodePin() {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            if let placemark = placemarks?.first {
                place = AddressFormatter.shortAddress(from: placemark) ?? ""
            }
        }
    }
}

// MARK: - Search Completer

class SearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var queryFragment: String = "" {
        didSet { completer.queryFragment = queryFragment }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
