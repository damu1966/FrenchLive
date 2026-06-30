// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    // Incremented on every new task. Silence-timer closures capture this
    // value; ones from a previous task become no-ops (Fix C).
    private var sessionID = 0

    private var silenceWorkItem: DispatchWorkItem?
    private static let silenceTimeout: TimeInterval = 0.8  // Fix D: was 1.5

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    func start(locale: Locale) {
        guard !isRunning else { return }

        // Fix B: only create the recognizer once; reuse it across segments.
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
        request = req

        print("FrenchLive: starting recognition task (session \(currentID))")
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            var restarted = false

            if let result = result {
                let text = result.bestTranscription.formattedString
                print("FrenchLive: result isFinal=\(result.isFinal) text='\(text)'")
                if result.isFinal {
                    self.cancelSilenceTimer()
                    if !text.isEmpty { self.onFinalResult?(text) }
                    // Fix B: only tear down request+task, keep the recognizer.
                    self.task?.cancel()
                    self.task = nil
                    self.request?.endAudio()
                    self.request = nil
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
        DispatchQueue.main.async { [weak self] in
            // Fix C: drop if a newer task has already started.
            guard let self, self.sessionID == sessionID else { return }
            self.silenceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.sessionID == sessionID else { return }
                print("FrenchLive: silence detected — ending segment (session \(sessionID))")
                self.request?.endAudio()
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
