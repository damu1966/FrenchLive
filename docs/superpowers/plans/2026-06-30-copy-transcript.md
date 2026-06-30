# Copy Transcript Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Copy" toolbar button to `HistorySheet` that copies the selected transcript's content to the system clipboard.

**Architecture:** Single `.toolbar` modifier added to the `HSplitView` in `HistorySheet.body`. The button reads the existing `content: String` state property and writes it to `NSPasteboard`. No new state, no new methods.

**Tech Stack:** SwiftUI `.toolbar`, `NSPasteboard`, macOS 13+

## Global Constraints

- Target: macOS 13+
- Zero compiler warnings — project baseline is 0 warnings
- Commit style: `feat:` prefix
- Button label: `"Copy"`
- Button disabled when `selectedFile == nil`
- Clipboard write: `NSPasteboard.general.clearContents()` then `NSPasteboard.general.setString(content, forType: .string)`
- No confirmation dialog, no feedback toast

---

### Task 1: Add Copy toolbar button to HistorySheet

**Files:**
- Modify: `Sources/FrenchLiveCore/History/HistorySheet.swift` (lines 21–31, `body` computed property)

**Interfaces:**
- Consumes: `content: String`, `selectedFile: URL?` — existing `@State` properties, unchanged
- Produces: nothing — leaf UI change

**Note on testing:** SwiftUI toolbar and `NSPasteboard` are not unit-testable without a running app. Verification is a clean `swift build` (zero warnings) + 33-test suite passing.

---

- [ ] **Step 1: Add `.toolbar` modifier to the `HSplitView` in `body`**

In `Sources/FrenchLiveCore/History/HistorySheet.swift`, replace the `body` computed property (lines 21–31):

**Before:**
```swift
    var body: some View {
        HSplitView {
            fileList
            contentPane
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { loadFiles() }
        .onChange(of: selectedFile) { url in
            loadContent(url)
        }
    }
```

**After:**
```swift
    var body: some View {
        HSplitView {
            fileList
            contentPane
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }
                .disabled(selectedFile == nil)
            }
        }
        .onAppear { loadFiles() }
        .onChange(of: selectedFile) { url in
            loadContent(url)
        }
    }
```

---

- [ ] **Step 2: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected:
```
Build complete!
```

Zero warnings. If any warning appears, fix it before proceeding.

---

- [ ] **Step 3: Run the full test suite**

```bash
bash Resources/test.sh 2>&1 | tail -3
```

Expected:
```
✔ Test run with 33 tests in 6 suites passed after 0.XXX seconds.
```

All 33 tests must pass.

---

- [ ] **Step 4: Commit**

```bash
git add Sources/FrenchLiveCore/History/HistorySheet.swift
git commit -m "feat: add Copy button to history sheet toolbar"
```
