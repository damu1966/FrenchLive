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
                do {
                    try TranscriptFileWriter(folderURL: outputURL).write(self.store.entries, startDate: startDate)
                } catch {
                    print("FrenchLive: auto-save failed: \(error)")
                }
            }
        }
    }
}
