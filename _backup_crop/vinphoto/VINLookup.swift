import SwiftUI

// MARK: - Result

/// What the NHTSA VIN decoder returned, as plain values so it can be built off
/// the main actor. Mapped to the app's own types by the view that uses it.
nonisolated struct VINDecodeResult: Sendable {
    enum Kind: Sendable { case car, truck, motorcycle, rv }

    var year: Int?
    var make = ""
    var model = ""
    var trim = ""
    var bodyStyle = ""
    var cylinders: Int?
    var fuelType = ""
    var driveType = ""
    var transmission = ""
    var engineSize: Double?
    /// "L", "cc" or "ci" (matches `EngineSizeUnit.rawValue`).
    var engineUnitSymbol = "L"
    var kind: Kind?
    /// NHTSA flagged the 9th-character check digit. The VIN may have a typo.
    var checkDigitMismatch = false
}

nonisolated enum VINDecodeError: Error {
    case offline
    case notFound
    case service

    var message: String {
        switch self {
        case .offline:
            return L("Couldn't reach the VIN database. Check your internet connection, or tap Skip to keep the VIN and look it up later.")
        case .notFound:
            return L("No vehicle was found for that VIN. Check the characters and try again.")
        case .service:
            return L("The VIN database didn't respond correctly. Try again in a moment.")
        }
    }
}

// MARK: - Decoder

