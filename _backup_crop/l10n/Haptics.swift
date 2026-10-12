import UIKit

/// Small wrapper around UIKit's haptic feedback generators, used to give a
/// physical "tap" on key actions throughout the app — saving, deleting, and
/// completing something.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func delete() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
