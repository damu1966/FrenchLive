# Settings Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a settings sheet to FrenchLive that persists source language, target language, output folder, and auto-save interval via UserDefaults.

**Architecture:** A new `SettingsStore` ObservableObject holds all preferences with UserDefaults persistence. It is created in `ContentView.init()` and passed to `SessionManager`. The sheet is triggered by a gear button in the control bar and presented as a SwiftUI sheet.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, AVFoundation, Speech, ScreenCaptureKit, Translation (macOS 15+)

## Global Constraints

- Minimum platform: macOS 13 (`Package.swift` `.macOS(.v13)`)
- Test framework: Swift Testing (`import Testing`, `@Test`, `#expect`). No XCTest.
- Run tests with: `bash Resources/test.sh`
- App is not sandboxed — plain path strings in UserDefaults are sufficient (no security-scoped bookmarks)
- Settings take effect on the next recording session (not mid-session)

---

### Task 1: SettingsStore

**Files:**
- Create: `Sources/FrenchLiveCore/Settings/SettingsStore.swift`
- Create: `Tests/FrenchLiveTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces:
  - `final class SettingsStore: ObservableObject` (`@MainActor`)
  - `@Published var sourceLanguage: String` — locale identifier e.g. `"fr-FR"`
  - `@Published var targetLanguage: String` — bare code e.g. `"en"`
  - `@Published var outputFolderPath: String` — absolute path string
  - `@Published var autoSaveInterval: Int` — minutes; 0 = off
  - `static let sourceLanguages: [LanguageOption]`
  - `static let targetLanguages: [LanguageOption]`
  - `struct LanguageOption: Identifiable { var id: String { code }; let code: String; let label: String }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FrenchLiveTests/SettingsStoreTests.swift`:

```swift
import Testing
@testable import FrenchLiveCore

@Suite struct SettingsStoreTests {

    @Test func testSourceLanguagesNonEmpty() {
        #expect(!SettingsStore.sourceLanguages.isEmpty)
    }

    @Test func testTargetLanguagesNonEmpty() {
        #expect(!SettingsStore.targetLanguages.isEmpty)
    }

    @Test func testSourceLanguagesContainsFrench() {
        #expect(SettingsStore.sourceLanguages.contains { $0.code == "fr-FR" })
    }

    @Test func testTargetLanguagesContainsEnglish() {
        #expect(SettingsStore.targetLanguages.contains { $0.code == "en" })
    }

    @Test func testSourceLanguagesHaveNonEmptyLabels() {
        for lang in SettingsStore.sourceLanguages {
            #expect(!lang.label.isEmpty)
        }
    }

