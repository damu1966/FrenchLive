# Copy Transcript — Design Spec
Date: 2026-06-30

## Overview

Add a "Copy" toolbar button to `HistorySheet` that puts the selected transcript's content onto the system clipboard. One file changed, ~6 lines added.

---

## Button

**Placement:** `.toolbar { ToolbarItem(placement: .automatic) { ... } }` on the `HSplitView` in `HistorySheet.body`. Appears in the sheet's title bar area — visible regardless of scroll position.

**Label:** `"Copy"`

**Enabled:** when `selectedFile != nil` (a file is selected and its content is loaded)

**Disabled:** when `selectedFile == nil` (no file selected, content pane shows placeholder)

---

## Clipboard Write

```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(content, forType: .string)
```

No confirmation dialog, no feedback toast. Silent clipboard write is standard macOS behaviour.

---

## Implementation

**Modified file:** `Sources/FrenchLiveCore/History/HistorySheet.swift`

Add `.toolbar` modifier to the `HSplitView` in `body`, after `.frame(minWidth: 600, minHeight: 400)`:

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

## Files Changed

| Action | File |
|---|---|
| Modify | `Sources/FrenchLiveCore/History/HistorySheet.swift` |

---

## Testing

No new unit tests — clipboard write and SwiftUI toolbar are not unit-testable. Verification: `swift build` (zero warnings) + 33-test suite passing.

---

## Out of Scope

- Feedback toast / "Copied!" confirmation
- Copy button in the main transcript view (live session)
- Keyboard shortcut for copy (Cmd+C already works on selected text in the ScrollView)
