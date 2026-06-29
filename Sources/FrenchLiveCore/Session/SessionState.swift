import Foundation

enum SessionState: Equatable {
    case idle
    case recording
    case stopping
}

enum AudioSourceMode: String, CaseIterable {
    case mic    = "Mic Only"
    case system = "System Audio"
    case both   = "Mic + System Audio"
}
