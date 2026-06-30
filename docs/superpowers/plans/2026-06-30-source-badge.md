# Source Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-row source icon to `TranscriptRowView` so users can see whether each utterance came from the microphone or system audio.

**Architecture:** Insert a new 20pt icon column between the timestamp column and the French text in `TranscriptRowView`. The icon is derived from `entry.source` (already stored on every `TranscriptEntry`). A matching 20pt spacer in the translation row keeps `→ English` aligned under the French text. No data model changes.

**Tech Stack:** SwiftUI, SF Symbols (`mic.fill`, `speaker.wave.2.fill`), Swift 5.9+, macOS 13+

## Global Constraints

- Target: macOS 13+ (existing minimum)
- No new dependencies
- Zero compiler warnings — project baseline is 0 warnings
- Tests run via `bash Resources/test.sh` (not `swift test` directly); uses Swift Testing (`import Testing`, `@Test`, `#expect`)
- Commit messages use conventional-commit style: `feat:`, `fix:`, etc.

---

### Task 1: Add source icon column to TranscriptRowView

**Files:**
- Modify: `Sources/FrenchLiveCore/ContentView.swift` (lines 187–214, `TranscriptRowView` only)

**Interfaces:**
- Consumes: `TranscriptEntry.source: AudioSource` (`.mic` | `.system`) — defined in `Sources/FrenchLiveCore/Transcript/TranscriptEntry.swift`
- Produces: nothing (leaf view change)

**Note on testing:** This is pure view rendering of an already-stored enum with no branching logic beyond the icon lookup. There is no meaningful unit test to write. Verification is a clean build + passing test suite.

- [ ] **Step 1: Replace `TranscriptRowView` in `ContentView.swift`**

Find the existing struct (lines 187–214) and replace it entirely with:

```swift
struct TranscriptRowView: View {
    let entry: TranscriptEntry

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                Text(Self.formatter.string(from: entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, alignment: .leading)
                sourceIcon
                    .frame(width: 20, alignment: .center)
                Text(entry.french)
                    .font(.body)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("").frame(width: 38)
                Text("").frame(width: 20)
                Text("→ \(entry.english)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        switch entry.source {
        case .mic:
            Image(systemName: "mic.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        case .system:
            Image(systemName: "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
```

- [ ] **Step 2: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected output ends with:
```
Build complete!
```

If any warning appears, fix it before proceeding.

- [ ] **Step 3: Run the full test suite**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 26 tests in 6 suites passed after 0.XXX seconds.
```

All 26 tests must pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/FrenchLiveCore/ContentView.swift
git commit -m "feat: add mic/system source icon to TranscriptRowView"
```
