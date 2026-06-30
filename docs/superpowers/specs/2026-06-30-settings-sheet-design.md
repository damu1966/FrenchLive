# Settings Sheet — Design Spec
Date: 2026-06-30

## Overview

Add a settings sheet to FrenchLive that lets users configure source language, target language, output folder, and auto-save interval. Settings are persisted via `UserDefaults` and take effect on the next recording session.

---

## SettingsStore

**File:** `Sources/FrenchLiveCore/Settings/SettingsStore.swift`

`@MainActor final class SettingsStore: ObservableObject` with four `@AppStorage` properties:

| Property | Type | Default | Key |
|---|---|---|---|
| `sourceLanguage` | `String` | `"fr-FR"` | `"sourceLanguage"` |
| `targetLanguage` | `String` | `"en"` | `"targetLanguage"` |
| `outputFolderPath` | `String` | `~/Documents/FrenchTranscripts` | `"outputFolderPath"` |
| `autoSaveInterval` | `Int` | `0` | `"autoSaveInterval"` |

**Source language options** (locale identifiers for `SFSpeechRecognizer`):
- French — `fr-FR`
- Spanish — `es-ES`
- Italian — `it-IT`
- German — `de-DE`
- Portuguese — `pt-BR`

**Target language options** (language codes for Translation / MyMemory):
- English — `en`
- Spanish — `es`
- French — `fr`
- German — `de`
- Italian — `it`
- Portuguese — `pt`

**Auto-save interval options:** Off (0), 5 min (5), 10 min (10), 30 min (30).

The default `outputFolderPath` is computed once at init from `FileManager.default.urls(for: .documentDirectory, ...)` + `"FrenchTranscripts"`, matching the existing hardcoded path.

---

## Settings Sheet UI

**File:** `Sources/FrenchLiveCore/Settings/SettingsSheet.swift`

`struct SettingsSheet: View` — presented as a SwiftUI sheet from `ContentView`.

**Trigger:** A gear button on the right side of the control bar. Disabled while `sessionManager.state != .idle`.

**Layout:**
```
┌─────────────────────────────────────┐
│  Settings                      [✕]  │
├─────────────────────────────────────┤
│  RECOGNITION                        │
│  Source Language   [French (fr-FR)▾]│
├─────────────────────────────────────┤
│  TRANSLATION                        │
│  Target Language   [English (en)  ▾]│
├─────────────────────────────────────┤
│  FILES                              │
│  Output Folder  ~/Documents/Fre…    │
│                          [Choose…]  │
├─────────────────────────────────────┤
│  SESSION                            │
│  Auto-save        [Off            ▾]│
└─────────────────────────────────────┘
```

- Pickers use `.pickerStyle(.menu)`
- Output folder path is displayed truncated to the last two path components
- "Choose…" opens `NSOpenPanel` with `canChooseDirectories = true`, `canChooseFiles = false`, `allowsMultipleSelection = false`; on confirmation, updates `settings.outputFolderPath`
- Sheet dismissed via the `✕` button or clicking outside
- Changes write to `UserDefaults` immediately via `@AppStorage`; the next session picks them up

---

## Propagation

### ContentView
- Creates `SettingsStore` in `init()` alongside `TranscriptStore` and `Translator`
- Passes `SettingsStore` to `SessionManager.init(store:translator:settings:)`
- Holds `@State private var showingSettings = false`
- Adds `.sheet(isPresented: $showingSettings) { SettingsSheet(settings: settingsStore) }`

### SpeechRecognizer
- Currently creates `SFSpeechRecognizer` at `init()` with hardcoded `fr-FR`
- Change `start()` to `start(locale: Locale)` — creates the recognizer inside `start()` using the provided locale
- `SessionManager` passes `Locale(identifier: settings.sourceLanguage)` at session start

### TranslationEnabledView
- Currently hardcodes `source: "fr"`, `target: "en"` in `TranslationSession.Configuration`
- Change to accept `sourceLanguage: String` and `targetLanguage: String` parameters
- Derive config: strip the region suffix from `sourceLanguage` (e.g. `"fr-FR"` → `"fr"`) before constructing `Locale.Language(identifier:)`; `targetLanguage` is already a bare code (`"en"`, `"es"`, etc.)
- `TranslationSession.Configuration(source: Locale.Language(identifier: sourceLangCode), target: Locale.Language(identifier: targetLanguage))`
- `ContentView` passes values from `SettingsStore`; `@AppStorage` changes trigger re-render which updates config

### Translator
- `translateWithMyMemory` currently hardcodes `langpair=fr|en`
- Change signature to `translate(_ text: String, targetLanguage: String) async -> String`
- Builds `langpair=\(sourceLang)|\(targetLanguage)` — source derived from the first component of `sourceLanguage` (e.g. `"fr-FR"` → `"fr"`)
- All callers in `SessionManager` pass `settings.targetLanguage`

### TranscriptFileWriter
- Currently called with a hardcoded default `folderURL`
- `SessionManager` passes `URL(fileURLWithPath: settings.outputFolderPath)` explicitly at stop time and at auto-save time

### Auto-save (SessionManager)
- Adds `private var autoSaveTimer: Timer?`
- At `start()`: if `settings.autoSaveInterval > 0`, schedule `autoSaveTimer` to fire every `settings.autoSaveInterval * 60` seconds
- On fire: call `TranscriptFileWriter(folderURL: outputURL).write(store.entries, startDate: sessionStartDate)` — overwrites the same file so it stays current mid-session
- At `stop()`: invalidate `autoSaveTimer` before the final write

---

## Files Changed / Created

| Action | File |
|---|---|
| New | `Sources/FrenchLiveCore/Settings/SettingsStore.swift` |
| New | `Sources/FrenchLiveCore/Settings/SettingsSheet.swift` |
| Modified | `Sources/FrenchLiveCore/ContentView.swift` |
| Modified | `Sources/FrenchLiveCore/Session/SessionManager.swift` |
| Modified | `Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift` |
| Modified | `Sources/FrenchLiveCore/Translation/Translator.swift` |
| Modified | `Sources/FrenchLiveCore/TranslationEnabledView.swift` |

---

## Out of Scope

- Appearance settings (font size, theme)
- Per-session language overrides
- Security-scoped bookmarks (app is not sandboxed)
- Exporting settings to a file
