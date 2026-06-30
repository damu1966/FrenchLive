import Foundation

enum AudioSource: Equatable {
    case mic
    case system
}

struct WordToken: Equatable {
    let word: String
    let confidence: Float  // 0.0 (uncertain) → 1.0 (certain)
}

struct TranscriptEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let source: AudioSource
    let french: String          // full formatted string (used for file output and search)
    let tokens: [WordToken]     // per-word confidence; empty means no data available
    var english: String

    // Convenience init — no confidence data (tests, file writer, placeholders).
    init(timestamp: Date, source: AudioSource, french: String, english: String) {
        self.timestamp = timestamp
        self.source = source
        self.french = french
        self.tokens = []
        self.english = english
    }

    // Full init with per-word confidence tokens from SFSpeech.
    init(timestamp: Date, source: AudioSource, french: String, tokens: [WordToken], english: String) {
        self.timestamp = timestamp
        self.source = source
        self.french = french
        self.tokens = tokens
        self.english = english
    }
}
