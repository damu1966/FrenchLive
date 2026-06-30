# Pause/Resume Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pause/resume recording so users can hold a session mid-way without ending the timer, transcript entries, or output file context.

**Architecture:** Add `.paused` to `SessionState`; add `pause()` and `resume()` to `SessionManager` (stop/restart engines without touching the timer); update `stop()` to handle both `.recording` and `.paused`; update `ContentView` with a Pause/Resume primary button and a separate Stop button during active sessions.

**Tech Stack:** SwiftUI, AVFoundation, Speech, Swift Testing (`import Testing`, `@Test`, `#expect`), macOS 13+

## Global Constraints

- Target: macOS 13+
- Zero compiler warnings — project baseline is 0 warnings
- Tests run via `bash Resources/test.sh` (not `swift test` directly)
- Test framework: Swift Testing — `import Testing`, `@Test`, `#expect`; NOT XCTest
- `@MainActor`-isolated types accessed inside `await MainActor.run { }` in tests
- Commit style: `feat:` prefix

---

### Task 1: State machine + SessionManager + tests

**Files:**
- Modify: `Sources/FrenchLiveCore/Session/SessionState.swift`
- Modify: `Sources/FrenchLiveCore/Session/SessionManager.swift`
- Test: `Tests/FrenchLiveTests/SessionManagerTests.swift`

**Interfaces:**
- Produces: `SessionState.paused`, `SessionManager.pause() async`, `SessionManager.resume() async`
- Task 2 depends on these for its UI and disabled-state logic

- [ ] **Step 1: Add `.paused` to `SessionState`**

Replace the entire content of `Sources/FrenchLiveCore/Session/SessionState.swift` with:

```swift
import Foundation

enum SessionState: Equatable {
    case idle
    case recording
    case paused
    case stopping
}

enum AudioSourceMode: String, CaseIterable {
    case mic    = "Mic Only"
    case system = "System Audio"
    case both   = "Mic + System Audio"
}
```

- [ ] **Step 2: Write failing tests**

Add these five tests to `Tests/FrenchLiveTests/SessionManagerTests.swift`, inside the existing `@Suite struct SessionManagerTests { }` block (after the last `@Test`):

```swift
@Test func testPauseFromRecordingTransitionsToPaused() async {
    let manager: SessionManager = await MainActor.run {
        let store = TranscriptStore()
        let translator = Translator()
        let settings = SettingsStore()
        let m = SessionManager(store: store, translator: translator, settings: settings)
        m.testSetState(.recording)
        return m
    }
    await manager.pause()
    let state = await MainActor.run { manager.state }
    #expect(state == .paused)
}

@Test func testPauseWhenIdleIsNoOp() async {
    let manager: SessionManager = await MainActor.run {
        let store = TranscriptStore()
        let translator = Translator()
        let settings = SettingsStore()
        return SessionManager(store: store, translator: translator, settings: settings)
    }
    await manager.pause()
    let state = await MainActor.run { manager.state }
    #expect(state == .idle)
}

@Test func testResumeFromPausedTransitionsToRecording() async {
    let manager: SessionManager = await MainActor.run {
        let store = TranscriptStore()
        let translator = Translator()
        let settings = SettingsStore()
        let m = SessionManager(store: store, translator: translator, settings: settings)
        m.testSetState(.paused)
        return m
    }
    await manager.resume()
    let state = await MainActor.run { manager.state }
    #expect(state == .recording)
}

@Test func testResumeWhenIdleIsNoOp() async {
    let manager: SessionManager = await MainActor.run {
        let store = TranscriptStore()
        let translator = Translator()
        let settings = SettingsStore()
        return SessionManager(store: store, translator: translator, settings: settings)
    }
    await manager.resume()
    let state = await MainActor.run { manager.state }
    #expect(state == .idle)
}

@Test func testStopFromPausedTransitionsToIdle() async {
    let manager: SessionManager = await MainActor.run {
        let store = TranscriptStore()
        let translator = Translator()
        let settings = SettingsStore()
        let m = SessionManager(store: store, translator: translator, settings: settings)
        m.testSetState(.paused)
        return m
    }
    await manager.stop()
    let state = await MainActor.run { manager.state }
    #expect(state == .idle)
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bash Resources/test.sh 2>&1 | tail -10
```

Expected: compile error or test failures — `pause()` and `resume()` don't exist yet, and `stop()` still guards `.recording` only.

- [ ] **Step 4: Add `pause()`, `resume()`, update `stop()` in SessionManager**

Replace the entire content of `Sources/FrenchLiveCore/Session/SessionManager.swift` with:

