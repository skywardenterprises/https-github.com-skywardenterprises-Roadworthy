import SwiftUI

/// Small colored pill showing a reminder's status — red Overdue, orange
/// Upcoming, green On Track. Used wherever reminders are displayed.
struct ReminderStatusBadge: View {
    let status: ReminderStatus

    private var color: Color {
        switch status {
        case .overdue: return .red
        case .upcoming: return .orange
        case .onTrack: return .green
        }
    }

    var body: some View {
        Text(status.rawValue)
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
        if isDueSoon(currentMileage: currentMileage) { return .orange }
        return .secondary
    }

    /// Color for the next-due date: red once past due, otherwise secondary.
    func dateTint(currentMileage: Int) -> Color {
        isDue(currentMileage: currentMileage) ? .red : .secondary
    }
}
