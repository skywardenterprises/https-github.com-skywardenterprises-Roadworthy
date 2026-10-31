import SwiftUI

extension View {
    /// Number entry that avoids the iPad's floating number-pad popover (which
    /// can sit on top of the field being edited). iPad gets the standard
    /// docked keyboard on its numbers page; iPhone keeps the number pad.
    /// Callers must still filter the text, since this keyboard can type letters.
    func numericKeyboard(_ phoneType: UIKeyboardType) -> some View {
        keyboardType(UIDevice.current.userInterfaceIdiom == .pad ? .numbersAndPunctuation : phoneType)
    }

    /// Keyboard handling for forms: tap anywhere outside a text field (or
    /// scroll) to dismiss the keyboard, keeps the focused field clear of the
    /// keyboard, and shows a "Done" button only for iPhone number pads, which
    /// have no Return key.
    func withKeyboardDismiss() -> some View {
        modifier(KeyboardSupport())
    }
}

private struct KeyboardSupport: ViewModifier {
    @State private var showDone = false

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                KeyboardAvoider.recordKeyboardFrame(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                KeyboardAvoider.startTapToDismiss()
                KeyboardAvoider.revealFocusedField()
                showDone = KeyboardAvoider.focusedFieldNeedsDoneButton()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                KeyboardAvoider.stopTapToDismiss()
                showDone = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
                KeyboardAvoider.revealFocusedField()
                showDone = KeyboardAvoider.focusedFieldNeedsDoneButton()
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in
                KeyboardAvoider.revealFocusedField()
                showDone = KeyboardAvoider.focusedFieldNeedsDoneButton()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if showDone {
                        Spacer()
                        Button("Done") { KeyboardAvoider.dismissKeyboard() }
                    }
                }
            }
    }
}

// MARK: - Keeping the focused field visible

extension UIResponder {
    /// Called through `sendAction` with a nil target, which UIKit delivers
    /// to whichever responder is currently first responder.
    @objc fileprivate func rwCaptureFirstResponder() {
        KeyboardAvoider.capturedResponder = self
    }
}

/// Scrolls the form so the field being edited sits clear of the keyboard,
/// the iPad number-pad popover, and the floating "Done" button above the
/// keyboard. Works for any Form or List without per-field setup.
@MainActor
enum KeyboardAvoider {
    fileprivate static weak var capturedResponder: UIResponder?
    private static var keyboardFrame: CGRect = .zero
    private static let tapHandler = KeyboardTapHandler()
    private static weak var tapWindow: UIWindow?

    static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// True for number and decimal pads on iPhone, which have no Return key.
    static func focusedFieldNeedsDoneButton() -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        capturedResponder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.rwCaptureFirstResponder), to: nil, from: nil, for: nil)
        guard let traits = capturedResponder as? UITextInputTraits, let type = traits.keyboardType else { return false }
        return type == .numberPad || type == .decimalPad || type == .phonePad
    }

    /// While the keyboard is up, a tap anywhere outside a text field closes
    /// it. The tap still reaches whatever was tapped (buttons, pickers).
    static func startTapToDismiss() {
        capturedResponder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.rwCaptureFirstResponder), to: nil, from: nil, for: nil)
        guard let window = (capturedResponder as? UIView)?.window, tapWindow !== window else { return }
        stopTapToDismiss()
        window.addGestureRecognizer(tapHandler.recognizer)
        tapWindow = window
    }

    static func stopTapToDismiss() {
        tapWindow?.removeGestureRecognizer(tapHandler.recognizer)
        tapWindow = nil
    }

    /// Extra room kept between the bottom of the field and the top of the
    /// keyboard so the floating Done button doesn't sit on top of it.
    private static let bottomClearance: CGFloat = 72

    static func recordKeyboardFrame(_ note: Notification) {
        keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
    }

    static func revealFocusedField() {
        // The keyboard animates in and the system makes its own scroll
        // adjustment first; wait for that, then correct it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            reveal()
        }
    }

    private static func reveal() {
        capturedResponder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.rwCaptureFirstResponder), to: nil, from: nil, for: nil)
        guard let field = capturedResponder as? UIView, let window = field.window else { return }

        var ancestor = field.superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView else { return }

        let fieldFrame = field.convert(field.bounds, to: window)
        let scrollFrame = scroll.convert(scroll.bounds, to: window)

        var bottomLimit = scrollFrame.maxY - 12
        let keyboardInWindow = window.convert(keyboardFrame, from: nil)
        if keyboardInWindow.height > 0, keyboardInWindow.minY < window.bounds.height {
            bottomLimit = min(bottomLimit, keyboardInWindow.minY)
        }
        bottomLimit -= bottomClearance
        let topLimit = scrollFrame.minY + scroll.adjustedContentInset.top + 12

        var delta: CGFloat = 0
        if fieldFrame.maxY > bottomLimit {
            delta = fieldFrame.maxY - bottomLimit
        } else if fieldFrame.minY < topLimit {
            delta = fieldFrame.minY - topLimit
        }
        guard abs(delta) > 1 else { return }

        let minOffset = -scroll.adjustedContentInset.top
        let maxOffset = max(minOffset, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let target = min(max(scroll.contentOffset.y + delta, minOffset), maxOffset)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: true)
    }
}

@MainActor
private final class KeyboardTapHandler: NSObject, UIGestureRecognizerDelegate {
    lazy var recognizer: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        return tap
    }()

    @objc private func handleTap(_ tap: UITapGestureRecognizer) {
        guard tap.state == .ended, let window = tap.view else { return }
        var view: UIView? = window.hitTest(tap.location(in: window), with: nil)
        while let current = view {
            if current is UITextField || current is UITextView { return }
            view = current.superview
        }
        KeyboardAvoider.dismissKeyboard()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