```swift
// Sources/FrenchLiveCore/Session/SessionManager.swift
import Foundation
import AVFoundation
import Speech

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published var selectedSource: AudioSourceMode = .both
    @Published private(set) var elapsedSeconds: Int = 0

    let store: TranscriptStore
    let translator: Translator
    let settings: SettingsStore

    private let micEngine = MicEngine()
    private let captureEngine = ScreenCaptureEngine()
    private let micRecognizer = SpeechRecognizer()
    private let systemRecognizer = SpeechRecognizer()
    private var sessionStartDate: Date?
    private var timer: Timer?
    private var autoSaveTimer: Timer?

    init(store: TranscriptStore, translator: Translator, settings: SettingsStore) {
        self.store = store
        self.translator = translator
        self.settings = settings
        wireRecognizers()
    }

    func start() async {
        guard state == .idle else { return }
        await requestPermissions()
        state = .recording
        sessionStartDate = Date()
        startTimer()
        startAutoSave()
        print("FrenchLive: SessionManager start, source=\(selectedSource)")

        let locale = Locale(identifier: settings.sourceLanguage)

        if selectedSource == .mic || selectedSource == .both {
            micEngine.onBuffer = { [weak self] buffer in
                self?.micRecognizer.appendBuffer(buffer)
            }
            do {
                try micEngine.start()
            } catch {
                print("FrenchLive: MicEngine failed to start: \(error)")
            }
            micRecognizer.start(locale: locale)
        }

        if selectedSource == .system || selectedSource == .both {
            captureEngine.onBuffer = { [weak self] buffer in
                self?.systemRecognizer.appendBuffer(buffer)
            }
            do {
                try await captureEngine.start()
            } catch {
                print("FrenchLive: ScreenCaptureEngine failed to start: \(error)")
            }
            systemRecognizer.start(locale: locale)
        }
    }

    func pause() async {
        guard state == .recording else { return }
        micEngine.stop()
        micRecognizer.stop()
        await captureEngine.stop()
        systemRecognizer.stop()
        store.liveText = ""
        store.liveSource = nil
        state = .paused
    }

    func resume() async {
        guard state == .paused else { return }
        state = .recording
        let locale = Locale(identifier: settings.sourceLanguage)

        if selectedSource == .mic || selectedSource == .both {
            micEngine.onBuffer = { [weak self] buffer in
                self?.micRecognizer.appendBuffer(buffer)
            }
            do {
                try micEngine.start()
            } catch {
                print("FrenchLive: MicEngine failed to resume: \(error)")
            }
            micRecognizer.start(locale: locale)
        }

        if selectedSource == .system || selectedSource == .both {
            captureEngine.onBuffer = { [weak self] buffer in
                self?.systemRecognizer.appendBuffer(buffer)
            }
            do {
                try await captureEngine.start()
            } catch {
                print("FrenchLive: ScreenCaptureEngine failed to resume: \(error)")
            }
            systemRecognizer.start(locale: locale)
        }
    }

    func stop() async {
        guard state == .recording || state == .paused else { return }
        let wasRecording = state == .recording
        state = .stopping
        stopTimer()
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        if wasRecording {
            micEngine.stop()
            micRecognizer.stop()
            await captureEngine.stop()
            systemRecognizer.stop()
        }

        if let startDate = sessionStartDate {
            let outputURL = URL(fileURLWithPath: settings.outputFolderPath)
            do {
                try TranscriptFileWriter(folderURL: outputURL).write(store.entries, startDate: startDate)
            } catch {
                print("FrenchLive: auto-save failed: \(error)")
            }
        }
        sessionStartDate = nil
        store.liveText = ""
        store.liveSource = nil
        state = .idle
    }

    /// Exposed for unit testing only — sets state without touching hardware.
    func testSetState(_ newState: SessionState) {
        state = newState
    }

    // MARK: - Private

    private func wireRecognizers() {
        micRecognizer.onPartialResult = { [weak self] text in
            Task { @MainActor in
                self?.store.liveText = text
                self?.store.liveSource = .mic
            }
        }
        micRecognizer.onError = { error in
            print("FrenchLive: mic recognizer error: \(error)")
        }
        micRecognizer.onFinalResult = { [weak self] text in
            guard let self else { return }
            let capturedAt = Date()
            let srcLang = self.settings.sourceLanguage
            let tgtLang = self.settings.targetLanguage
            Task {
                let english = await self.translator.translate(text, from: srcLang, to: tgtLang)
                await MainActor.run {
                    self.store.append(TranscriptEntry(
                        timestamp: capturedAt, source: .mic, french: text, english: english
                    ))
                }
            }
        }

        systemRecognizer.onPartialResult = { [weak self] text in
            Task { @MainActor in
                self?.store.liveText = text
                self?.store.liveSource = .system
            }
        }
        systemRecognizer.onError = { error in
            print("FrenchLive: system recognizer error: \(error)")
        }
        systemRecognizer.onFinalResult = { [weak self] text in
            guard let self else { return }
            let capturedAt = Date()
            let srcLang = self.settings.sourceLanguage
            let tgtLang = self.settings.targetLanguage
            Task {
                let english = await self.translator.translate(text, from: srcLang, to: tgtLang)
                await MainActor.run {
                    self.store.append(TranscriptEntry(
                        timestamp: capturedAt, source: .system, french: text, english: english
                    ))
                }
            }
        }
    }

    private func requestPermissions() async {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { _ in cont.resume() }
        }
    }

    private func startTimer() {
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startAutoSave() {
        guard settings.autoSaveInterval > 0 else { return }
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: Double(settings.autoSaveInterval) * 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startDate = self.sessionStartDate else { return }
                let outputURL = URL(fileURLWithPath: self.settings.outputFolderPath)
                do {
                    try TranscriptFileWriter(folderURL: outputURL).write(self.store.entries, startDate: startDate)
                } catch {
                    print("FrenchLive: auto-save failed: \(error)")
                }
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify all 33 pass**

```bash
bash Resources/test.sh 2>&1 | tail -5
```

Expected:
```
✔ Test run with 33 tests in 6 suites passed after 0.XXX seconds.
```

All 33 tests must pass (28 existing + 5 new). Zero failures, zero warnings.

- [ ] **Step 6: Commit**

```bash
git add Sources/FrenchLiveCore/Session/SessionState.swift \
        Sources/FrenchLiveCore/Session/SessionManager.swift \
        Tests/FrenchLiveTests/SessionManagerTests.swift