    @Test func testTargetLanguagesHaveNonEmptyLabels() {
        for lang in SettingsStore.targetLanguages {
            #expect(!lang.label.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
bash Resources/test.sh --filter SettingsStoreTests
```

Expected: compile error — `SettingsStore` not defined yet.

- [ ] **Step 3: Create SettingsStore**

Create `Sources/FrenchLiveCore/Settings/SettingsStore.swift`:

```swift
import Foundation

@MainActor
final class SettingsStore: ObservableObject {

    struct LanguageOption: Identifiable {
        var id: String { code }
        let code: String
        let label: String
    }

    static let sourceLanguages: [LanguageOption] = [
        LanguageOption(code: "fr-FR", label: "French"),
        LanguageOption(code: "es-ES", label: "Spanish"),
        LanguageOption(code: "it-IT", label: "Italian"),
        LanguageOption(code: "de-DE", label: "German"),
        LanguageOption(code: "pt-BR", label: "Portuguese"),
    ]

    static let targetLanguages: [LanguageOption] = [
        LanguageOption(code: "en", label: "English"),
        LanguageOption(code: "es", label: "Spanish"),
        LanguageOption(code: "fr", label: "French"),
        LanguageOption(code: "de", label: "German"),
        LanguageOption(code: "it", label: "Italian"),
        LanguageOption(code: "pt", label: "Portuguese"),
    ]

    @Published var sourceLanguage: String {
        didSet { UserDefaults.standard.set(sourceLanguage, forKey: Keys.sourceLanguage) }
    }
    @Published var targetLanguage: String {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: Keys.targetLanguage) }
    }
    @Published var outputFolderPath: String {
        didSet { UserDefaults.standard.set(outputFolderPath, forKey: Keys.outputFolderPath) }
    }
    @Published var autoSaveInterval: Int {
        didSet { UserDefaults.standard.set(autoSaveInterval, forKey: Keys.autoSaveInterval) }
    }

    private enum Keys {
        static let sourceLanguage    = "sourceLanguage"
        static let targetLanguage    = "targetLanguage"
        static let outputFolderPath  = "outputFolderPath"
        static let autoSaveInterval  = "autoSaveInterval"
    }

    init() {
        let ud = UserDefaults.standard
        let defaultFolder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrenchTranscripts").path
        sourceLanguage   = ud.string(forKey: Keys.sourceLanguage)   ?? "fr-FR"
        targetLanguage   = ud.string(forKey: Keys.targetLanguage)   ?? "en"
        outputFolderPath = ud.string(forKey: Keys.outputFolderPath) ?? defaultFolder
        autoSaveInterval = ud.object(forKey: Keys.autoSaveInterval) as? Int ?? 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
bash Resources/test.sh --filter SettingsStoreTests
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FrenchLiveCore/Settings/SettingsStore.swift \
        Tests/FrenchLiveTests/SettingsStoreTests.swift
git commit -m "feat: add SettingsStore with UserDefaults persistence"
```

---

### Task 2: SpeechRecognizer — configurable locale

**Files:**
- Modify: `Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `func start(locale: Locale)` — replaces the no-arg `start()`; locale is used to create the `SFSpeechRecognizer` and is captured in the restart closure

- [ ] **Step 1: Replace the file**

Rewrite `Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift` in full:

```swift
// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    func start(locale: Locale) {
        guard !isRunning else { return }

        guard let rec = SFSpeechRecognizer(locale: locale) else {
            print("FrenchLive: SpeechRecognizer unavailable for locale \(locale.identifier)")
            onError?(NSError(domain: "SpeechRecognizer", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Locale \(locale.identifier) unavailable"]))
            return
        }
        rec.defaultTaskHint = .dictation
        recognizer = rec

        guard rec.isAvailable else {
            print("FrenchLive: SpeechRecognizer not available for \(locale.identifier)")
            return
        }
        isRunning = true

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        request = req

        print("FrenchLive: SpeechRecognizer starting recognition task")
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                print("FrenchLive: recognition result isFinal=\(result.isFinal) text='\(text)'")
                if result.isFinal {
                    if !text.isEmpty { self.onFinalResult?(text) }
                    self.stop()
                    self.start(locale: locale)
                } else {
                    self.onPartialResult?(text)
                }
            }
            if let error = error {
                let nsError = error as NSError
                print("FrenchLive: recognition error \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                    self.stop()
                    self.start(locale: locale)
                } else {
                    self.onError?(error)
                }
            }
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        isRunning = false
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        recognizer = nil
    }
}
```

- [ ] **Step 2: Verify the build compiles**

```
swift build 2>&1 | head -30
```

Expected: build error on `SessionManager.swift` — `micRecognizer.start()` now requires a `locale:` argument. That's expected; Task 5 fixes it. Confirm the error is only about the missing argument.

- [ ] **Step 3: Commit**

```bash
git add Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
git commit -m "feat: make SpeechRecognizer locale configurable via start(locale:)"
```

---

### Task 3: Translator — configurable language pair

**Files:**
- Modify: `Sources/FrenchLiveCore/Translation/Translator.swift`
- Create: `Tests/FrenchLiveTests/TranslatorTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `func translate(_ text: String, from sourceLanguage: String, to targetLanguage: String) async -> String`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FrenchLiveTests/TranslatorTests.swift`:

```swift
import Testing
@testable import FrenchLiveCore

@Suite struct TranslatorTests {

    @Test func testEmptyTextReturnsEmpty() async {
        let translator = Translator()
        let result = await translator.translate("", from: "fr-FR", to: "en")
        #expect(result == "")
    }

    @Test func testWhitespaceTextReturnsEmpty() async {
        let translator = Translator()
        let result = await translator.translate("   ", from: "fr-FR", to: "en")
        #expect(result == "")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
bash Resources/test.sh --filter TranslatorTests
```

Expected: compile error — `translate(_:from:to:)` not defined yet.

- [ ] **Step 3: Update Translator**

Rewrite `Sources/FrenchLiveCore/Translation/Translator.swift` in full:

```swift
// Sources/FrenchLiveCore/Translation/Translator.swift
import Foundation

#if canImport(Translation)
import Translation
#endif

actor Translator {
    // Stored as Any? because @available cannot annotate stored properties
    private var _session: Any?

    @available(macOS 15.0, *)
    func setSession(_ session: TranslationSession) {
        _session = session
    }

    func translate(_ text: String, from sourceLanguage: String = "fr-FR", to targetLanguage: String = "en") async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if #available(macOS 15.0, *), let session = _session as? TranslationSession {
            return await translateWithApple(text, session: session)
        }
        return await translateWithMyMemory(text, from: sourceLanguage, to: targetLanguage)
    }

    @available(macOS 15.0, *)
    private func translateWithApple(_ text: String, session: TranslationSession) async -> String {
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            return "[translation unavailable]"
        }
    }

    private func translateWithMyMemory(_ text: String, from sourceLanguage: String, to targetLanguage: String) async -> String {
        let sourceLangCode = sourceLanguage.components(separatedBy: "-").first ?? "fr"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(sourceLangCode)|\(targetLanguage)")
        else { return "[translation unavailable]" }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            return decoded.responseData.translatedText
        } catch {
            return "[translation unavailable]"
        }
    }
}

private struct MyMemoryResponse: Decodable {
    let responseData: ResponseData
    struct ResponseData: Decodable {
        let translatedText: String
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
bash Resources/test.sh --filter TranslatorTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FrenchLiveCore/Translation/Translator.swift \
        Tests/FrenchLiveTests/TranslatorTests.swift
git commit -m "feat: make Translator language pair configurable via translate(from:to:)"
```

---

### Task 4: TranslationEnabledView — accept language parameters

**Files:**
- Modify: `Sources/FrenchLiveCore/TranslationEnabledView.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: updated `TranslationEnabledView(content:translator:sourceLanguage:targetLanguage:)` initialiser; updates `TranslationSession.Configuration` when either language string changes

- [ ] **Step 1: Replace the file**

Rewrite `Sources/FrenchLiveCore/TranslationEnabledView.swift` in full:

```swift
// Sources/FrenchLiveCore/TranslationEnabledView.swift
import SwiftUI
import Translation

@available(macOS 15.0, *)
struct TranslationEnabledView<Content: View>: View {
    let content: Content
    let translator: Translator
    let sourceLanguage: String
    let targetLanguage: String

    @State private var config: TranslationSession.Configuration

    init(content: Content, translator: Translator, sourceLanguage: String, targetLanguage: String) {
        self.content = content
        self.translator = translator
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        let srcCode = sourceLanguage.components(separatedBy: "-").first ?? "fr"
        _config = State(initialValue: TranslationSession.Configuration(
            source: Locale.Language(identifier: srcCode),
            target: Locale.Language(identifier: targetLanguage)
        ))
    }

    var body: some View {
        content
            .translationTask(config) { session in
                await translator.setSession(session)
            }
            .onChange(of: sourceLanguage) { _, newValue in
                let srcCode = newValue.components(separatedBy: "-").first ?? "fr"
                config = TranslationSession.Configuration(
                    source: Locale.Language(identifier: srcCode),
                    target: Locale.Language(identifier: targetLanguage)
                )
            }
            .onChange(of: targetLanguage) { _, newValue in
                let srcCode = sourceLanguage.components(separatedBy: "-").first ?? "fr"
                config = TranslationSession.Configuration(
                    source: Locale.Language(identifier: srcCode),
                    target: Locale.Language(identifier: newValue)
                )
            }
    }
}
```

- [ ] **Step 2: Verify the build compiles**

```
swift build 2>&1 | head -30
```

Expected: build error on `ContentView.swift` — `TranslationEnabledView` now needs `sourceLanguage:` and `targetLanguage:` arguments. That's expected; Task 7 fixes it.

- [ ] **Step 3: Commit**

```bash
git add Sources/FrenchLiveCore/TranslationEnabledView.swift
git commit -m "feat: make TranslationEnabledView accept dynamic source/target language"
```

---

### Task 5: SessionManager — wire SettingsStore and auto-save

**Files:**
- Modify: `Sources/FrenchLiveCore/Session/SessionManager.swift`
- Modify: `Tests/FrenchLiveTests/SessionManagerTests.swift`

**Interfaces:**
- Consumes:
  - `SettingsStore` (Task 1) — `sourceLanguage`, `targetLanguage`, `outputFolderPath`, `autoSaveInterval`
  - `SpeechRecognizer.start(locale: Locale)` (Task 2)
  - `Translator.translate(_:from:to:)` (Task 3)
- Produces: `init(store: TranscriptStore, translator: Translator, settings: SettingsStore)`

- [ ] **Step 1: Update the failing tests first**

Replace `Tests/FrenchLiveTests/SessionManagerTests.swift` in full:

```swift
// Tests/FrenchLiveTests/SessionManagerTests.swift
import Testing
import Foundation
@testable import FrenchLiveCore

@Suite struct SessionManagerTests {

    @Test func testInitialStateIsIdle() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let manager = SessionManager(store: store, translator: translator, settings: settings)
            #expect(manager.state == .idle)
        }
    }

    @Test func testDefaultSourceIsBoth() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let manager = SessionManager(store: store, translator: translator, settings: settings)
            #expect(manager.selectedSource == .both)
        }
    }

    @Test func testElapsedSecondsStartsAtZero() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let manager = SessionManager(store: store, translator: translator, settings: settings)
            #expect(manager.elapsedSeconds == 0)
        }
    }

    @Test func testStartWhenAlreadyRecordingIsNoOp() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let m = SessionManager(store: store, translator: translator, settings: settings)
            m.testSetState(.recording)
            return m
        }
        let stateBefore = await MainActor.run { manager.state }
        await manager.start()
        let stateAfter = await MainActor.run { manager.state }
        #expect(stateAfter == stateBefore)
    }

    @Test func testStopWhenIdleIsNoOp() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            return SessionManager(store: store, translator: translator, settings: settings)
        }
        #expect(await MainActor.run { manager.state } == .idle)
        await manager.stop()
        #expect(await MainActor.run { manager.state } == .idle)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
