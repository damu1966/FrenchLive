// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    private var silenceWorkItem: DispatchWorkItem?
    // 1.5 s gives natural speech room to breathe without a false-silence cut.
    private static let silenceTimeout: TimeInterval = 1.5

    // Last partial result accumulated during the current task — rescued if the
    // task errors out before it can send a proper isFinal result.
    private var lastPartialText: String = ""
    private var lastPartialTokens: [WordToken] = []

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
        lastPartialText = ""
        lastPartialTokens = []
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
        req.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition

        // Swap to new request first so appendBuffer never sees nil between segments.
        let oldRequest = self.request
        self.request = req
        // Do NOT cancel self.task here — if called from an isFinal callback the
        // task is already done; cancelling it triggers a second error callback
        // that would call stop() and fight the new task we just created.
        self.task = nil

        let mode = rec.supportsOnDeviceRecognition ? "on-device" : "server"
        print("FrenchLive: starting recognition task (\(mode))")
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            var restarted = false

            if let result = result {
                let transcription = result.bestTranscription
                let text = transcription.formattedString
                if result.isFinal {
                    self.cancelSilenceTimer()
                    self.lastPartialText = ""
                    self.lastPartialTokens = []
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
                    // Keep the latest partial so we can rescue it if the task errors.
                    self.lastPartialText = text
                    self.lastPartialTokens = transcription.segments.map {
                        WordToken(word: $0.substring, confidence: $0.confidence)
                    }
                    self.onPartialResult?(text)
                    self.scheduleSilenceEnd()
                }
            }
            if let error = error {
                let nsError = error as NSError
                print("FrenchLive: recognition error \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
                if !restarted {
                    // Rescue any partial text the task accumulated before erroring
                    // so the sentence isn't silently dropped from the transcript.
                    let savedText = self.lastPartialText
                    let savedTokens = self.lastPartialTokens
                    self.lastPartialText = ""
                    self.lastPartialTokens = []
                    if !savedText.isEmpty {
                        self.onFinalResult?(savedTokens, savedText)
                    }

                    // Restart via zero-gap startTask so no audio is dropped.
                    if let rec = self.recognizer {
                        self.startTask(with: rec, locale: locale)
                    } else {
                        self.stop()
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            self?.start(locale: locale)
                        }
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