git commit -m "feat: add pause/resume to SessionManager and SessionState"
```

---

### Task 2: ContentView UI

**Files:**
- Modify: `Sources/FrenchLiveCore/ContentView.swift`

**Interfaces:**
- Consumes: `SessionState.paused`, `SessionManager.pause() async`, `SessionManager.resume() async` from Task 1

**Note on testing:** Pure SwiftUI view changes with no unit-testable logic beyond state-driven rendering. Verification is a clean build + full passing suite.

- [ ] **Step 1: Replace `controlBar`, `statusBar`, and `toggleRecording()` in `ContentView.swift`**

Find and replace the `controlBar` computed property (currently lines ~103–129):

```swift
// MARK: - Controls

private var controlBar: some View {
    HStack {
        Button(action: togglePause) {
            Label(primaryButtonLabel, systemImage: primaryButtonIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(primaryButtonTint)
        .disabled(sessionManager.state == .stopping)

        if sessionManager.state == .recording || sessionManager.state == .paused {
            Button(action: endSession) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(sessionManager.state == .stopping)
        }

        Spacer()

        Button("Clear") { store.clear() }
            .disabled(sessionManager.state != .idle)

        Button("Open Folder") { openTranscriptsFolder() }

        Button { showingSettings = true } label: {
            Image(systemName: "gearshape")
        }
        .disabled(sessionManager.state != .idle)
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
}

private var primaryButtonLabel: String {
    switch sessionManager.state {
    case .idle:     return "Start"
    case .recording: return "Pause"
    case .paused:   return "Resume"
    case .stopping: return "Pause"
    }
}

private var primaryButtonIcon: String {
    switch sessionManager.state {
    case .idle:     return "record.circle"
    case .recording: return "pause.fill"
    case .paused:   return "play.fill"
    case .stopping: return "pause.fill"
    }
}

private var primaryButtonTint: Color {
    switch sessionManager.state {
    case .idle:     return .accentColor
    case .recording: return .orange
    case .paused:   return .accentColor
    case .stopping: return .orange
    }
}
```

Find and replace the `statusBar` computed property (currently lines ~133–154):

```swift
// MARK: - Status bar

private var statusBar: some View {
    HStack(spacing: 6) {
        if sessionManager.state == .recording {
            Circle().fill(.red).frame(width: 7, height: 7)
            Text("Recording · \(sessionManager.selectedSource.rawValue) · \(formattedElapsed)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if sessionManager.state == .paused {
            Circle().fill(.yellow).frame(width: 7, height: 7)
            Text("Paused · \(formattedElapsed)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if sessionManager.state == .stopping {
            Text("Saving…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
    .padding(.horizontal)
    .padding(.vertical, 5)
    .background(.bar)
}
```

Find and replace the `toggleRecording()` function (currently lines ~165–173) with two functions:

```swift
private func togglePause() {
    Task {
        switch sessionManager.state {
        case .idle:      await sessionManager.start()
        case .recording: await sessionManager.pause()
        case .paused:    await sessionManager.resume()
        case .stopping:  break
        }
    }
}

private func endSession() {
    Task { await sessionManager.stop() }
}
```

- [ ] **Step 2: Build and verify zero warnings**

```bash
swift build 2>&1 | tail -5
```

Expected:
```
Build complete!
```

Zero warnings. If any warning appears (e.g. exhaustiveness), fix it before proceeding.

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
git commit -m "feat: add Pause/Resume/Stop buttons to ContentView"
```
