import SwiftUI

/// Small colored pill showing a reminder's status — red Overdue, orange
/// Upcoming, green On Track. Used wherever reminders are displayed.
struct ReminderStatusBadge: View {
    let status: ReminderStatus

    private var color: Color {
        switch status {
        // Darker than the system colors so the white label is readable
        // (4.5:1 or better) in both light and dark appearance.
        case .overdue: return Color(red: 0.78, green: 0.16, blue: 0.16)
        case .upcoming: return Color(red: 0.71, green: 0.37, blue: 0.02)
        case .onTrack: return Color(red: 0.18, green: 0.49, blue: 0.20)
        }
    }

    var body: some View {
        Text(LocalizedStringKey(status.rawValue))
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}

extension MaintenanceReminder {
    /// Color for the next-due mileage: red once past due, orange once due
    /// soon (see `isDueSoon` in Models.swift for the window), otherwise the
    /// normal secondary color. Shared by the reminder list and Overview.
    func mileageTint(currentMileage: Int) -> Color {
        if isDue(currentMileage: currentMileage) { return .red }
        if isDueSoon(currentMileage: currentMileage) { return RWColor.amber }
        return .secondary
    }

    /// Color for the next-due date: red once past due, otherwise secondary.
    func dateTint(currentMileage: Int) -> Color {
        isDue(currentMileage: currentMileage) ? .red : .secondary
    }
}
