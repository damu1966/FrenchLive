# Transcript History Browser — Design Spec
Date: 2026-06-30

## Overview

Add an in-app transcript history browser to FrenchLive. A "History" button in the control bar opens a sheet with a master-detail layout: a file list on the left and the selected transcript's content on the right. No new data model — files are read directly from the output folder on demand.

---

## Access Point

A "History" button is added to the right side of the control bar in `ContentView`, between "Open Folder" and the ⚙ gear button. It is always enabled regardless of session state (idle, recording, paused, stopping).

```swift
Button("History") { showingHistory = true }
```

The sheet is presented via:
```swift
.sheet(isPresented: $showingHistory) {
    HistorySheet(folderPath: settings.outputFolderPath)
}
```

---

## Sheet Layout

`HistorySheet` uses `HSplitView` for a native macOS master-detail layout.

```
┌─────────────────────┬──────────────────────────────────────┐
│ Jun 30, 2026 · 14:35│ [14:35] Bonjour → Hello              │
│ Jun 30, 2026 · 09:12│ [14:36] Comment ça va → How are you  │
│ Jun 29, 2026 · 17:04│ ...                                  │
│                     │                                      │
└─────────────────────┴──────────────────────────────────────┘
```

- **Left column:** `List` of transcript files, minimum width 200pt
- **Right column:** `ScrollView` of selected file content, minimum width 300pt
- **Sheet minimum size:** 600 × 400pt

---

## File List

**Source:** `settings.outputFolderPath` — the same folder `SessionManager` writes to.

**Loading:** On `.onAppear`, scan the folder with `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:)`, filter to files with `.txt` extension, sort by filename **descending** (filenames are `yyyy-MM-dd_HH-mm.txt`, so alphabetical descending = newest first).

**Display name:** Parse the filename stem using `DateFormatter` with format `"yyyy-MM-dd_HH-mm"`, then format for display as `"MMM d, yyyy · HH:mm"`. If parsing fails, show the raw filename stem.

Example: `2026-06-30_14-35.txt` → `Jun 30, 2026 · 14:35`

**Selection:** `List` uses `selection: $selectedFile` (type `URL?`). Loading file content is triggered by `.onChange(of: selectedFile)`.

---

## Content Display

**Loading:** `try? String(contentsOf: url, encoding: .utf8)` on selection. If loading fails, show `"Could not load file."` in secondary color.

**Rendering:** Raw text in a monospaced font (`font(.body.monospaced())`), left-aligned, padded. The format is already human-readable:
```
[14:35] Bonjour → Hello
[14:36] Comment ça va → How are you
```

---

## Empty States

| Condition | Left column | Right column |
|---|---|---|
| Folder empty or missing | `"No transcripts yet."` (secondary) | blank |
| No file selected | — | `"Select a transcript."` (secondary) |
| File load failure | — | `"Could not load file."` (secondary) |

---

## Implementation

**New file:** `Sources/FrenchLiveCore/History/HistorySheet.swift`

```swift
import SwiftUI

struct HistorySheet: View {
    let folderPath: String
    @State private var files: [URL] = []
    @State private var selectedFile: URL? = nil
    @State private var content: String = ""

    private static let inputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f
    }()

    private static let outputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · HH:mm"
        return f
    }()

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

    private var contentPane: some View {
        ScrollView {
            if selectedFile != nil {
                Text(content)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text("Select a transcript.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(minWidth: 300)
    }

    private func loadFiles() {
        let folderURL = URL(fileURLWithPath: folderPath)
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ) else {
            files = []
            return
        }
        files = urls
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

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

**Modified file:** `Sources/FrenchLiveCore/ContentView.swift`

1. Add `@State private var showingHistory = false` alongside `showingSettings`.
2. Add History button to `controlBar` between "Open Folder" and the gear button:
   ```swift
   Button("History") { showingHistory = true }
   ```
3. Add sheet presentation in `mainContent` (alongside the existing settings sheet):
   ```swift
   .sheet(isPresented: $showingHistory) {
       HistorySheet(folderPath: settings.outputFolderPath)
   }
   ```

---

## Files Changed

| Action | File |
|---|---|
| Create | `Sources/FrenchLiveCore/History/HistorySheet.swift` |
| Modify | `Sources/FrenchLiveCore/ContentView.swift` |

---

## Testing

No new unit tests — file I/O and SwiftUI rendering are not unit-testable without hardware/filesystem mocks. Verification: `swift build` (zero warnings) + manual test with real `.txt` files in the output folder.

---

## Out of Scope

- Deleting transcripts from within the app
- Re-parsing file content into `TranscriptEntry` objects for re-rendering
- Search or filter within the file list
- Watching the folder for new files while the sheet is open (no live refresh)
- Copy-to-clipboard of the selected transcript
