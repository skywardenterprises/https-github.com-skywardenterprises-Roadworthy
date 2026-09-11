import SwiftUI

/// A numeric input field that behaves like a typical point-of-sale or
/// banking app: type digits only, and the decimal point is placed
/// automatically from the right — no need to type "." yourself. Typing
/// "5", "0", "0" with 2 decimal places produces 5.00, not 500.
///
/// Used for dollar amounts (with a "$" prefix) and for quantities like
/// fuel gallons (no prefix, typically 3 decimal places to match what a gas
/// pump shows).
///
/// The bound text is still a plain "45.99"-style decimal string, exactly
/// like a normal TextField would hold — this is a drop-in replacement
/// anywhere a decimal field already exists. Double(text) on save works
/// exactly the same as before, and anything that writes into the bound
/// text externally (like an auto-calculated total) is picked up and
/// reformatted correctly too.
struct AutoDecimalField: View {
    let title: String
    @Binding var text: String
    var decimalPlaces: Int = 2
    /// A leading symbol like "$" for currency. Nil for a plain quantity
    /// field like gallons.
    var prefix: String? = "$"

    @State private var rawDigits: String = ""

    var body: some View {
        HStack(spacing: 2) {
            if let prefix {
                Text(prefix)
                    .foregroundStyle(rawDigits.isEmpty ? .secondary : .primary)
            }
            TextField(title, text: Binding(
                get: { formattedDisplay },
                set: { newValue in
                    rawDigits = String(newValue.filter(\.isNumber).prefix(9))
                    text = plainDecimalString
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
        }
        .onAppear { syncFromExternalText() }
        .onChange(of: text) { _, _ in syncFromExternalText() }
    }

    /// Picks up a value that changed from outside this field — editing an
    /// existing record on first load, or an auto-calculated total, for
    /// example — without disturbing what's here if it already matches.
    private func syncFromExternalText() {
        guard let externalValue = Double(text), externalValue != 0 else {
            if Double(text) == nil { rawDigits = "" }
            return
        }
        let divisor = pow(10.0, Double(decimalPlaces))
        let recomputedDigits = String(Int((externalValue * divisor).rounded()))
        if recomputedDigits != rawDigits {
            rawDigits = recomputedDigits
        }
    }

    private var numericValue: Double {
        guard let cents = Int(rawDigits) else { return 0 }
        let divisor = pow(10.0, Double(decimalPlaces))
        return Double(cents) / divisor
    }

    private var formattedDisplay: String {
        rawDigits.isEmpty ? "" : numericValue.formatted(.number.precision(.fractionLength(decimalPlaces)))
    }

    private var plainDecimalString: String {
        rawDigits.isEmpty ? "" : String(format: "%.\(decimalPlaces)f", numericValue)
    }
}
