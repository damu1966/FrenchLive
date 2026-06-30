# Live Row Source Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `[mic]` / `[sys]` text prefix in live partial-result rows with a `mic.fill` / `speaker.wave.2.fill` icon, matching the icon pattern already used in `TranscriptRowView`.

**Architecture:** Add `liveSource: AudioSource?` to `TranscriptStore` so source travels separately from text. `SessionManager` strips the prefix and sets both `liveText` and `liveSource`. `LiveRowView` gains a `source` parameter and renders the icon in the same 20pt column as `TranscriptRowView`.

**Tech Stack:** SwiftUI, SF Symbols, Swift Testing (`import Testing`, `@Test`, `#expect`), macOS 13+

## Global Constraints

- Target: macOS 13+
- Zero compiler warnings — project baseline is 0 warnings
- Tests run via `bash Resources/test.sh` (not `swift test` directly)
- Test framework: Swift Testing — use `import Testing`, `@Test`, `#expect`; NOT XCTest
- `@MainActor`-isolated types must be accessed inside `await MainActor.run { }` in tests
- Commit style: `feat:` prefix

---

### Task 1: Add `liveSource` to `TranscriptStore`

**Files:**
- Modify: `Sources/FrenchLiveCore/Transcript/TranscriptStore.swift`
- Test: `Tests/FrenchLiveTests/TranscriptStoreTests.swift`

**Interfaces:**
- Consumes: `AudioSource` enum from `Sources/FrenchLiveCore/Transcript/TranscriptEntry.swift`:
  ```swift
  enum AudioSource {
      case mic
      case system
  }
  ```
- Produces: `TranscriptStore.liveSource: AudioSource?` — used by Task 2's `SessionManager` and `ContentView`

- [ ] **Step 1: Add `liveSource` to `TranscriptStore`**

Replace the entire content of `Sources/FrenchLiveCore/Transcript/TranscriptStore.swift` with:

```swift
import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published var liveText: String = ""
    @Published var liveSource: AudioSource? = nil

    func append(_ entry: TranscriptEntry) {
        entries.append(entry)
        liveText = ""
        liveSource = nil
    }

    func clear() {
        entries = []
        liveText = ""
        liveSource = nil
    }
}
```

- [ ] **Step 2: Write the failing tests**

Add these two tests to `Tests/FrenchLiveTests/TranscriptStoreTests.swift`, inside the existing `@Suite struct TranscriptStoreTests { }` block (after the last `@Test`):

```swift
@Test func testLiveSourceDefaultsToNil() async {
    await MainActor.run {
        let store = TranscriptStore()
        #expect(store.liveSource == nil)
    }
}

@Test func testClearResetsLiveSource() async {
    await MainActor.run {
        let store = TranscriptStore()
        store.liveSource = .mic
        store.clear()
        #expect(store.liveSource == nil)
    }
}
```

- [ ] **Step 3: Run tests to verify they pass**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 28 tests in 6 suites passed after 0.XXX seconds.
```

All 28 tests must pass (26 existing + 2 new). Zero failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/FrenchLiveCore/Transcript/TranscriptStore.swift \
        Tests/FrenchLiveTests/TranscriptStoreTests.swift
git commit -m "feat: add liveSource property to TranscriptStore"
```

---

### Task 2: Wire SessionManager + update LiveRowView

**Files:**
- Modify: `Sources/FrenchLiveCore/Session/SessionManager.swift` (lines ~100–122 in `wireRecognizers`, line ~88 in `stop`)
- Modify: `Sources/FrenchLiveCore/ContentView.swift` (`LiveRowView` struct + call site)

**Interfaces:**
- Consumes: `TranscriptStore.liveSource: AudioSource?` from Task 1
- Produces: nothing (leaf wiring)

**Note on testing:** `SessionManager` partial-result paths are not covered by the existing unit tests (they require live audio). `LiveRowView` is pure view rendering. Verification is a clean build + full passing suite.

- [ ] **Step 1: Strip prefix and set `liveSource` in `SessionManager`**

In `Sources/FrenchLiveCore/Session/SessionManager.swift`, find `wireRecognizers()` and update both `onPartialResult` closures.

**mic partial result** — change:
```swift
micRecognizer.onPartialResult = { [weak self] text in
    Task { @MainActor in self?.store.liveText = "[mic] \(text)" }
}
```
to:
```swift
micRecognizer.onPartialResult = { [weak self] text in
    Task { @MainActor in
        self?.store.liveText = text
        self?.store.liveSource = .mic
    }
}
```

**system partial result** — change:
```swift
systemRecognizer.onPartialResult = { [weak self] text in
    Task { @MainActor in self?.store.liveText = "[sys] \(text)" }
}
```
to:
```swift
systemRecognizer.onPartialResult = { [weak self] text in
    Task { @MainActor in
        self?.store.liveText = text
        self?.store.liveSource = .system
    }
}
```

Also in `stop()`, find `store.liveText = ""` and add `store.liveSource = nil` immediately after:
```swift
store.liveText = ""
store.liveSource = nil
```

- [ ] **Step 2: Update `LiveRowView` in `ContentView.swift`**

Find the existing `struct LiveRowView: View` (currently lines ~233–257) and replace it entirely with:

```swift
struct LiveRowView: View {
    let text: String
    let source: AudioSource?
    @State private var showCursor = true
    @State private var cursorTimer: Timer? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("live")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 38, alignment: .leading)
            sourceIcon
                .frame(width: 20, alignment: .center)
            Text(text + (showCursor ? "▌" : " "))
                .font(.body)
                .foregroundStyle(.primary.opacity(0.5))
        }
        .onAppear {
            cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                showCursor.toggle()
            }
        }
        .onDisappear {
            cursorTimer?.invalidate()
            cursorTimer = nil
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        switch source {
        case .mic:
            Image(systemName: "mic.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        case .system:
            Image(systemName: "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .none:
            Color.clear
        }
    }
}
```

- [ ] **Step 3: Update the `LiveRowView` call site in `ContentView.swift`**

Find the call site (currently `LiveRowView(text: store.liveText)`) and change it to:

```swift
LiveRowView(text: store.liveText, source: store.liveSource)
```

- [ ] **Step 4: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected:
```
Build complete!
```

Zero warnings. If any warning appears, fix it before proceeding.

- [ ] **Step 5: Run the full test suite**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 28 tests in 6 suites passed after 0.XXX seconds.
```

All 28 tests must pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FrenchLiveCore/Session/SessionManager.swift \
        Sources/FrenchLiveCore/ContentView.swift
git commit -m "feat: show source icon in LiveRowView; strip [mic]/[sys] prefix"
```
