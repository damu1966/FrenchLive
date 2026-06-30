# Keyboard Shortcuts — Design Spec
Date: 2026-06-30

## Overview

Add two keyboard shortcuts to FrenchLive's main window: Space to start/pause/resume, Cmd+. to stop. Shortcuts are window-only (active when FrenchLive is the frontmost window) and implemented as `.keyboardShortcut()` modifiers on the existing control bar buttons.

---

## Shortcuts

| Key | Action | Active when |
|---|---|---|
| `Space` | Start (from `.idle`), Pause (from `.recording`), Resume (from `.paused`) | Always (primary button is always visible; disabled during `.stopping`) |
| `Cmd+.` | Stop | `.recording` or `.paused` only (Stop button is conditionally rendered) |

**Why Cmd+. instead of Escape:** Escape is reserved by SwiftUI for dismissing sheets and popovers. Using it for Stop would conflict with the settings sheet. Cmd+. is the macOS convention for "stop" (used in Xcode, Terminal, etc.).

**Activation follows button state:** `.keyboardShortcut()` on a disabled button is inactive. The existing disabled logic (`sessionManager.state == .stopping`) already suppresses both shortcuts during the `.stopping` transition. No additional guard logic needed.

---

## Implementation

**File:** `Sources/FrenchLiveCore/ContentView.swift`

Add one modifier to the primary button in `controlBar`:

```swift
Button(action: togglePause) {
    Label(primaryButtonLabel, systemImage: primaryButtonIcon)
}
.buttonStyle(.borderedProminent)
.tint(primaryButtonTint)
.disabled(sessionManager.state == .stopping)
.keyboardShortcut(" ", modifiers: [])   // ← add this line
```

Add one modifier to the Stop button in `controlBar`:

```swift
Button(action: endSession) {
    Label("Stop", systemImage: "stop.fill")
}
.buttonStyle(.borderedProminent)
.tint(.red)
.disabled(sessionManager.state == .stopping)
.keyboardShortcut(".", modifiers: .command)   // ← add this line
```

No other files change.

---

## What Doesn't Change

- `SessionManager`, `SessionState`, `TranscriptStore`, `Translator` — no logic changes
- `togglePause()`, `endSession()` — existing functions, unchanged
- All other views and subviews

---

## Testing

No new unit tests (shortcut wiring is framework-level behavior). Verification: `swift build` (zero warnings) + manual confirmation that Space and Cmd+. trigger the correct actions in each session state.

---

## Out of Scope

- Global shortcuts (active when FrenchLive is not the frontmost window)
- Customisable shortcut keys
- Keyboard shortcut indicators in the UI (tooltips, menu items)
- Additional shortcuts (e.g., Cmd+S to save, Cmd+K to clear)
