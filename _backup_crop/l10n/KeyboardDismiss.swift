import SwiftUI

extension View {
    /// Adds a "Done" button above the keyboard (works for number pads too,
    /// which don't have a built-in return/dismiss key), and lets the user
    /// swipe down on the form to dismiss the keyboard as well.
    func withKeyboardDismiss() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
    }
}