bash Resources/test.sh --filter SessionManagerTests
```

Expected: compile error — `SessionManager.init` still takes 2 arguments.

- [ ] **Step 3: Replace SessionManager**

Rewrite `Sources/FrenchLiveCore/Session/SessionManager.swift` in full:

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

    func stop() async {
        guard state == .recording else { return }
        state = .stopping
        stopTimer()
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        micEngine.stop()
        micRecognizer.stop()
        await captureEngine.stop()
        systemRecognizer.stop()

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
        state = .idle
    }

    /// Exposed for unit testing only — sets state without touching hardware.
    func testSetState(_ newState: SessionState) {
        state = newState
    }

    // MARK: - Private

    private func wireRecognizers() {
        micRecognizer.onPartialResult = { [weak self] text in
            Task { @MainActor in self?.store.liveText = "[mic] \(text)" }
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
            Task { @MainActor in self?.store.liveText = "[sys] \(text)" }
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
                try? TranscriptFileWriter(folderURL: outputURL).write(self.store.entries, startDate: startDate)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
bash Resources/test.sh --filter SessionManagerTests
```

Expected: 5 tests pass.

- [ ] **Step 5: Run the full test suite**

```
bash Resources/test.sh 2>&1 | tail -20
```

Expected: all existing tests pass. Build may still error on `ContentView.swift` (Task 7 fixes it); tests themselves should be green.

