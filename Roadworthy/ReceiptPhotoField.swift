import SwiftUI
import PhotosUI

/// A reusable "Receipt Photo" row for forms — lets the user take a photo,
/// choose one from their library, view it, or remove it. Used by both the
/// Maintenance and Expense add/edit forms.
struct ReceiptPhotoField: View {
    @Binding var photoData: Data?

    @State private var showingOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingViewer = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            HStack {
                Text("Receipt Photo").foregroundStyle(.primary)
                Spacer()
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("Add")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Receipt Photo", isPresented: $showingOptions, titleVisibility: .visible) {
            Button("Take Photo") { showingCamera = true }
            Button("Choose from Library") { showingPhotoPicker = true }
            if photoData != nil {
                Button("View Photo") { showingViewer = true }
                Button("Remove Photo", role: .destructive) { photoData = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(imageData: $photoData)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
        .sheet(isPresented: $showingViewer) {
            if let photoData, let uiImage = UIImage(data: photoData) {
                NavigationStack {
                    ScrollView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    .navigationTitle("Receipt Photo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingViewer = false }
                        }
                    }
                }
            }
        }
    }
}
