# Live Row Source Icon — Design Spec
Date: 2026-06-30

## Overview

Replace the `[mic]` / `[sys]` text prefix in live (partial-result) rows with the same `mic.fill` / `speaker.wave.2.fill` icon used in `TranscriptRowView`. This requires separating the audio source from the live text in `TranscriptStore`, stripping the prefix from `SessionManager`, and updating `LiveRowView` to accept and display the source.

---

## Data Model

**File:** `Sources/FrenchLiveCore/Transcript/TranscriptStore.swift`

Add one property:

```swift
@Published var liveSource: AudioSource? = nil
```

`clear()` resets `liveSource = nil` alongside `liveText = ""`.

---

## SessionManager Changes

**File:** `Sources/FrenchLiveCore/Session/SessionManager.swift`

In `wireRecognizers()`, replace the prefixed assignments:

```swift
// before
self?.store.liveText = "[mic] \(text)"
self?.store.liveText = "[sys] \(text)"

// after (mic)
self?.store.liveText = text
self?.store.liveSource = .mic

// after (system)
self?.store.liveText = text
self?.store.liveSource = .system
```

In `stop()`, add `store.liveSource = nil` alongside the existing `store.liveText = ""`.

---

## LiveRowView Layout

**File:** `Sources/FrenchLiveCore/ContentView.swift`

`LiveRowView` gains a `source: AudioSource?` parameter and adopts the same 3-column layout as `TranscriptRowView`:

```
live [38pt] | icon [20pt] | partial text▌
```

Icon mapping (identical to `TranscriptRowView`):

| `AudioSource` | SF Symbol | Color |
|---|---|---|
| `.mic` | `mic.fill` | `.blue` |
| `.system` | `speaker.wave.2.fill` | `.orange` |
| `nil` | `Color.clear` (20pt spacer) | — |

Use `@ViewBuilder` for the icon switch, matching the existing `TranscriptRowView.sourceIcon` pattern.

**Call site** (also in `ContentView.swift`):

```swift
// before
LiveRowView(text: store.liveText)

// after
LiveRowView(text: store.liveText, source: store.liveSource)
```

---

## Files Changed

| Action | File |
|---|---|
| Modify | `Sources/FrenchLiveCore/Transcript/TranscriptStore.swift` |
| Modify | `Sources/FrenchLiveCore/Session/SessionManager.swift` |
| Modify | `Sources/FrenchLiveCore/ContentView.swift` (`LiveRowView` struct + call site) |
| Modify | `Tests/FrenchLiveTests/TranscriptStoreTests.swift` (add `liveSource` tests) |

---

## Testing

`TranscriptStoreTests` already covers `liveText` — add two tests for `liveSource`:
- `testLiveSourceDefaultsToNil` — fresh store has `liveSource == nil`
- `testClearResetsLiveSource` — after setting `liveSource = .mic`, `clear()` resets it to `nil`

No changes needed to `SessionManagerTests` (existing tests don't exercise partial results).

---

## Out of Scope

- Sharing the `sourceIcon` computed property between `TranscriptRowView` and `LiveRowView` (DRY refactor) — each view is small enough to inline
- Changing the "live" label color or style
- Showing source in the `TranscriptStore.liveText` string anywhere else
