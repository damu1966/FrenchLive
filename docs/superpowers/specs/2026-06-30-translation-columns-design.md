# Translation Columns — Design Spec
Date: 2026-06-30

## Overview

Replace the two-row stacked layout in `TranscriptRowView` with a single-row two-column layout: French on the left, English on the right, separated by a vertical divider. This makes dense transcripts easier to scan by keeping source and translation visually parallel rather than stacked.

---

## Current Layout

```
[HH:mm] [icon] French text…
               → English text…
```

Two rows per entry. The `→` prefix and `.callout` font distinguish the translation, but the stacked format requires vertical scanning to compare source and translation.

---

## New Layout

```
[HH:mm] [icon] | French text…  | │ | English text… |
```

A single `HStack` per entry:

| Column | Width | Font | Color |
|---|---|---|---|
| Timestamp | 38pt fixed | `.caption` | `.tertiary` |
| Source icon | 20pt fixed | `.caption` | `.blue` / `.orange` |
| French text | `maxWidth: .infinity` | `.body` | `.primary` |
| Divider | automatic (1pt) | — | system separator |
| English text | `maxWidth: .infinity` | `.body` | `.secondary` |

---

## Implementation

**File:** `Sources/FrenchLiveCore/ContentView.swift`

Replace the entire `body` of `struct TranscriptRowView: View` with:

```swift
var body: some View {
    HStack(alignment: .top, spacing: 8) {
        Text(Self.formatter.string(from: entry.timestamp))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 38, alignment: .leading)
        sourceIcon
            .frame(width: 20, alignment: .center)
        Text(entry.french)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
        Text(entry.english)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

The `sourceIcon` computed property and `DateFormatter` are unchanged.

---

## What Changes

| Item | Before | After |
|---|---|---|
| Layout | Two-row `VStack` | Single-row `HStack` |
| English font | `.callout` | `.body` |
| English prefix | `→ ` | Removed |
| Column separator | None | `Divider()` |

---

## What Doesn't Change

- `LiveRowView` — unaffected (shows one language at a time)
- `TranscriptEntry`, `TranscriptStore`, `SessionManager` — no data model changes
- Timestamp format, source icon, column widths for the fixed columns

---

## Testing

No new unit tests. This is a pure layout change with no logic. Verification: `swift build` (zero warnings) + visual inspection in the running app.

---

## Out of Scope

- Configurable column widths or split ratio
- Collapsing/hiding the English column
- Copying individual columns to clipboard
- Showing a language label header above the columns
