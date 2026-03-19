import SwiftUI

struct DayPicker: View {
    @Binding var selectedDays: Set<Weekday>

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    dayButton(day)
                }
            }

        }
    }

    private func dayButton(_ day: Weekday) -> some View {
        let isSelected = selectedDays.contains(day)
        return Button {
            if isSelected {
                selectedDays.remove(day)
            } else {
                selectedDays.insert(day)
            }
        } label: {
            Text(day.shortLabel)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