/// Free U.S. government VIN decoder (NHTSA vPIC). No account or key needed.
nonisolated enum VINDecoder {
    /// VINs never contain I, O or Q.
    private static let allowed = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")

    static func normalized(_ raw: String) -> String {
        String(raw.uppercased().filter { allowed.contains($0) }.prefix(17))
    }

    static func decode(_ rawVIN: String) async throws -> VINDecodeResult {
        let vin = normalized(rawVIN)
        guard vin.count == 17,
              let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/\(vin)?format=json")
        else { throw VINDecodeError.notFound }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            throw VINDecodeError.offline
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["Results"] as? [[String: Any]],
              let row = results.first
        else { throw VINDecodeError.service }

        func text(_ key: String) -> String {
            (row[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result = VINDecodeResult()
        let make = text("Make")
        result.make = make.count <= 3 ? make : make.capitalized
        result.model = text("Model")
        guard !result.make.isEmpty || !result.model.isEmpty else { throw VINDecodeError.notFound }

        result.year = Int(text("ModelYear"))
        result.trim = text("Trim").isEmpty ? text("Series") : text("Trim")
        result.bodyStyle = text("BodyClass")
        result.fuelType = text("FuelTypePrimary")
        result.driveType = text("DriveType")

        let style = text("TransmissionStyle")
        let speeds = text("TransmissionSpeeds")
        result.transmission = (speeds.isEmpty || style.isEmpty) ? style : "\(speeds)-speed \(style)"

        if let value = Double(text("EngineCylinders")), value > 0 { result.cylinders = Int(value) }

        if let liters = Double(text("DisplacementL")), liters > 0 {
            result.engineSize = (liters * 100).rounded() / 100
            result.engineUnitSymbol = "L"
        } else if let cc = Double(text("DisplacementCC")), cc > 0 {
            result.engineSize = cc.rounded()
            result.engineUnitSymbol = "cc"
        } else if let ci = Double(text("DisplacementCI")), ci > 0 {
            result.engineSize = (ci * 10).rounded() / 10
            result.engineUnitSymbol = "ci"
        }

        let vehicleType = text("VehicleType").uppercased()
        let body = result.bodyStyle.uppercased()
        if vehicleType.contains("MOTORCYCLE") {
            result.kind = .motorcycle
        } else if body.contains("PICKUP") {
            result.kind = .truck
        } else if body.contains("MOTORHOME") || body.contains("RECREATIONAL") {
            result.kind = .rv
        } else if vehicleType.contains("PASSENGER CAR") || vehicleType.contains("MULTIPURPOSE") {
            result.kind = .car
        }

        let codes = text("ErrorCode").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        result.checkDigitMismatch = codes.contains("1")
        return result
    }
}

// MARK: - Prompt sheet

/// Asks whether the person knows the VIN and, if so, looks it up.
struct VINPromptView: View {
    @Environment(\.dismiss) private var dismiss

    let skipTitle: LocalizedStringKey
    let onSkip: ((String) -> Void)?
    let onDecoded: (String, VINDecodeResult) -> Void

    @State private var vin: String
    @State private var isLooking = false
    @State private var errorMessage: String?
    @State private var showingScanner = false
    @State private var showingHelp = false
    @FocusState private var focused: Bool

    /// `onSkip` receives whatever is in the VIN field when the person skips,
    /// so a scanned VIN isn't lost when the lookup can't run (for example
    /// with no internet).
    init(initialVIN: String = "", skipTitle: LocalizedStringKey, onSkip: ((String) -> Void)? = nil, onDecoded: @escaping (String, VINDecodeResult) -> Void) {
        _vin = State(initialValue: VINDecoder.normalized(initialVIN))
        self.skipTitle = skipTitle
        self.onSkip = onSkip
        self.onDecoded = onDecoded
    }

    private var canLookUp: Bool { vin.count == 17 && !isLooking }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 54))
                        .foregroundStyle(.tint)
                        .padding(.top, 8)

                    Text("Do you know the VIN?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Scan or enter the 17-character VIN and Roadworthy will fill in the year, make, model, engine and other details. You can also skip this and enter everything yourself.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wifi")
                            .font(.headline)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Internet connection required")
                                .font(.subheadline.weight(.semibold))
                            Text("Looking up a VIN sends it to the U.S. NHTSA public vehicle database. Scanning works offline: with no connection, scan the VIN now and look it up later.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement(children: .combine)

                    Group {
                        VStack(spacing: 6) {
                            Button {
                                focused = false
                                showingScanner = true
                            } label: {
                                Label("Scan VIN Barcode", systemImage: "barcode.viewfinder")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLooking)

                            Text("Fastest way: scan the barcode on the driver's door jamb sticker.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                showingHelp = true
                            } label: {
                                Label("How does scanning work?", systemImage: "questionmark.circle")
                                    .font(.footnote)
                            }
                        }

                        HStack {
                            Rectangle().fill(.quaternary).frame(height: 1)
                            Text("or type it in")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Rectangle().fill(.quaternary).frame(height: 1)
                        }
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("17-character VIN", text: $vin)
                            .font(.system(.title3, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.search)
                            .onSubmit { if canLookUp { lookUp() } }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onChange(of: vin) { _, newValue in
                                let cleaned = VINDecoder.normalized(newValue)
                                if cleaned != newValue { vin = cleaned }
                                errorMessage = nil
                            }
                        Text("\(vin.count)/17")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button { lookUp() } label: { lookUpLabel }
                        .buttonStyle(.bordered)
                        .disabled(!canLookUp)

                    Button {
                        onSkip?(vin)
                        dismiss()
                    } label: {
                        Text(skipTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .disabled(isLooking)

                    VStack(spacing: 8) {
                        Text("You can find the VIN on the driver's side of the dashboard near the windshield, on the driver's door jamb sticker, or on your registration and insurance card.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .sheet(isPresented: $showingHelp) { VINScanHelpView() }
            .fullScreenCover(isPresented: $showingScanner) {
                VINScannerView { scanned in
                    vin = scanned
                    lookUp()
                }
            }
        }
        .interactiveDismissDisabled(isLooking)
    }

    private var lookUpLabel: some View {
        HStack {
            if isLooking { ProgressView() }
            Text(LocalizedStringKey(isLooking ? "Looking up…" : "Look Up VIN"))
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func lookUp() {
        guard canLookUp else { return }
        isLooking = true
        errorMessage = nil
        let requested = vin
        Task {
            do {
                let result = try await VINDecoder.decode(requested)
                isLooking = false
                onDecoded(requested, result)
            } catch let error as VINDecodeError {
                isLooking = false
                errorMessage = error.message
            } catch {
                isLooking = false
            }
        }
    }
}
