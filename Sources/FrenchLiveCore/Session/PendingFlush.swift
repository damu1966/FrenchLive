// Sources/FrenchLiveCore/Session/PendingFlush.swift
import Foundation

// One in-flight speculative translation for a single recognizer stream
// (mic or system). SessionManager kicks a translation off the moment
// SpeechRecognizer signals a chunk is about to be cut, before the final
// transcript text is confirmed — this tracks that guess so it can be
// reused (or discarded) once the real final text arrives.
struct PendingFlush {
    let id = UUID()
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

// Finds the oldest still-unclaimed pending flush for a final to claim.
// Deliberately positional, not text-based: a SpeechRecognizer stream only
// ever has one flush "in flight" toward finalization at a time (the next
// chunk can't even start until the current one's final — or error-rescue
// — has been delivered), so the very next final always belongs to the
// oldest unclaimed flush, regardless of exact wording. Matching by text
// failed on nearly every utterance in production: the recognizer almost
// always revises a trailing word between the flush snapshot and the true
// final, so exact-text equality virtually never held — every mismatch
// silently discarded the speculative translation, forced a redundant
// fallback network call, and left the flush orphaned in the queue forever
// (unbounded growth over a session). "Unclaimed" (entryID == nil) still
// matters here too: once a flush is claimed by one final, it must never
// be claimed by another, or the earlier entry's translation is starved.
func oldestUnclaimedFlushIndex(in queue: [PendingFlush]) -> Int? {
    queue.firstIndex(where: { $0.entryID == nil })
}
