# Transcript History Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app transcript history browser: a "History" button in the control bar opens a sheet with a file list on the left and transcript content on the right.

**Architecture:** One new file (`HistorySheet.swift`) holds the self-contained sheet view. `ContentView.swift` gets a state flag, a sheet modifier, and a toolbar button — three small additions. No new data model; files are read from `settings.outputFolderPath` on demand using `FileManager` and `String(contentsOf:)`.

**Tech Stack:** SwiftUI `HSplitView`, `FileManager`, macOS 13+

## Global Constraints

- Target: macOS 13+
- Zero compiler warnings — project baseline is 0 warnings
- Commit style: `feat:` prefix
- Sheet minimum frame: 600 × 400pt
- File list minimum width: 200pt; content pane minimum width: 300pt
- Files sorted newest-first by filename (alphabetical descending)
- Filename parse format: `"yyyy-MM-dd_HH-mm"` → display format: `"MMM d, yyyy · HH:mm"`
- History button always enabled regardless of session state

---

### Task 1: Create HistorySheet and wire into ContentView

**Files:**
- Create: `Sources/FrenchLiveCore/History/HistorySheet.swift`
- Modify: `Sources/FrenchLiveCore/ContentView.swift` (lines 7, 44–46, 128–133)

**Interfaces:**
- Consumes: `settings.outputFolderPath: String` (passed as `folderPath: String` init parameter)
- Produces: nothing — leaf feature, no downstream dependencies

**Note on testing:** `HistorySheet` is pure SwiftUI + file I/O. There is no unit-testable logic that isn't already covered by the Swift standard library. Verification is a clean `swift build` (zero warnings) + the existing 33-test suite still passing.

---

- [ ] **Step 1: Create `Sources/FrenchLiveCore/History/HistorySheet.swift`**

Create a new directory `Sources/FrenchLiveCore/History/` and write the file with this exact content:

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
        guard let urls = try? FileManager.default.contentsOfDirectory(
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

---

- [ ] **Step 2: Add `showingHistory` state to `ContentView`**

In `Sources/FrenchLiveCore/ContentView.swift`, find line 7 and add the new state variable on the line immediately after it:

**Before (lines 7–8):**
```swift
    @State private var showingSettings = false

    public init() {
```

**After:**
```swift
    @State private var showingSettings = false
    @State private var showingHistory = false

    public init() {
```

---

- [ ] **Step 3: Add history sheet modifier to `mainContent`**

In the same file, find the `mainContent` computed property. Add a second `.sheet` modifier immediately after the existing settings sheet (lines 44–46):

**Before:**
```swift
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(settings: settings)
        }
    }
```

**After:**
```swift
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(settings: settings)
        }
        .sheet(isPresented: $showingHistory) {
            HistorySheet(folderPath: settings.outputFolderPath)
        }
    }
```

---

- [ ] **Step 4: Add History button to `controlBar`**

In the same file, find the `controlBar` computed property. Add a `Button("History")` immediately after the `Button("Open Folder")` line and before the gear button:

**Before (lines 128–134):**
```swift
            Button("Open Folder") { openTranscriptsFolder() }

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .disabled(sessionManager.state != .idle)
```

**After:**
```swift
            Button("Open Folder") { openTranscriptsFolder() }

            Button("History") { showingHistory = true }

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .disabled(sessionManager.state != .idle)
```

---

- [ ] **Step 5: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected:
```
Build complete!
```

Zero warnings. If any warning appears, fix it before proceeding.

---

- [ ] **Step 6: Run the full test suite**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 33 tests in 6 suites passed after 0.XXX seconds.
```

All 33 tests must pass. `HistorySheet` has no unit tests — file I/O and SwiftUI rendering are not unit-testable without hardware mocks.

---

- [ ] **Step 7: Commit**

```bash
git add Sources/FrenchLiveCore/History/HistorySheet.swift Sources/FrenchLiveCore/ContentView.swift
git commit -m "feat: add transcript history browser sheet"
```