- [ ] **Step 6: Commit**

```bash
git add Sources/FrenchLiveCore/Session/SessionManager.swift \
        Tests/FrenchLiveTests/SessionManagerTests.swift
git commit -m "feat: wire SettingsStore into SessionManager; add auto-save timer"
```

---

### Task 6: SettingsSheet UI

**Files:**
- Create: `Sources/FrenchLiveCore/Settings/SettingsSheet.swift`

**Interfaces:**
- Consumes: `SettingsStore` (Task 1) — binds to all four `@Published` properties
- Produces: `struct SettingsSheet: View` — takes `@ObservedObject var settings: SettingsStore`

- [ ] **Step 1: Create the file**

Create `Sources/FrenchLiveCore/Settings/SettingsSheet.swift`:

```swift
// Sources/FrenchLiveCore/Settings/SettingsSheet.swift
import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section("Recognition") {
                    Picker("Source Language", selection: $settings.sourceLanguage) {
                        ForEach(SettingsStore.sourceLanguages) { lang in
                            Text(lang.label).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Translation") {
                    Picker("Target Language", selection: $settings.targetLanguage) {
                        ForEach(SettingsStore.targetLanguages) { lang in
                            Text(lang.label).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Files") {
                    HStack {
                        Text(shortenedPath(settings.outputFolderPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }

                Section("Session") {
                    Picker("Auto-save", selection: $settings.autoSaveInterval) {
                        Text("Off").tag(0)
                        Text("Every 5 min").tag(5)
                        Text("Every 10 min").tag(10)
                        Text("Every 30 min").tag(30)
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380)
    }

    private func shortenedPath(_ path: String) -> String {
        let components = (path as NSString).pathComponents
        let last2 = components.suffix(2)
        return last2.isEmpty ? path : "…/" + last2.joined(separator: "/")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolderPath = url.path
        }
    }
}
```

