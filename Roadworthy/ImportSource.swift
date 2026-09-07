import Foundation

/// Which app someone is importing their history from. Fuelly is the only
/// one actually implemented right now — this is deliberately structured so
/// adding a new source later (Drivvo, AUTOsist, etc.) means adding one case
/// here and one parser file, not redesigning the import flow itself.
enum ImportSource: String, CaseIterable, Identifiable {
    case fuelly = "Fuelly"

    var id: String { rawValue }

    var isSupported: Bool {
        switch self {
        case .fuelly: return true
        }
    }

    var icon: String {
        switch self {
        case .fuelly: return "fuelpump.fill"
        }
    }
}
