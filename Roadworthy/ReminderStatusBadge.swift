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
