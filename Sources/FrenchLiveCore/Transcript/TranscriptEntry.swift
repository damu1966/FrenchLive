import Foundation

enum AudioSource {
    case mic
    case system
}

struct TranscriptEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let source: AudioSource
    let french: String
    var english: String  // var: filled immediately with "" then updated after translation (Fix A)
}
