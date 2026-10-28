import UIKit
import Vision

/// Finds a VIN in a photo from the library: a barcode on a door-jamb sticker
/// or the VIN printed on the dashboard, registration or insurance card.
nonisolated enum VINPhotoReader {
    static func readVIN(from data: Data) async -> String? {
        await Task.detached(priority: .userInitiated) {
            read(data)
        }.value
    }

    private static func read(_ data: Data) -> String? {
        // Upright, at most 3000 px on the long edge: sharp enough to read
        // small print, small enough to process quickly.
        guard let image = ImageNormalizer.thumbnail(from: data, maxPixel: 3000),
              let cgImage = image.cgImage else { return nil }

        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [
            .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
            .code128, .dataMatrix, .qr, .pdf417
        ]
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([barcodeRequest, textRequest])

        let barcodePayloads = (barcodeRequest.results ?? []).compactMap { $0.payloadStringValue }
        let textLines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }

        // 1. A barcode whose check digit passes is the best evidence.
        for payload in barcodePayloads {
            if let match = VINScanParser.bestVIN(in: payload), match.checkDigitValid { return match.vin }
        }
        // 2. Printed text whose check digit passes.
        for line in textLines {
            if let match = VINScanParser.bestVIN(in: line), match.checkDigitValid, looksLikeVIN(match.vin) {
                return match.vin
            }
        }
        // 3. Printed text with the letters I, O and Q read as 1, 0 and 0.
        //    Real VINs never contain those letters, so they are misreads.
        for line in textLines {
            let fixed = line.uppercased()
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "Q", with: "0")
                .replacingOccurrences(of: "I", with: "1")
            if let match = VINScanParser.bestVIN(in: fixed), match.checkDigitValid, looksLikeVIN(match.vin) {
                return match.vin
            }
        }
        // 4. Any barcode that holds 17 VIN characters.
        for payload in barcodePayloads {
            if let match = VINScanParser.bestVIN(in: payload) { return match.vin }
        }
        // 5. Any plausible printed VIN. The lookup flags a bad check digit.
        for line in textLines {
            if let match = VINScanParser.bestVIN(in: line), looksLikeVIN(match.vin) { return match.vin }
        }
        return nil
    }

    /// Real VINs hold many digits. Ordinary words that happen to be 17
    /// letters long once spaces are removed don't.
    private static func looksLikeVIN(_ vin: String) -> Bool {
        vin.filter(\.isNumber).count >= 4
    }
}
