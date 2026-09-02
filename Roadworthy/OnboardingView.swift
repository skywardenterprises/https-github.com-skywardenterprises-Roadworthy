import SwiftUI

private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        icon: "car.fill",
        title: "Welcome to Roadworthy",
        description: "Track maintenance, fuel, expenses, and more — all in one place, for every vehicle you own."
    ),
    OnboardingPage(
        icon: "plus.circle.fill",
        title: "Log Anything in One Tap",
        description: "The + button at the bottom is your quick-add menu — fuel, maintenance, expenses, reminders, and more, all a tap away."
    ),
    OnboardingPage(
        icon: "list.bullet.rectangle.fill",
        title: "Vehicle Logs",
        description: "Every entry you log lives here, organized and easy to browse — tap into any category to see the full history."
    ),
    OnboardingPage(
        icon: "chart.line.uptrend.xyaxis",
        title: "See the Full Picture",
        description: "Reports turns your data into MPG trends, spending breakdowns, and more — so you always know where you stand."
    )
]

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private var isLastPage: Bool { currentPage == onboardingPages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Skip — always in the top-right, hidden only on the last page
            // since "Get Started" replaces the need for it there.
            HStack {
                Spacer()
                Button("Skip") {
                    finish()
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding()
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
            }

            Spacer()

            // Page content — swipeable via drag gesture below.
            VStack(spacing: 20) {
                Image(systemName: onboardingPages[currentPage].icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                Text(onboardingPages[currentPage].title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(onboardingPages[currentPage].description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .id(currentPage)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: currentPage)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < 0 {
                            goToNextPage()
                        } else if value.translation.width > 0 && currentPage > 0 {
                            currentPage -= 1
                        }
                    }
            )

            Spacer()

            // Page indicator dots — shows exactly which of the total slides is active.
            HStack(spacing: 8) {
                ForEach(0..<onboardingPages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 28)

            // Next / Get Started — the one clear action that always tells
            // the person what to do next, on every single page.
            Button {
                goToNextPage()
            } label: {
                Text(isLastPage ? "Get Started" : "Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private func goToNextPage() {
        if isLastPage {
            finish()
        } else {
            Haptics.tap()
            withAnimation { currentPage += 1 }
        }
    }

    private func finish() {
        Haptics.tap()
        isPresented = false
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
