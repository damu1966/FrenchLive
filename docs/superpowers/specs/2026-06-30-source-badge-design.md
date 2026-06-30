# Source Badge — Design Spec
Date: 2026-06-30

## Overview

Add a per-row source badge to `TranscriptRowView` so users can see at a glance whether each utterance came from the microphone or system audio. `TranscriptEntry.source` already stores this value; only the view needs to change.

---

## Layout

```
HH:mm  [icon]  French utterance…
               → English translation
```

- A new **20pt-wide icon column** is inserted between the timestamp column (38pt) and the French text
- The icon appears on the first (French) row only
- The translation row gets a 20pt spacer so `→ English` stays left-aligned under the French text

---

## Icon Mapping

| `AudioSource` | SF Symbol | Color |
|---|---|---|
| `.mic` | `mic.fill` | `.blue` |
| `.system` | `speaker.wave.2.fill` | `.orange` |

---

## Behaviour

- Badge is always shown regardless of the session's `selectedSource` mode (Mic Only, System Audio, or Mic + System Audio)
- No special handling for single-source sessions — the badge simply reflects `entry.source` on every row

---

## Files Changed

| Action | File |
|---|---|
| Modify | `Sources/FrenchLiveCore/ContentView.swift` (`TranscriptRowView` only) |

No other files are touched. `TranscriptEntry`, `AudioSource`, `TranscriptStore`, and all other types are unchanged.

---

## Out of Scope

- `LiveRowView` source indicator (currently shows `[mic]` / `[sys]` as a text prefix — separate cleanup)
- Legend or tooltip explaining the icons
- Filtering rows by source
