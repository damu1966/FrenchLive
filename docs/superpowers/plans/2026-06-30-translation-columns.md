# Translation Columns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-row stacked translation layout in `TranscriptRowView` with a single-row two-column layout: French on the left, vertical divider, English on the right.

**Architecture:** Pure visual change to one struct in `ContentView.swift`. Replace the `VStack` + two `HStack` body with a single `HStack` that puts French and English in equal-width columns separated by `Divider()`. No data model or logic changes.

**Tech Stack:** SwiftUI, macOS 13+

## Global Constraints

- Target: macOS 13+
- Zero compiler warnings — project baseline is 0 warnings
- Commit style: `feat:` prefix

---

### Task 1: Replace TranscriptRowView body with two-column layout

**Files:**
- Modify: `Sources/FrenchLiveCore/ContentView.swift` (lines 239–259, `TranscriptRowView.body`)

**Interfaces:**
- Consumes: `TranscriptEntry` fields: `timestamp`, `source`, `french`, `english` (unchanged)
- Produces: nothing — leaf view change

**Note on testing:** Pure SwiftUI layout change with no unit-testable logic. Verification is a clean `swift build` (zero warnings) + full passing suite.

- [ ] **Step 1: Replace `TranscriptRowView.body` in `ContentView.swift`**

Find and replace the entire `var body: some View` block inside `struct TranscriptRowView` (lines 239–259). The `formatter`, `sourceIcon`, and struct declaration are unchanged — only `body` changes.

**Before (lines 239–259):**
```swift
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
```

**After:**
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

Key changes:
- Outer `VStack` + two `HStack`s → single `HStack`
- French text: add `.frame(maxWidth: .infinity, alignment: .leading)`
- Add `Divider()` between the two text columns
- English text: remove `"→ "` prefix, change font from `.callout` to `.body`, add `.frame(maxWidth: .infinity, alignment: .leading)`, keep `.foregroundStyle(.secondary)`
- Remove the two spacer `Text("").frame(width:)` placeholders

- [ ] **Step 2: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected:
```
Build complete!
```

Zero warnings. If any warning appears, fix it before proceeding.

- [ ] **Step 3: Run the full test suite**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 33 tests in 6 suites passed after 0.XXX seconds.
```

All 33 tests must pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/FrenchLiveCore/ContentView.swift
git commit -m "feat: show French and English in side-by-side columns in TranscriptRowView"
```
