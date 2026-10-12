import SwiftUI
import UIKit

/// Takes a photo with the camera, then lets the person rotate and crop it
/// before it is saved. Use it as a sheet; it dismisses itself when the photo
/// is accepted or the camera is cancelled. "Retake" in the crop screen goes
/// back to the camera.
struct CameraPicker: View {
    /// False on Macs, on devices where Screen Time or a management profile
    /// restricts the camera, and in the Simulator. Presenting the camera
    /// when it isn't available throws an exception and crashes the app, so
    /// every "Take Photo" option checks this first.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var capturedData: Data?

    var body: some View {
        if let capturedData {
            PhotoCropRotateView(
                workingData: capturedData,
                cancelTitle: "Retake",
                onDone: { data in
                    imageData = data
                    dismiss()
                },
                onCancel: { self.capturedData = nil }
            )
        } else {
            CameraCapture(
                onCapture: { image in
                    // Kept at working size so the crop screen can crop without losing detail.
                    capturedData = ImageNormalizer.workingData(from: image)
                },
                onCancel: { dismiss() }
            )
            .ignoresSafeArea()
        }
    }
}

/// Wraps UIKit's camera capture screen so it can be used from SwiftUI.
/// (SwiftUI's PhotosPicker only covers the photo library — there's no
/// built-in SwiftUI component for taking a new photo with the camera.)
private struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Nothing to update after creation.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture

        init(_ parent: CameraCapture) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
