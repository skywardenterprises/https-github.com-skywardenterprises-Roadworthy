import SwiftUI
import VisionKit

// MARK: - Parsing

/// Pulls a VIN out of whatever the camera read (a door-jamb barcode payload or
/// a line of printed text).
nonisolated enum VINScanParser {
    private static let allowed = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
    private static let values: [Character: Int] = [
        "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
        "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
        "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9
    ]
    private static let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]

    /// Every 17-character run of VIN-legal characters in the text.
    static func candidates(in raw: String) -> [String] {
        let cleaned = Array(raw.uppercased().filter { !$0.isWhitespace && $0 != "-" })
        guard cleaned.count >= 17 else { return [] }
        var found: [String] = []
        for start in 0...(cleaned.count - 17) {
            let window = cleaned[start..<(start + 17)]
            if window.allSatisfy({ allowed.contains($0) }) {
                let vin = String(window)
                if !found.contains(vin) { found.append(vin) }
            }
        }
        return found
    }

    /// The 9th character of North American VINs is a check digit.
    static func hasValidCheckDigit(_ vin: String) -> Bool {
        let chars = Array(vin)
        guard chars.count == 17 else { return false }
        var sum = 0
        for (index, char) in chars.enumerated() {
            let value: Int
            if let digit = char.wholeNumberValue { value = digit } else if let mapped = values[char] { value = mapped } else { return false }
            sum += value * weights[index]
        }
        let remainder = sum % 11
        return chars[8] == (remainder == 10 ? "X" : Character(String(remainder)))
    }

    /// Best candidate in the text, preferring one whose check digit passes.
    static func bestVIN(in raw: String) -> (vin: String, checkDigitValid: Bool)? {
        let all = candidates(in: raw)
        if let valid = all.first(where: hasValidCheckDigit) { return (valid, true) }
        if let first = all.first { return (first, false) }
        return nil
    }
}

// MARK: - Scanner

/// Full-screen camera that reads a VIN barcode (or the printed VIN) and hands
/// back the 17 characters.
struct VINScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onFound: (String) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isAvailable {
                    ZStack(alignment: .bottom) {
                        VINScannerRepresentable { vin in
                            Haptics.success()
                            onFound(vin)
                            dismiss()
                        }
                        .ignoresSafeArea()

                        Text("Point the camera at the barcode on the driver's door jamb, or at the VIN on the dashboard. It fills in automatically.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Scanning isn't available right now. Check camera access in Settings, or type the VIN instead.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                }
            }
            .navigationTitle("Scan VIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct VINScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.code39, .code128, .dataMatrix, .qr, .pdf417]),
                .text()
            ],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var finished = false
        /// How many frames in a row a printed (not barcode) VIN was read the
        /// same way. Barcodes are exact; printed text can be misread.
        private var textSightings: [String: Int] = [:]

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(updatedItems)
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !finished else { return }
            for item in items {
                switch item {
                case .barcode(let barcode):
                    if let payload = barcode.payloadStringValue, let match = VINScanParser.bestVIN(in: payload) {
                        finish(match.vin)
                        return
                    }
                case .text(let text):
                    guard let match = VINScanParser.bestVIN(in: text.transcript) else { continue }
                    textSightings[match.vin, default: 0] += 1
                    // A passing check digit is strong evidence; otherwise
                    // require the same reading several times in a row.
                    if (match.checkDigitValid && textSightings[match.vin, default: 0] >= 2)
                        || textSightings[match.vin, default: 0] >= 6 {
                        finish(match.vin)
                        return
                    }
                @unknown default:
                    break
                }
            }
        }

        private func finish(_ vin: String) {
            finished = true
            onFound(vin)
        }
    }
}
