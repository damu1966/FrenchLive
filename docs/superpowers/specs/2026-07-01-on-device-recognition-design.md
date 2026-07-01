# On-Device Recognition with Server Fallback — Design

## Goal

Prefer on-device speech recognition when the locale supports it; fall back to Apple's server automatically when it doesn't.

## Motivation

Server-based recognition has a ~60-second task limit imposed by Apple. On-device recognition has no such limit, works offline, and is lower-latency. macOS 13+ supports on-device for French and several other languages the app already exposes.

## Change

**File:** `Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift`  
**Method:** `startTask(with:locale:)`

Replace:
```swift
req.requiresOnDeviceRecognition = false
```
With:
```swift
req.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
```

`rec.supportsOnDeviceRecognition` is checked fresh on every `startTask` call, so language changes mid-session are handled automatically.

## Behaviour

| Scenario | Result |
|---|---|
| French on macOS 13+ with model downloaded | On-device — no server limit, works offline |
| Locale without on-device support | Server — transparent fallback |
| Language switched in Settings during a session | Next task picks up the new locale's capability |

## Out of Scope

- No UI indicator for on-device vs server mode
- No user toggle in Settings
- No changes to silence timeout or error-rescue logic
