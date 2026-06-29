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
    let english: String
}
