import Foundation
import UserNotifications

/// Handles requesting permission and scheduling/canceling the local
/// notifications tied to recurring maintenance reminders.
enum ReminderNotificationManager {

    /// Ask the person to allow notifications. Safe to call repeatedly —
    /// iOS only shows the system prompt the first time; after that it's a no-op.
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedules (or re-schedules) the notification for a reminder, based on
    /// its current due date and "notify X days before" setting. Does nothing
    /// if notifications are turned off for this reminder, or if it isn't
    /// date-based, or if the calculated fire date is already in the past.
    static func schedule(for reminder: MaintenanceReminder, vehicleName: String) {
        // Always clear out any previously scheduled notification first, so
        // edits (or turning notifications off) don't leave stale ones behind.
        cancel(for: reminder)

        guard reminder.notificationsEnabled,
              let fireDate = reminder.notificationFireDate,
              fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Maintenance Reminder"
        content.sound = .default
        if reminder.notifyDaysBefore > 0 {
            content.body = "\(reminder.title) for \(vehicleName) is due in \(reminder.notifyDaysBefore) day\(reminder.notifyDaysBefore == 1 ? "" : "s")."
        } else {
            content.body = "\(reminder.title) for \(vehicleName) is due today."
        }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.reminderID.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    /// Removes any pending notification for this reminder — used when
    /// editing, marking done (since the due date shifts), or deleting.
    static func cancel(for reminder: MaintenanceReminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [reminder.reminderID.uuidString]
        )
    }
}
