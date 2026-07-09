// Sources/FrenchLiveCore/Session/PendingFlush.swift
import Foundation

// One in-flight speculative translation for a single recognizer stream
// (mic or system). SessionManager kicks a translation off the moment
// SpeechRecognizer signals a chunk is about to be cut, before the final
// transcript text is confirmed — this tracks that guess so it can be
// reused (or discarded) once the real final text arrives.
struct PendingFlush {
    let text: String
    var english: String?
    var entryID: UUID?
}

enum FlushResolution {
    case ready(String)   // pending matched and its translation already resolved
    case pendingText      // pending matched but translation is still in flight
    case none              // no usable match — caller should request a fresh translation
}

// Pure decision: given the flush that was speculatively kicked off (if any)
// and the text SFSpeechRecognizer settled on as final, decide what
// SessionManager should do. Kept pure/top-level so it's unit testable
// without spinning up SessionManager or a real SFSpeechRecognizer.
func resolveFlush(_ pending: PendingFlush?, finalText: String) -> FlushResolution {
    guard let pending, pending.text == finalText else { return .none }
    if let english = pending.english { return .ready(english) }
    return .pendingText
}
