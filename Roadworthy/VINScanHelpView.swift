import SwiftUI

/// Looping demo of scanning the VIN barcode on a door-jamb sticker, shown from
/// the (?) button. Continue returns to the scanner.
struct VINScanHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cycle: Double = 7

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    animation
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "Open the driver's door and find the sticker on the jamb.")
                        step(2, "Hold the phone about a hand's width from the barcode.")
                        step(3, "The VIN fills in and Roadworthy looks up the vehicle.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .navigationTitle("How to Scan the VIN")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
                .background(.bar)
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var animation: some View {
        if reduceMotion {
            scaled(progress: 0.8)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                scaled(progress: t.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle)
            }
        }
    }

    /// The scene is drawn on a fixed 640 x 400 canvas and scaled to fit.
    private func scaled(progress: Double) -> some View {
        GeometryReader { geo in
            let scale = geo.size.width / 640
            scene(progress)
                .frame(width: 640, height: 400, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: 400 * scale, alignment: .topLeading)
        }
        .aspectRatio(640.0 / 400.0, contentMode: .fit)
    }

    // MARK: - Timeline helpers

    private func ramp(_ p: Double, _ a: Double, _ b: Double) -> Double {
        min(1, max(0, (p - a) / (b - a)))
    }

    private func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    // MARK: - Scene

    private func scene(_ p: Double) -> some View {
        let appear = ease(ramp(p, 0, 0.12))
        let leave = ramp(p, 0.92, 1)
        let phoneOpacity = appear * (1 - leave)
        let locked = p >= 0.52 && p < 0.92
        let sweep = ramp(p, 0.15, 0.52)
        let scanY = 84 * (1 - cos(2 * Double.pi * sweep)) / 2
        let scanOpacity = (p > 0.15 && p < 0.52) ? 1.0 : 0.0
        let flash = p >= 0.52 ? 0.35 * (1 - ramp(p, 0.54, 0.62)) : 0
        let resultIn = ease(ramp(p, 0.56, 0.64))
        let resultOut = ease(ramp(p, 0.90, 0.96))
        let cardDY = 130 * ((1 - resultIn) + resultOut)
        let tickT = ramp(p, 0.62, 0.72)
        let tickScale = p < 0.62 ? 0 : (tickT < 0.6 ? tickT / 0.6 * 1.25 : 1.25 - (tickT - 0.6) / 0.4 * 0.25)
        let beams = 0.55 * phoneOpacity
        let green = Color(red: 0.12, green: 0.64, blue: 0.39)

        return ZStack(alignment: .topLeading) {
            Color(.secondarySystemBackground)
            Color(.systemGray4).frame(width: 34, height: 400)
            Color(white: 0.23).frame(width: 12, height: 400).offset(x: 34)
            Color(.systemGray5).frame(width: 594, height: 400).offset(x: 46)

            sticker(highlight: locked, green: green)
                .offset(x: 66, y: 80)

            Path { path in
                path.move(to: CGPoint(x: 342, y: 174)); path.addLine(to: CGPoint(x: 420, y: 124))
                path.move(to: CGPoint(x: 342, y: 232)); path.addLine(to: CGPoint(x: 420, y: 214))
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            .opacity(beams)

            phone(scanY: scanY, scanOpacity: scanOpacity, locked: locked, flash: flash,
                  cardDY: cardDY, tickScale: tickScale, green: green)
                .rotationEffect(.degrees(-3))
                .offset(x: 404 + 70 * (1 - appear), y: 30 + 26 * (1 - appear))
                .opacity(phoneOpacity)
        }
        .frame(width: 640, height: 400, alignment: .topLeading)
        .clipped()
    }

    private func sticker(highlight: Bool, green: Color) -> some View {
        let ink = Color(red: 0.13, green: 0.15, blue: 0.16)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.95, green: 0.95, blue: 0.93))
            RoundedRectangle(cornerRadius: 6).stroke(highlight ? green : Color.black.opacity(0.18), lineWidth: highlight ? 3 : 1)
            RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.75)).frame(width: 120, height: 8).offset(x: 20, y: 18)
            RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.2)).frame(width: 250, height: 5).offset(x: 20, y: 34)
            RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.2)).frame(width: 230, height: 5).offset(x: 20, y: 45)
            RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.2)).frame(width: 180, height: 5).offset(x: 20, y: 56)
            Text("VIN").font(.system(size: 9, design: .monospaced)).foregroundStyle(ink.opacity(0.6)).offset(x: 20, y: 74)
            BarcodeBars(seed: 7, unit: 260 / 112).fill(ink).frame(width: 260, height: 62).offset(x: 20, y: 96)
            Text("1HGCM82633A004352")
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(ink)
                .frame(width: 260)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .offset(x: 20, y: 172)
        }
        .frame(width: 300, height: 230)
    }

    private func phone(scanY: Double, scanOpacity: Double, locked: Bool, flash: Double,
                       cardDY: Double, tickScale: Double, green: Color) -> some View {
        let ink = Color(red: 0.13, green: 0.15, blue: 0.16)
        let screen = ZStack(alignment: .topLeading) {
            Color(red: 0.04, green: 0.05, blue: 0.06)
            Group {
            Text("Cancel").font(.system(size: 10.5)).foregroundStyle(Color(red: 0.42, green: 0.64, blue: 1)).offset(x: 14, y: 20)
            Text("Scan VIN").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 180).offset(y: 20)
            Color(red: 0.09, green: 0.10, blue: 0.11).frame(width: 180, height: 228).offset(y: 38)

            RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.95, green: 0.95, blue: 0.93))
                .frame(width: 156, height: 116).offset(x: 12, y: 84)
            BarcodeBars(seed: 7, unit: 132 / 84).fill(ink).frame(width: 132, height: 58).offset(x: 24, y: 98)
            Text("1HGCM82633A004352")
                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(ink)
                .frame(width: 132).minimumScaleFactor(0.5).lineLimit(1).offset(x: 24, y: 172)
            }

            Group {
            RoundedRectangle(cornerRadius: 6).fill(green.opacity(flash))
                .frame(width: 156, height: 116).offset(x: 12, y: 84)

            RoundedRectangle(cornerRadius: 1).fill(Color(red: 1, green: 0.3, blue: 0.24))
                .frame(width: 140, height: 2.5).offset(x: 20, y: 98 + scanY).opacity(scanOpacity)

            CornerBrackets()
                .stroke(locked ? green : Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 140, height: 106).offset(x: 20, y: 92)

            Color(red: 0.04, green: 0.05, blue: 0.06).frame(width: 180, height: 54).offset(y: 266)
            Text("Point at the barcode").font(.system(size: 10)).foregroundStyle(Color(white: 0.75))
                .frame(width: 180).offset(y: 290)

            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(green).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .scaleEffect(tickScale)
                    }
                    Text("VIN found").font(.system(size: 12.5, weight: .bold))
                }
                Text("1HGCM82633A004352").font(.system(size: 9.5, design: .monospaced))
                Text("Looking up vehicle…").font(.system(size: 9)).foregroundStyle(Color(white: 0.45))
            }
            .foregroundStyle(Color(white: 0.1))
            .padding(12)
            .frame(width: 164, height: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            .offset(x: 8, y: 204 + cardDY)
        }
        .frame(width: 180, height: 320, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 22))

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 32).fill(Color(white: 0.07))
            RoundedRectangle(cornerRadius: 31).stroke(Color(white: 0.25), lineWidth: 1.5).padding(1)
            screen.offset(x: 10, y: 10)
            Capsule().fill(.black).frame(width: 56, height: 14).offset(x: 72, y: 16)
        }
        .frame(width: 200, height: 340)
    }
}

// MARK: - Shapes

/// Vertical bars of varying width, repeatable from a seed so both barcodes match.
private struct BarcodeBars: Shape {
    let seed: UInt64
    let unit: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var state = seed
        func random() -> Double {
            state = (state &* 1664525 &+ 1013904223) % 4294967296
            return Double(state) / 4294967296
        }
        var x: CGFloat = 0
        while x < rect.width - unit {
            var barWidth = unit * CGFloat(1 + Int(random() * 3))
            if x + barWidth > rect.width { barWidth = rect.width - x }
            path.addRect(CGRect(x: rect.minX + x, y: rect.minY, width: barWidth, height: rect.height))
            x += barWidth + unit * CGFloat(1 + Int(random() * 2))
        }
        return path
    }
}

/// Four corner marks, like a camera focus frame.
private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 18
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}
