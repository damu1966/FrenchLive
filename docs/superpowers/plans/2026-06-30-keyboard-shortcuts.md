# Keyboard Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Space (start/pause/resume) and Cmd+. (stop) keyboard shortcuts to the FrenchLive main window.

**Architecture:** Two `.keyboardShortcut()` modifiers added to the existing primary and Stop buttons in `controlBar` inside `ContentView.swift`. No new functions, no new state — shortcut activation follows existing button visibility and disabled logic automatically.

**Tech Stack:** SwiftUI `.keyboardShortcut()`, macOS 13+

## Global Constraints

- Target: macOS 13+
- Zero compiler warnings — project baseline is 0 warnings
- Commit style: `feat:` prefix

---

### Task 1: Add keyboard shortcuts to controlBar buttons

**Files:**
- Modify: `Sources/FrenchLiveCore/ContentView.swift` (lines 108–118, two button modifier chains)

**Interfaces:**
- Consumes: `togglePause()` and `endSession()` — existing private functions, unchanged
- Produces: nothing — leaf UI change

**Note on testing:** `.keyboardShortcut()` is framework-level wiring with no unit-testable logic. Verification is a clean `swift build` (zero warnings) + full passing suite.

- [ ] **Step 1: Add `.keyboardShortcut(" ", modifiers: [])` to the primary button**

In `Sources/FrenchLiveCore/ContentView.swift`, find the primary button in `controlBar` and add the shortcut modifier after `.disabled`:

**Before (lines 105–110):**
```swift
Button(action: togglePause) {
    Label(primaryButtonLabel, systemImage: primaryButtonIcon)
}
.buttonStyle(.borderedProminent)
.tint(primaryButtonTint)
.disabled(sessionManager.state == .stopping)
```

**After:**
```swift
Button(action: togglePause) {
    Label(primaryButtonLabel, systemImage: primaryButtonIcon)
}
.buttonStyle(.borderedProminent)
.tint(primaryButtonTint)
.disabled(sessionManager.state == .stopping)
.keyboardShortcut(" ", modifiers: [])
```

- [ ] **Step 2: Add `.keyboardShortcut(".", modifiers: .command)` to the Stop button**

In the same file, find the Stop button and add the shortcut modifier after `.disabled`:

**Before (lines 113–118):**
```swift
Button(action: endSession) {
    Label("Stop", systemImage: "stop.fill")
}
.buttonStyle(.borderedProminent)
.tint(.red)
.disabled(sessionManager.state == .stopping)
```

**After:**
```swift
Button(action: endSession) {
    Label("Stop", systemImage: "stop.fill")
}
.buttonStyle(.borderedProminent)
.tint(.red)
.disabled(sessionManager.state == .stopping)
.keyboardShortcut(".", modifiers: .command)
```

- [ ] **Step 3: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected:
```
Build complete!
```

Zero warnings. If any warning appears, fix it before proceeding.

- [ ] **Step 4: Run the full test suite**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 33 tests in 6 suites passed after 0.XXX seconds.
```

All 33 tests must pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FrenchLiveCore/ContentView.swift
git commit -m "feat: add Space and Cmd+. keyboard shortcuts for pause/resume and stop"
```
