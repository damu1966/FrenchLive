# Pause/Resume Recording — Design Spec
Date: 2026-06-30

## Overview

Add pause/resume recording to FrenchLive. A new `.paused` state allows users to hold mid-session without ending it — preserving the elapsed timer, transcript entries, session start date, and output file context. Audio engines and recognizers stop during pause and restart on resume.

---

## State Machine

```
idle ──start()──▶ recording ──pause()──▶ paused
                     ▲                      │
                     └──────resume()────────┘
recording ──stop()──▶ stopping ──▶ idle
paused    ──stop()──▶ stopping ──▶ idle
```

**File:** `Sources/FrenchLiveCore/Session/SessionState.swift`

```swift
enum SessionState: Equatable {
    case idle
    case recording
    case paused
    case stopping
}
```

---

## SessionManager

**File:** `Sources/FrenchLiveCore/Session/SessionManager.swift`

### `pause() async`

Guards `state == .recording`. Stops all audio engines and recognizers, clears `store.liveText` and `store.liveSource`, transitions to `.paused`. Timer and auto-save timer keep running.

```swift
func pause() async {
    guard state == .recording else { return }
    micEngine.stop()
    micRecognizer.stop()
    await captureEngine.stop()
    systemRecognizer.stop()
    store.liveText = ""
    store.liveSource = nil
    state = .paused
}
```

### `resume() async`

Guards `state == .paused`. Restarts engines and recognizers using `settings.sourceLanguage` (same locale as `start()`). Transitions to `.recording`.

```swift
func resume() async {
    guard state == .paused else { return }
    state = .recording
    let locale = Locale(identifier: settings.sourceLanguage)
    if selectedSource == .mic || selectedSource == .both {
        micEngine.onBuffer = { [weak self] buffer in self?.micRecognizer.appendBuffer(buffer) }
        do { try micEngine.start() } catch { print("FrenchLive: MicEngine failed to resume: \(error)") }
        micRecognizer.start(locale: locale)
    }
    if selectedSource == .system || selectedSource == .both {
        captureEngine.onBuffer = { [weak self] buffer in self?.systemRecognizer.appendBuffer(buffer) }
        do { try await captureEngine.start() } catch { print("FrenchLive: ScreenCaptureEngine failed to resume: \(error)") }
        systemRecognizer.start(locale: locale)
    }
}
```

### `stop()` update

Change the guard to accept both `.recording` and `.paused`. Capture original state before transitioning to avoid double-stopping engines that are already halted when paused:

```swift
guard state == .recording || state == .paused else { return }
let wasRecording = state == .recording
state = .stopping
stopTimer()
autoSaveTimer?.invalidate()
autoSaveTimer = nil
if wasRecording {
    micEngine.stop()
    micRecognizer.stop()
    await captureEngine.stop()
    systemRecognizer.stop()
}
// … write file, clear store, sessionStartDate = nil, state = .idle
```

---

## ContentView UI

**File:** `Sources/FrenchLiveCore/ContentView.swift`

### Control Bar

| State | Left buttons | Right buttons |
|---|---|---|
| `.idle` | `[Start]` (record.circle, accent) | Clear · Open Folder · ⚙ |
| `.recording` | `[Pause]` (pause.fill, orange) + `[Stop]` (stop.fill, red) | Clear (disabled) · Open Folder · ⚙ (disabled) |
| `.paused` | `[Resume]` (play.fill, accent) + `[Stop]` (stop.fill, red) | Clear (disabled) · Open Folder · ⚙ (disabled) |
| `.stopping` | `[Pause]` (disabled) + `[Stop]` (disabled) | Clear (disabled) · Open Folder · ⚙ (disabled) |

Replace `toggleRecording()` with two separate action functions:
- `togglePause()` — calls `start()` from `.idle`, `pause()` from `.recording`, `resume()` from `.paused`
- `endSession()` — calls `stop()` from `.recording` or `.paused`

### Status Bar

| State | Display |
|---|---|
| `.recording` | Red dot (`Circle().fill(.red)`) + `"Recording · {source} · {elapsed}"` |
| `.paused` | Yellow dot (`Circle().fill(.yellow)`) + `"Paused · {elapsed}"` |
| `.stopping` | `"Saving…"` |
| `.idle` | `"Ready"` |

The source picker and ⚙ settings button remain disabled during `.paused` (same as `.recording`).

---

## Tests

**File:** `Tests/FrenchLiveTests/SessionManagerTests.swift`

Five new tests using `testSetState()` to set state without touching hardware:

| Test | Setup | Action | Expected |
|---|---|---|---|
| `testPauseFromRecordingTransitionsToPaused` | `testSetState(.recording)` | `await sm.pause()` | `state == .paused` |
| `testPauseWhenIdleIsNoOp` | default | `await sm.pause()` | `state == .idle` |
| `testResumeFromPausedTransitionsToRecording` | `testSetState(.paused)` | `await sm.resume()` | `state == .recording` |
| `testResumeWhenIdleIsNoOp` | default | `await sm.resume()` | `state == .idle` |
| `testStopFromPausedTransitionsToIdle` | `testSetState(.paused)` | `await sm.stop()` | `state == .idle` |

All follow the existing `await MainActor.run { }` pattern from `SessionManagerTests`.

---

## Files Changed

| Action | File |
|---|---|
| Modify | `Sources/FrenchLiveCore/Session/SessionState.swift` |
| Modify | `Sources/FrenchLiveCore/Session/SessionManager.swift` |
| Modify | `Sources/FrenchLiveCore/ContentView.swift` |
| Modify | `Tests/FrenchLiveTests/SessionManagerTests.swift` |

---

## Out of Scope

- Auto-saving on pause (pause is transient; final save on stop is sufficient)
- Pausing only one source while keeping the other active
- Keyboard shortcut for pause/resume (separate feature)
- Showing cumulative active recording time vs. total elapsed time
