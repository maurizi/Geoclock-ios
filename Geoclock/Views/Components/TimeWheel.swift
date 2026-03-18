import SwiftUI

struct TimeWheel: View {
    @Binding var hour: Int
    @Binding var minute: Int

    private var date: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour = components.hour ?? 0
                minute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        DatePicker(
            "Time",
            selection: date,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 150)
    }
}
