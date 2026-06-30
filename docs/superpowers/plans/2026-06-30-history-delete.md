# History Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add right-click context menu and Delete key support to the history browser to move transcript files to the system Trash.

**Architecture:** Three small additions to `HistorySheet.swift`: a `deleteFile(_ url: URL)` method, a `.contextMenu` modifier on each list row, and a `.onDeleteCommand` modifier on the `List`. No new files, no new state properties.

**Tech Stack:** SwiftUI `.contextMenu`, `.onDeleteCommand`, `FileManager.trashItem`, macOS 13+

## Global Constraints

- Target: macOS 13+
- Zero compiler warnings — project baseline is 0 warnings
- Commit style: `feat:` prefix
- Deletion moves to system Trash — no permanent delete, no confirmation dialog
- Post-delete: clear `selectedFile` and `content` if the deleted file was selected; no auto-advance
- Failure to trash (file already gone, permissions): silently ignore

---

### Task 1: Add delete support to HistorySheet

**Files:**
- Modify: `Sources/FrenchLiveCore/History/HistorySheet.swift` (lines 33–44, 87)

**Interfaces:**
- Consumes: `files: [URL]`, `selectedFile: URL?`, `content: String` — existing state properties
- Produces: nothing — leaf feature

**Note on testing:** `FileManager.trashItem` and SwiftUI gesture handling are not unit-testable without a real filesystem and UI runtime. Verification is a clean `swift build` (zero warnings) + 33-test suite passing.

---

- [ ] **Step 1: Add `deleteFile(_ url: URL)` method to `HistorySheet`**

In `Sources/FrenchLiveCore/History/HistorySheet.swift`, add this method after `loadContent` (after line 79, before the closing `}` of `HistorySheet`). Place it between `loadContent` and `displayName`:

**Before (lines 76–88):**
```swift
    private func loadContent(_ url: URL?) {
        guard let url else { content = ""; return }
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? "Could not load file."
    }

    private func displayName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        if let date = Self.inputFormatter.date(from: stem) {
            return Self.outputFormatter.string(from: date)
        }
        return stem
    }
}
```

**After:**
```swift
    private func loadContent(_ url: URL?) {
        guard let url else { content = ""; return }
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? "Could not load file."
    }

    private func deleteFile(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        files.removeAll { $0 == url }
        if selectedFile == url {
            selectedFile = nil
            content = ""
        }
    }

    private func displayName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        if let date = Self.inputFormatter.date(from: stem) {
            return Self.outputFormatter.string(from: date)
        }
        return stem
    }
}
```

---

- [ ] **Step 2: Add `.contextMenu` and `.onDeleteCommand` to `fileList`**

Replace the entire `fileList` computed property (lines 33–44):

**Before:**
```swift
    private var fileList: some View {
        List(files, id: \.self, selection: $selectedFile) { url in
            Text(displayName(for: url))
        }
        .frame(minWidth: 200)
        .overlay {
            if files.isEmpty {
                Text("No transcripts yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
```

**After:**
```swift
    private var fileList: some View {
        List(files, id: \.self, selection: $selectedFile) { url in
            Text(displayName(for: url))
                .contextMenu {
                    Button("Move to Trash", role: .destructive) {
                        deleteFile(url)
                    }
                }
        }
        .frame(minWidth: 200)
        .onDeleteCommand {
            if let url = selectedFile { deleteFile(url) }
        }
        .overlay {
            if files.isEmpty {
                Text("No transcripts yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
```

Key changes:
- `.contextMenu` added to each row's `Text`, containing a single destructive `Button("Move to Trash")`
- `.onDeleteCommand` added to the `List` (between `.frame` and `.overlay`), calling `deleteFile` on the currently selected file if any

---

- [ ] **Step 3: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected:
```
Build complete!
```

Zero warnings. If any warning appears, fix it before proceeding.

---

- [ ] **Step 4: Run the full test suite**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 33 tests in 6 suites passed after 0.XXX seconds.
```

All 33 tests must pass.

---

- [ ] **Step 5: Commit**

```bash
git add Sources/FrenchLiveCore/History/HistorySheet.swift
git commit -m "feat: add Move to Trash via right-click and Delete key in history browser"
```