- [ ] **Step 2: Verify the build compiles (ignoring ContentView errors)**

```
swift build 2>&1 | grep -v ContentView | head -20
```

Expected: no errors outside of `ContentView.swift` (which is still pending Task 7).

- [ ] **Step 3: Commit**

```bash
git add Sources/FrenchLiveCore/Settings/SettingsSheet.swift
git commit -m "feat: add SettingsSheet with pickers for all four settings"
```

---

### Task 7: ContentView — wire everything together

**Files:**
- Modify: `Sources/FrenchLiveCore/ContentView.swift`

**Interfaces:**
- Consumes:
  - `SettingsStore` (Task 1)
  - `TranslationEnabledView(content:translator:sourceLanguage:targetLanguage:)` (Task 4)
  - `SessionManager.init(store:translator:settings:)` (Task 5)
  - `SettingsSheet(settings:)` (Task 6)
- Produces: nothing new — this is the final wiring task

- [ ] **Step 1: Replace the file**

Rewrite `Sources/FrenchLiveCore/ContentView.swift` in full:

```swift
import SwiftUI

public struct ContentView: View {
    @StateObject private var store: TranscriptStore
    @StateObject private var sessionManager: SessionManager
    @StateObject private var settings: SettingsStore
    @State private var showingSettings = false

    public init() {
        let store = TranscriptStore()
        let translator = Translator()
        let settings = SettingsStore()
        _store = StateObject(wrappedValue: store)
        _settings = StateObject(wrappedValue: settings)
        _sessionManager = StateObject(wrappedValue: SessionManager(store: store, translator: translator, settings: settings))
    }

    public var body: some View {
        if #available(macOS 15.0, *) {
            TranslationEnabledView(
                content: mainContent,
                translator: sessionManager.translator,
                sourceLanguage: settings.sourceLanguage,
                targetLanguage: settings.targetLanguage
            )
        } else {
            mainContent
        }
    }

    // MARK: - Main layout

    private var mainContent: some View {
        VStack(spacing: 0) {
            sourcePickerBar
            Divider()
            transcriptScrollView
            Divider()
            controlBar
            Divider()
            statusBar
        }
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(settings: settings)
        }
    }

    // MARK: - Source picker

    private var sourcePickerBar: some View {
        HStack {
            Text("Source:")
                .foregroundStyle(.secondary)
            Picker("", selection: $sessionManager.selectedSource) {
                ForEach(AudioSourceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(sessionManager.state != .idle)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript scroll view

    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.entries) { entry in
                        TranscriptRowView(entry: entry)
                            .id(entry.id)
                    }
                    if !store.liveText.isEmpty {
                        LiveRowView(text: store.liveText)
                            .id("live")
                    }
                }
                .padding()
            }
            .onChange(of: store.entries.count) { _ in
                withAnimation {
                    if let lastId = store.entries.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    } else {
                        proxy.scrollTo("live", anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.liveText) { _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack {
            Button(action: toggleRecording) {
                Label(
                    sessionManager.state == .recording ? "Stop" : "Start",
                    systemImage: sessionManager.state == .recording ? "stop.fill" : "record.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(sessionManager.state == .recording ? .red : .accentColor)
            .disabled(sessionManager.state == .stopping)

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

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            if sessionManager.state == .recording {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("Recording · \(sessionManager.selectedSource.rawValue) · \(formattedElapsed)")
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

    // MARK: - Helpers

    private var formattedElapsed: String {
        let h = sessionManager.elapsedSeconds / 3600
        let m = sessionManager.elapsedSeconds / 60 % 60
        let s = sessionManager.elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func toggleRecording() {
        Task {
            if sessionManager.state == .recording {
                await sessionManager.stop()
            } else {
                await sessionManager.start()
            }
        }
    }

    private func openTranscriptsFolder() {
        let folder = URL(fileURLWithPath: settings.outputFolderPath)
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(folder)
    }
}

// MARK: - Subviews

struct TranscriptRowView: View {
    let entry: TranscriptEntry

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                Text(Self.formatter.string(from: entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, alignment: .leading)
                Text(entry.french)
                    .font(.body)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("").frame(width: 38)
                Text("→ \(entry.english)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LiveRowView: View {
    let text: String
    @State private var showCursor = true
    @State private var cursorTimer: Timer? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("live")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 38, alignment: .leading)
            Text(text + (showCursor ? "▌" : " "))
                .font(.body)
                .foregroundStyle(.primary.opacity(0.5))
        }
        .onAppear {
            cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                showCursor.toggle()
            }
        }
        .onDisappear {
            cursorTimer?.invalidate()
            cursorTimer = nil
        }
    }
}
```

- [ ] **Step 2: Verify the full build passes**

```
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Run the full test suite**

```
bash Resources/test.sh 2>&1 | tail -20
```

Expected: all tests pass (SettingsStoreTests × 6, TranslatorTests × 2, SessionManagerTests × 5, TranscriptStoreTests × 5, TranscriptFileWriterTests × 5, placeholder × 1).

- [ ] **Step 4: Commit**

```bash
git add Sources/FrenchLiveCore/ContentView.swift
git commit -m "feat: wire SettingsStore into ContentView; add gear button and settings sheet"
```
