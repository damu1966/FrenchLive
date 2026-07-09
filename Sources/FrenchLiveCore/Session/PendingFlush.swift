// Sources/FrenchLiveCore/Session/PendingFlush.swift
import Foundation

// One in-flight speculative translation for a single recognizer stream
// (mic or system). SessionManager kicks a translation off the moment
// SpeechRecognizer signals a chunk is about to be cut, before the final
// transcript text is confirmed — this tracks that guess so it can be
// reused (or discarded) once the real final text arrives.
//
// id is minted by SpeechRecognizer at flush time and threaded back through
// onFinalResult's flushID param — the only reliable correspondence between
// a flush and its final. Two prior designs both failed in production:
// matching by text (the recognizer almost always revises a trailing word
// during finalization, so exact equality virtually never held) and matching
// by queue position (a final can be dropped by SessionManager's own
// short-text guard without ever consuming its queue entry, permanently
// desyncing position-based lookups for every later final in the stream). An
// explicit id has neither failure mode: SessionManager looks itself up by
// `$0.id == flushID`, nothing else.
struct PendingFlush {
    let id: UUID
    let text: String
    var english: String?
    var entryID: UUID?
}

enum FlushResolution {
    case ready(String)   // pending matched and its translation already resolved
    case pendingText      // pending matched but translation is still in flight
    case none              // no usable match — caller should request a fresh translation
}

// Pure decision: given the flush claimed for this final (if any), decide
// what SessionManager should do. Kept pure/top-level so it's unit testable
// without spinning up SessionManager or a real SFSpeechRecognizer.
func resolveFlush(_ pending: PendingFlush?) -> FlushResolution {
    guard let pending else { return .none }
    if let english = pending.english { return .ready(english) }
    return .pendingText
}
