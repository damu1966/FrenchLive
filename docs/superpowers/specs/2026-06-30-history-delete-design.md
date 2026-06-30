# History Browser — Delete Transcript — Design Spec
Date: 2026-06-30

## Overview

Add the ability to delete individual transcript files from within the history browser sheet. Two macOS-standard triggers (right-click context menu and Delete key) move the selected file to the system Trash. No confirmation dialog — Trash is recoverable. Only `HistorySheet.swift` changes.

---

## Interaction Triggers

| Trigger | How |
|---|---|
| Right-click a row | Context menu appears with "Move to Trash" (destructive role) |
| Select a row + press ⌫ | `.onDeleteCommand` on the `List` fires |

Both triggers call the same `deleteFile(_ url: URL)` method.

---

## Deletion Logic

**Method:** `private func deleteFile(_ url: URL)`

**Steps:**
1. Call `try FileManager.default.trashItem(at: url, resultingItemURL: nil)` — synchronous, moves to system Trash
2. On success: remove `url` from `files`; if `url == selectedFile`, also set `selectedFile = nil` and `content = ""`
3. On failure (file already gone, permissions denied): silently ignore — `files` will simply retain the stale entry until the sheet is reopened, which is acceptable

---

## Post-Delete State

Selection is cleared after deletion. The content pane shows `"Select a transcript."` The user manually selects the next file. No auto-advance.

---

## Implementation

**Modified file:** `Sources/FrenchLiveCore/History/HistorySheet.swift`

**Change 1 — Add `deleteFile` method:**
```swift
private func deleteFile(_ url: URL) {
    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    files.removeAll { $0 == url }
    if selectedFile == url {
        selectedFile = nil
        content = ""
    }
}
```

**Change 2 — Add `.contextMenu` to each list row in `fileList`:**
```swift
List(files, id: \.self, selection: $selectedFile) { url in
    Text(displayName(for: url))
        .contextMenu {
            Button("Move to Trash", role: .destructive) {
                deleteFile(url)
            }
        }
}
```

**Change 3 — Add `.onDeleteCommand` to the `List`:**
```swift
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
.overlay { ... }
```

---

## Files Changed

| Action | File |
|---|---|
| Modify | `Sources/FrenchLiveCore/History/HistorySheet.swift` |

---

## Testing

No new unit tests — `FileManager.trashItem` and SwiftUI gesture handling are not unit-testable without a real filesystem and UI runtime. Verification: `swift build` (zero warnings) + 33-test suite passing + manual test: right-click a row → "Move to Trash" removes it from the list; select a row + ⌫ does the same.

---

## Out of Scope

- Permanent delete (no Trash)
- Undo support
- Multi-select delete
- Confirmation dialog
