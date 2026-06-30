// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

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
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false

        // Swap to new request first so appendBuffer never sees nil between segments.
        let oldRequest = self.request
        self.request = req
        // Do NOT cancel self.task here — if called from an isFinal callback the
        // task is already done; cancelling it triggers a second error callback
        // that would call stop() and fight the new task we just created.
        self.task = nil

        print("FrenchLive: starting recognition task")
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
                    self.scheduleSilenceEnd()
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

        // End old request after new task is already receiving audio.
        oldRequest?.endAudio()
    }

    // MARK: - Silence detection

    private func scheduleSilenceEnd() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.silenceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.request?.endAudio()
            }
            self.silenceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + SpeechRecognizer.silenceTimeout,
                                          execute: item)
        }
    }

    private func cancelSilenceTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.silenceWorkItem?.cancel()
            self?.silenceWorkItem = nil
        }
    }
}
