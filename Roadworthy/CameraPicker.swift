import SwiftUI
import UIKit

/// Wraps UIKit's camera capture screen so it can be used from SwiftUI.
/// (SwiftUI's PhotosPicker only covers the photo library — there's no
/// built-in SwiftUI component for taking a new photo with the camera.)
struct CameraPicker: UIViewControllerRepresentable {
    /// False on Macs, on devices where Screen Time or a management profile
    /// restricts the camera, and in the Simulator. Presenting the camera
    /// when it isn't available throws an exception and crashes the app, so
    /// every "Take Photo" option checks this first.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

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
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                // Same size and quality as library photos (see ImageNormalizer).
                parent.imageData = ImageNormalizer.jpegData(from: image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
