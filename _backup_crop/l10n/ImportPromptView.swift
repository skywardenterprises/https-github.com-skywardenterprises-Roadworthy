import SwiftUI

struct ImportPromptView: View {
    @Binding var isPresented: Bool
    @State private var showingImport = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Coming From Another App?")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Your maintenance history shouldn't be stuck somewhere else just because you switched apps. Bring it with you — it only takes a minute.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                showingImport = true
            } label: {
                Text("Import My History")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Button("Maybe Later") {
                Haptics.tap()
                isPresented = false
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingImport, onDismiss: {
            isPresented = false
        }) {
            ImportView()
        }
    }
}

#Preview {
    ImportPromptView(isPresented: .constant(true))
}
