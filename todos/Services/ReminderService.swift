import EventKit
import Foundation

/// Connects tasks to Apple's Reminders app. A task with a reminder becomes a real reminder there,
/// with a due time and an alert, so iOS delivers the notification and this app needs none of its own.
/// The link is one way: changes made in Reminders are not read back.
@MainActor
final class ReminderService {
    static let shared = ReminderService()
    private let eventStore = EKEventStore()

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .denied || status == .restricted
    }

    /// Asks for access to Reminders the first time, and reports whether it is granted.
    func requestAccess() async -> Bool {
        if isAuthorized { return true }
        if isDenied { return false }
        return (try? await eventStore.requestFullAccessToReminders()) ?? false
    }

    /// Creates the reminder, or updates it if it still exists. Returns its identifier, or nil if it could not be saved.
    func upsert(id: String?, title: String, note: String?, due: Date) -> String? {
        guard isAuthorized else { return nil }
        let reminder: EKReminder
        if let id, let existing = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }
        guard reminder.calendar != nil else { return nil }
        reminder.title = title
        reminder.notes = note
        reminder.isCompleted = false
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        reminder.addAlarm(EKAlarm(absoluteDate: due))
        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    /// Ticks the reminder off, or reopens it, to match the task.
    func setCompleted(id: String?, _ completed: Bool) {
        guard isAuthorized, let id, let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder,
              reminder.isCompleted != completed else { return }
        reminder.isCompleted = completed
        try? eventStore.save(reminder, commit: true)
    }

    func remove(id: String?) {
        guard isAuthorized, let id, let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try? eventStore.remove(reminder, commit: true)
    }

    #if DEBUG
    /// What the Reminders app currently holds for an identifier, for the debug self-test.
    func snapshot(id: String) -> (title: String, due: Date?, alarm: Date?, completed: Bool)? {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
        return (reminder.title, reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                reminder.alarms?.first?.absoluteDate, reminder.isCompleted)
    }
    #endif
}
