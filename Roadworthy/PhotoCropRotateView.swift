import SwiftUI
import UIKit

/// Lets the person rotate and crop a photo before it is attached to a
/// receipt, document, insurance card or vehicle. Every photo path in the app
/// (camera and library) goes through this screen, so a skewed or sideways
/// photo of a receipt or title can be fixed before it is saved.
///
/// The input is a "working" JPEG (see `ImageNormalizer.workingData`): upright
/// pixels, long edge capped at 3,000 px so cropping keeps a sharp result. The
/// output is a normal app photo (long edge 1,600 px) made from the cropped area.
struct PhotoCropRotateView: View {
    /// "Cancel" for library photos, "Retake" for camera photos.
    var cancelTitle: LocalizedStringKey = "Cancel"
    var onDone: (Data) -> Void
    var onCancel: () -> Void

    @State private var working: UIImage
    /// The crop area as fractions (0 to 1) of the current image.
    @State private var crop = PhotoCropRotateView.fullImage
    @State private var dragStartCrop: CGRect?

    private static let fullImage = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// The crop can't be dragged smaller than this fraction of the image.
    private let minFraction: CGFloat = 0.08
    private let handleSize: CGFloat = 44

    init(
        workingData: Data,
        cancelTitle: LocalizedStringKey = "Cancel",
        onDone: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _working = State(initialValue: UIImage(data: workingData) ?? UIImage())
        self.cancelTitle = cancelTitle
        self.onDone = onDone
        self.onCancel = onCancel
    }

    private enum Corner: CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight
        var id: Self { self }

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }

        var accessibilityName: LocalizedStringKey {
            switch self {
            case .topLeft: return "Top left crop handle"
            case .topRight: return "Top right crop handle"
            case .bottomLeft: return "Bottom left crop handle"
            case .bottomRight: return "Bottom right crop handle"
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let fitted = fittedRect(for: working.size, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: working)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                        .accessibilityHidden(true)
                    cropOverlay(fitted: fitted)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .background(Color.black)
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .disabled(working.cgImage == nil)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { rotate(clockwise: false) } label: {
                        Label("Rotate Left", systemImage: "rotate.left")
                            .labelStyle(.iconOnly)
                    }
                    Spacer()
                    Button("Reset Crop") { crop = Self.fullImage }
                        .disabled(crop == Self.fullImage)
                    Spacer()
                    Button { rotate(clockwise: true) } label: {
                        Label("Rotate Right", systemImage: "rotate.right")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Crop overlay

    private func cropOverlay(fitted: CGRect) -> some View {
        let r = CGRect(
            x: fitted.minX + crop.minX * fitted.width,
            y: fitted.minY + crop.minY * fitted.height,
            width: crop.width * fitted.width,
            height: crop.height * fitted.height
        )
        return ZStack(alignment: .topLeading) {
            // Dims everything outside the crop area.
            Path { path in
                path.addRect(fitted)
                path.addRect(r)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // Thirds grid and border.
            Path { path in
                for i in 1...2 {
                    let x = r.minX + r.width * CGFloat(i) / 3
                    let y = r.minY + r.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: r.minY)); path.addLine(to: CGPoint(x: x, y: r.maxY))
                    path.move(to: CGPoint(x: r.minX, y: y)); path.addLine(to: CGPoint(x: r.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)

            // Drag inside the box to move it.
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .gesture(moveGesture(fitted: fitted))
                .accessibilityHidden(true)

            ForEach(Corner.allCases) { corner in
                let p = corner.point(in: r)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .frame(width: handleSize, height: handleSize)
                    .contentShape(Rectangle())
                    .offset(x: p.x - handleSize / 2, y: p.y - handleSize / 2)
                    .gesture(cornerGesture(corner, fitted: fitted))
                    .accessibilityLabel(corner.accessibilityName)
            }
        }
    }

    private func moveGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard fitted.width > 0, fitted.height > 0 else { return }
                let start = dragStartCrop ?? crop
                dragStartCrop = start
                let x = min(max(0, start.minX + value.translation.width / fitted.width), 1 - start.width)
                let y = min(max(0, start.minY + value.translation.height / fitted.height), 1 - start.height)
                crop = CGRect(x: x, y: y, width: start.width, height: start.height)
            }
            .onEnded { _ in dragStartCrop = nil }
    }

    private func cornerGesture(_ corner: Corner, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard fitted.width > 0, fitted.height > 0 else { return }
                let start = dragStartCrop ?? crop
                dragStartCrop = start
                crop = resized(
                    start,
                    corner: corner,
                    dx: value.translation.width / fitted.width,
                    dy: value.translation.height / fitted.height
                )
            }
            .onEnded { _ in dragStartCrop = nil }
    }

    private func resized(_ start: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        switch corner {
        case .topLeft, .bottomLeft:
            minX = min(max(0, start.minX + dx), start.maxX - minFraction)
        case .topRight, .bottomRight:
            maxX = max(min(1, start.maxX + dx), start.minX + minFraction)
        }
        switch corner {
        case .topLeft, .topRight:
            minY = min(max(0, start.minY + dy), start.maxY - minFraction)
        case .bottomLeft, .bottomRight:
            maxY = max(min(1, start.maxY + dy), start.minY + minFraction)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Layout

    /// Where the image sits on screen: as large as fits, centered, with a
    /// margin so the corner handles stay easy to reach.
    private func fittedRect(for size: CGSize, in container: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let margin: CGFloat = 24
        let available = CGSize(
            width: max(1, container.width - margin * 2),
            height: max(1, container.height - margin * 2)
        )
        let scale = min(available.width / size.width, available.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Actions

    /// Turns the photo 90 degrees. The crop box turns with it.
    private func rotate(clockwise: Bool) {
        let image = working
        guard image.size.width > 0, image.size.height > 0 else { return }
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rotated = UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
        let c = crop
        crop = clockwise
            ? CGRect(x: 1 - c.maxY, y: c.minX, width: c.height, height: c.width)
            : CGRect(x: c.minY, y: 1 - c.maxX, width: c.height, height: c.width)
        working = rotated
    }

    private func finish() {
        let width = working.size.width
        let height = working.size.height
        let pixelRect = CGRect(
            x: (crop.minX * width).rounded(),
            y: (crop.minY * height).rounded(),
            width: (crop.width * width).rounded(),
            height: (crop.height * height).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !pixelRect.isEmpty,
              let cgImage = working.cgImage?.cropping(to: pixelRect),
              let data = ImageNormalizer.jpegData(from: UIImage(cgImage: cgImage))
        else { return }
        onDone(data)
    }
}
