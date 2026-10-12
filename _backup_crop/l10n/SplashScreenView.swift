import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.accentColor
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Uses your generated logo image if you've added one named
                // "SplashLogo" to Assets.xcassets. Falls back to a simple
                // badge icon if that asset doesn't exist yet, so the app
                // still looks intentional either way.
                if UIImage(named: "SplashLogo") != nil {
                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.white)
                }

                Text("Roadworthy")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Because every car deserves a good record")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .scaleEffect(isAnimating ? 1.0 : 0.85)
            .opacity(isAnimating ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
