import CoreLocation
import SwiftUI

struct AlarmCardView: View {
    @Bindable var alarm: GeoAlarm
    var userLocation: CLLocationCoordinate2D?
    var onToggle: (Bool) -> Void = { _ in }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                timeRow
                detailRow
            }

            Spacer()

            Toggle("", isOn: $alarm.enabled)
                .labelsHidden()
                .onChange(of: alarm.enabled) { _, newValue in
                    onToggle(newValue)
                }
        }
        .padding(.vertical, 4)
    }

    private var timeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let hour = alarm.hour, let minute = alarm.minute {
                Text(formattedTime(hour: hour, minute: minute))
                    .font(.title2)
                    .fontWeight(.medium)
                    .monospacedDigit()
            } else {
                Text("\u{2014}")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text(DaysSummary.summary(for: alarm.days))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detailRow: some View {
        HStack(spacing: 4) {
            if let place = alarm.place {
                Text(place)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let distance = distanceText {
                Text(" \u{00B7} \(distance)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(" \u{00B7} \(GeoAlarm.radiusSizeLabel(for: alarm.radius))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var distanceText: String? {
        guard let userLocation else { return nil }
        let edgeDistance = DistanceFormatter.distanceToEdge(from: userLocation, to: alarm)
        if edgeDistance <= 0 { return nil }
        return DistanceFormatter.formatEdgeDistance(meters: edgeDistance)
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: .current)
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? .now
        return formatter.string(from: date)
    }
}
