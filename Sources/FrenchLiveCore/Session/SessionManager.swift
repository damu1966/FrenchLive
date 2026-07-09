// Sources/FrenchLiveCore/Session/SessionManager.swift
import Foundation
import AVFoundation
import Speech

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var elapsedSeconds: Int = 0

    var selectedSource: AudioSourceMode {
        get { settings.selectedSource }
        set { settings.selectedSource = newValue }
    }

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

    // Maps raw Apple speaker labels ("0", "1", …) → friendly labels ("P1", "P2", …).
    // Reset each time a new session starts so numbering is consistent per conversation.
    private var speakerLabelMap: [String: String] = [:]
    private var speakerCounter = 0

    // Speculative in-flight translations, one queue per recognizer stream —
    // kicked off by SpeechRecognizer.onFlushReady before the final transcript
    // text is confirmed. A queue, not a single slot: the next chunk's flush
    // can fire before the previous chunk's translation call returns (MyMemory
    // latency can exceed the time it takes to speak 6 more words), so more
    // than one speculative translation can be in flight at once. See
    // PendingFlush.swift.
    private var pendingMicFlushes: [PendingFlush] = []
    private var pendingSystemFlushes: [PendingFlush] = []

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
        speakerLabelMap = [:]
        speakerCounter = 0
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
                systemRecognizer.start(locale: locale)
            } catch {
                print("FrenchLive: ScreenCaptureEngine failed to start: \(error)")
            }
        }
    }

    func pause() async {
        guard state == .recording else { return }
        micEngine.stop()
        micRecognizer.stop()
        await captureEngine.stop()
        systemRecognizer.stop()
        guard state == .recording else { return }
        store.liveText = ""
        store.liveSource = nil
        pendingMicFlushes.removeAll()
        pendingSystemFlushes.removeAll()
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
                systemRecognizer.start(locale: locale)
            } catch {
                print("FrenchLive: ScreenCaptureEngine failed to resume: \(error)")
            }
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
        pendingMicFlushes.removeAll()
        pendingSystemFlushes.removeAll()
        state = .idle
    }

    /// Exposed for unit testing only — sets state without touching hardware.
    func testSetState(_ newState: SessionState) {
        state = newState
    }

    // MARK: - Private

    private func wireRecognizers() {
        // DispatchQueue.main.async is lighter than Task { @MainActor } —
        // no heap allocation for a Task object on every partial result (5-10/sec).
        micRecognizer.onPartialResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.store.liveText = text
                self?.store.liveSource = .mic
            }
        }
        micRecognizer.onError = { error in
            print("FrenchLive: mic recognizer error: \(error)")
        }
        // Fires right before SpeechRecognizer cuts the chunk — start translating
        // now instead of waiting for isFinal, so recognizer finalization and the
        // MyMemory round-trip run concurrently. Appended to a queue (not a single
        // slot) since more than one flush can be in flight at once. flushID is
        // minted by SpeechRecognizer and is the ONLY thing used to reunite this
        // entry with its final — never text, never queue position (both failed
        // in production; see PendingFlush.swift).
        micRecognizer.onFlushReady = { [weak self] flushID, text in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let flush = PendingFlush(id: flushID, text: text, english: nil, entryID: nil)
                self.pendingMicFlushes.append(flush)
                let translator = self.translator
                let srcLang    = self.settings.sourceLanguage
                let tgtLang    = self.settings.targetLanguage
                translator.translateGCD(text, from: srcLang, to: tgtLang) { [weak self] english in
                    guard let self,
                          let idx = self.pendingMicFlushes.firstIndex(where: { $0.id == flushID })
                    else { return }
                    self.pendingMicFlushes[idx].english = english
                    if let id = self.pendingMicFlushes[idx].entryID {
                        self.store.updateEnglish(for: id, english: english)
                        self.pendingMicFlushes.remove(at: idx)
                    }
                }
            }
        }
        micRecognizer.onFinalResult = { [weak self] tokens, text, _, flushID in
            guard let self else { return }
            guard text.split(separator: " ").count >= 2 else {
                // No transcript entry is created, but this final still consumed
                // whatever flush preceded it — discard that entry by id so it
                // doesn't linger in the queue forever.
                if let flushID {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if let idx = self.pendingMicFlushes.firstIndex(where: { $0.id == flushID }) {
                            self.pendingMicFlushes.remove(at: idx)
                        }
                    }
                }
                return
            }
            let capturedAt = Date()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let entry = TranscriptEntry(timestamp: capturedAt, source: .mic,
                                            french: text, tokens: tokens, english: "")
                self.store.append(entry)
                let entryID    = entry.id
                let store      = self.store
                let translator = self.translator
                let srcLang    = self.settings.sourceLanguage
                let tgtLang    = self.settings.targetLanguage
                let matchIndex = flushID.flatMap { fid in self.pendingMicFlushes.firstIndex(where: { $0.id == fid }) }
                let pending    = matchIndex.map { self.pendingMicFlushes[$0] }
                let resolution = resolveFlush(pending)
                switch resolution {
                case .ready(let english):
                    if let idx = matchIndex { self.pendingMicFlushes.remove(at: idx) }
                    store.updateEnglish(for: entryID, english: english)
                case .pendingText:
                    if let idx = matchIndex { self.pendingMicFlushes[idx].entryID = entryID }
                case .none:
                    // translateGCD uses URLSession.dataTask — no Swift Concurrency,
                    // no actor executor — reliable on macOS 26.
                    translator.translateGCD(text, from: srcLang, to: tgtLang) { english in
                        store.updateEnglish(for: entryID, english: english)
                    }
                }
            }
        }

        systemRecognizer.onPartialResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.store.liveText = text
                self?.store.liveSource = .system
            }
        }
        systemRecognizer.onError = { error in
            print("FrenchLive: system recognizer error: \(error)")
        }
        systemRecognizer.onFlushReady = { [weak self] flushID, text in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let flush = PendingFlush(id: flushID, text: text, english: nil, entryID: nil)
                self.pendingSystemFlushes.append(flush)
                let translator = self.translator
                let srcLang    = self.settings.sourceLanguage
                let tgtLang    = self.settings.targetLanguage
                translator.translateGCD(text, from: srcLang, to: tgtLang) { [weak self] english in
                    guard let self,
                          let idx = self.pendingSystemFlushes.firstIndex(where: { $0.id == flushID })
                    else { return }
                    self.pendingSystemFlushes[idx].english = english
                    if let id = self.pendingSystemFlushes[idx].entryID {
                        self.store.updateEnglish(for: id, english: english)
                        self.pendingSystemFlushes.remove(at: idx)
                    }
                }
            }
        }
        systemRecognizer.onFinalResult = { [weak self] tokens, text, _, flushID in
            guard let self else { return }
            guard text.split(separator: " ").count >= 2 else {
                if let flushID {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if let idx = self.pendingSystemFlushes.firstIndex(where: { $0.id == flushID }) {
                            self.pendingSystemFlushes.remove(at: idx)
                        }
                    }
                }
                return
            }
            let capturedAt = Date()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let entry = TranscriptEntry(timestamp: capturedAt, source: .system,
                                            french: text, tokens: tokens, english: "")
                self.store.append(entry)
                let entryID    = entry.id
                let store      = self.store
                let translator = self.translator
                let srcLang    = self.settings.sourceLanguage
                let tgtLang    = self.settings.targetLanguage
                let matchIndex = flushID.flatMap { fid in self.pendingSystemFlushes.firstIndex(where: { $0.id == fid }) }
                let pending    = matchIndex.map { self.pendingSystemFlushes[$0] }
                let resolution = resolveFlush(pending)
                switch resolution {
                case .ready(let english):
                    if let idx = matchIndex { self.pendingSystemFlushes.remove(at: idx) }
                    store.updateEnglish(for: entryID, english: english)
                case .pendingText:
                    if let idx = matchIndex { self.pendingSystemFlushes[idx].entryID = entryID }
                case .none:
                    translator.translateGCD(text, from: srcLang, to: tgtLang) { english in
                        store.updateEnglish(for: entryID, english: english)
                    }
                }
            }
        }
    }

    // Maps raw Apple speaker IDs ("0", "1", …) to "P1", "P2", …
    // Returns nil when the OS doesn't provide a label (single-speaker or older macOS).
    private func resolveSpeakerLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if let existing = speakerLabelMap[raw] { return existing }
        speakerCounter += 1
        let label = "P\(speakerCounter)"
        speakerLabelMap[raw] = label
        return label
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
