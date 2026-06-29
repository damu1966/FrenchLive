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

    private let micEngine = MicEngine()
    private let captureEngine = ScreenCaptureEngine()
    private let micRecognizer = SpeechRecognizer()
    private let systemRecognizer = SpeechRecognizer()
    private var sessionStartDate: Date?
    private var timer: Timer?

    init(store: TranscriptStore, translator: Translator) {
        self.store = store
        self.translator = translator
        wireRecognizers()
    }

    func start() async {
        guard state == .idle else { return }
        await requestPermissions()
        state = .recording
        sessionStartDate = Date()
        startTimer()

        if selectedSource == .mic || selectedSource == .both {
            micEngine.onBuffer = { [weak self] buffer in
                self?.micRecognizer.appendBuffer(buffer)
            }
            try? micEngine.start()
            micRecognizer.start()
        }

        if selectedSource == .system || selectedSource == .both {
            captureEngine.onBuffer = { [weak self] buffer in
                self?.systemRecognizer.appendBuffer(buffer)
            }
            try? await captureEngine.start()
            systemRecognizer.start()
        }
    }

    func stop() async {
        guard state == .recording else { return }
        state = .stopping
        stopTimer()

        micEngine.stop()
        micRecognizer.stop()
        await captureEngine.stop()
        systemRecognizer.stop()

        if let startDate = sessionStartDate {
            try? TranscriptFileWriter().write(store.entries, startDate: startDate)
        }
        sessionStartDate = nil
        state = .idle
    }

    /// Exposed for unit testing only — sets state without touching hardware.
    func testSetState(_ newState: SessionState) {
        state = newState
    }

    // MARK: - Private

    private func wireRecognizers() {
        micRecognizer.onPartialResult = { [weak self] text in
            Task { @MainActor in self?.store.liveText = text }
        }
        micRecognizer.onFinalResult = { [weak self] text in
            guard let self else { return }
            Task {
                let english = await self.translator.translate(text)
                await MainActor.run {
                    self.store.append(TranscriptEntry(
                        timestamp: Date(), source: .mic, french: text, english: english
                    ))
                }
            }
        }

        systemRecognizer.onPartialResult = { [weak self] text in
            Task { @MainActor in self?.store.liveText = text }
        }
        systemRecognizer.onFinalResult = { [weak self] text in
            guard let self else { return }
            Task {
                let english = await self.translator.translate(text)
                await MainActor.run {
                    self.store.append(TranscriptEntry(
                        timestamp: Date(), source: .system, french: text, english: english
                    ))
                }
            }
        }
    }

    private func requestPermissions() async {
        // Speech recognition
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
        // Microphone
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { _ in cont.resume() }
        }
        // Screen recording is triggered automatically by SCShareableContent in ScreenCaptureEngine
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
}
