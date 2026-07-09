# Reduce translation latency

## Problem

Users report English translations lag ~1-2s behind the moment the 6th word
of a chunk is spoken. The current pipeline runs these steps **sequentially**
for every chunk:

1. Wait for `wordFlushThreshold` (6) words in the partial result.
2. Wait `wordFlushDelay` (0.3s) so the last word settles.
3. Call `request.endAudio()` on `SFSpeechAudioBufferRecognitionRequest`.
4. Wait for `SFSpeechRecognizer` to finalize and deliver `isFinal`.
5. Only then does `SessionManager` call `translator.translateGCD(...)`
   (MyMemory HTTP call).

Steps 4 and 5 are the biggest, least visible contributors — translation
network I/O doesn't even start until recognizer finalization completes.

## Design

### Speculative translation (parallelize finalization and translation)

`SpeechRecognizer`'s existing debounce timer (`scheduleFlush`) is the single
point where the recognizer decides "this chunk is done, cut it now." Today
it only calls `request.endAudio()`. It will also fire a new callback,
`onFlushReady: ((String) -> Void)?`, with the chunk's text **at the same
instant**, so recognizer finalization and the MyMemory network call run
concurrently instead of back-to-back.

`scheduleFlush` changes from `scheduleFlush(after:)` to
`scheduleFlush(text:after:)`. The caller (inside the partial-result
handler, which already has `text` as a local) passes the current text in;
the value is captured by the `DispatchWorkItem` closure at schedule time.
This avoids reading the recognizer's `lastPartialText` var from the main
queue later — that var is otherwise only ever touched on the recognition
callback's own thread, so a cross-thread read would be a data race. Every
new partial result cancels and reschedules the timer (as today), so the
text captured is always from the last partial received before the debounce
window elapses — i.e., effectively the same text that will shortly become
final.

`SessionManager` wires `onFlushReady` for both `micRecognizer` and
`systemRecognizer`. Each recognizer gets its own single-slot pending state:

```swift
private struct PendingFlush {
    let text: String
    var english: String?   // nil while translateGCD is in flight
}
private var pendingMicFlush: PendingFlush?
private var pendingSystemFlush: PendingFlush?
```

`onFlushReady(text)`: store `PendingFlush(text: text, english: nil)`, then
call `translator.translateGCD(text) { english in ... }`, which fills in
`.english` on completion (guarded against a stale/superseded pending
entry by comparing text).

`onFinalResult(tokens, text, _)` (existing handler): create the
`TranscriptEntry` as today, then:
- If a pending flush exists **and its text matches** the final text: use
  its `.english` if already resolved (attach immediately, no wait), or
  mark the pending entry with the new entry's ID so the in-flight
  `translateGCD` completion applies it once ready.
- Otherwise (text differs — recognizer revised a word during finalization
  — or no pending flush exists, e.g. the error-rescue path in
  `SpeechRecognizer`): fall back to today's behavior, a fresh
  `translateGCD` call. No regression versus current behavior for this
  case, just no speedup.

### Tuned constant

`wordFlushDelay`: 0.3s → 0.15s. `wordFlushThreshold` stays at 6 words
(unchanged, to avoid degrading translation chunk quality).

## Error handling / edge cases

- **Orphaned pending flush** (e.g. a silence-timeout cut produces an empty
  final, so `onFinalResult` never fires because of the `!text.isEmpty`
  guard): harmless. The single-slot struct is simply overwritten by the
  next chunk's flush; no unbounded growth, no leak.
- **Text mismatch** between the speculative snapshot and the eventual
  final: falls back to a normal post-hoc `translateGCD` call, matching
  today's latency exactly — never worse than current behavior.
- **Two independent streams**: mic and system recognizers each get their
  own `PendingFlush` slot; no cross-talk between them.
- **Error-rescue path** (`SpeechRecognizer`'s error branch, which emits a
  final result from `lastPartialText` without ever calling
  `onFlushReady`): `SessionManager` sees no matching pending flush and
  falls back to a normal translate call, same as today.

## Testing

`Tests/FrenchLiveTests` uses Swift Testing (not XCTest); existing coverage
is structural (state transitions, store behavior) since `SFSpeechRecognizer`
itself isn't mockable. This change follows the same constraint:

- The `PendingFlush` matching/fallback decision in `SessionManager` (match
  → use ready or pending english; mismatch/absent → fresh translate call)
  is pure enough to unit test directly by invoking the wired closures with
  synthetic text/tokens, following the pattern in `SessionManagerTests.swift`.
- The `scheduleFlush(text:after:)` debounce behavior in `SpeechRecognizer`
  (cancel-and-reschedule, snapshot capture) is not independently testable
  without a real `SFSpeechRecognizer`; verified manually by running the app
  and observing translation latency, per this project's existing pattern
  for recognizer-dependent code.
- No regression check: existing `TranslatorTests` and `SessionManagerTests`
  must continue to pass unchanged.
