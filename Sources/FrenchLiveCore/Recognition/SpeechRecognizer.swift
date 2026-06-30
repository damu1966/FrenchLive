// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    // Incremented each time a new task starts. Silence-timer closures capture
    // this value so stale ones (from a previous task) become no-ops.
    private var sessionID = 0

    // Silence detection runs on a dedicated queue — keeps it off the main thread.
    private let silenceQueue = DispatchQueue(label: "com.frenchlive.silence", qos: .userInitiated)
    private var silenceWorkItem: DispatchWorkItem?
    private static let silenceTimeout: TimeInterval = 0.8

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: (([WordToken], String) -> Void)?
    var onError: ((Error) -> Void)?

    func start(locale: Locale) {
        guard !isRunning else { return }

        if recognizer == nil {
            guard let rec = SFSpeechRecognizer(locale: locale) else {
                print("FrenchLive: SpeechRecognizer unavailable for locale \(locale.identifier)")
                onError?(NSError(domain: "SpeechRecognizer", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "Locale \(locale.identifier) unavailable"]))
                return
            }
            rec.defaultTaskHint = .dictation
            recognizer = rec
        }

        guard let rec = recognizer, rec.isAvailable else {
            print("FrenchLive: SpeechRecognizer not available")
            return
        }
        isRunning = true
        startTask(with: rec, locale: locale)
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        cancelSilenceTimer()
        isRunning = false
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        recognizer = nil
    }

    // MARK: - Private

    private func startTask(with rec: SFSpeechRecognizer, locale: Locale) {
        sessionID &+= 1
        let currentID = sessionID

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false

        // Swap to the new request BEFORE ending the old one so the audio
        // tap never sees a nil request between segments (zero-gap restart).
        let oldRequest = self.request
        let oldTask = self.task
        self.request = req
        self.task = nil

        // Signal the old segment to finalise now that new request is live.
        oldTask?.cancel()
        oldRequest?.endAudio()

        print("FrenchLive: starting recognition task (session \(currentID))")
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            var restarted = false

            if let result = result {
                let transcription = result.bestTranscription
                let text = transcription.formattedString
                if result.isFinal {
                    self.cancelSilenceTimer()
                    if !text.isEmpty {
                        let tokens = transcription.segments.map {
                            WordToken(word: $0.substring, confidence: $0.confidence)
                        }
                        self.onFinalResult?(tokens, text)
                    }
                    if let rec = self.recognizer {
                        self.startTask(with: rec, locale: locale)
                    }
                    restarted = true
                } else {
                    self.onPartialResult?(text)
                    self.scheduleSilenceEnd(sessionID: currentID)
                }
            }
            if let error = error {
                let nsError = error as NSError
                print("FrenchLive: recognition error \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
                if !restarted {
                    self.stop()
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.start(locale: locale)
                    }
                }
            }
        }
    }

    // MARK: - Silence detection

    private func scheduleSilenceEnd(sessionID: Int) {
        silenceQueue.async { [weak self] in
            guard let self, self.sessionID == sessionID else { return }
            self.silenceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.sessionID == sessionID else { return }
                self.request?.endAudio()
            }
            self.silenceWorkItem = item
            self.silenceQueue.asyncAfter(deadline: .now() + SpeechRecognizer.silenceTimeout, execute: item)
        }
    }

    private func cancelSilenceTimer() {
        silenceQueue.async { [weak self] in
            self?.silenceWorkItem?.cancel()
            self?.silenceWorkItem = nil
        }
    }
}
