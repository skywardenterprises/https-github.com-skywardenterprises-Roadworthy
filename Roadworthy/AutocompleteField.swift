import SwiftUI

/// A text field that suggests previously-entered values as tappable chips —
/// used for things like Station Name and Shop Name, where people tend to
/// visit the same handful of places repeatedly. Suggestions come entirely
/// from data already stored on-device; nothing new is collected or sent
/// anywhere.
struct AutocompleteField: View {
    let title: String
    @Binding var text: String
    /// Candidate values, already deduplicated and ordered by the caller
    /// (most-recently-used first is the recommended order).
    let history: [String]

    @FocusState private var isFocused: Bool
    @State private var dismissedSuggestions: Set<String> = []

    private var suggestions: [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let candidates = history.filter { !dismissedSuggestions.contains($0) }
        let matches: [String]
        if trimmed.isEmpty {
            matches = candidates
        } else {
            matches = candidates.filter {
                $0.localizedCaseInsensitiveContains(trimmed) &&
                $0.localizedCaseInsensitiveCompare(trimmed) != .orderedSame
            }
        }
        return Array(matches.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(title, text: $text)
                .focused($isFocused)

            if isFocused && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                text = suggestion
                                isFocused = false
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                LongPressGesture().onEnded { _ in
                                    Haptics.tap()
                                    dismissedSuggestions.insert(suggestion)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
