// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    private var silenceWorkItem: DispatchWorkItem?
    // 3 s lets conversational turn-taking finish naturally before forcing a cut.
    private static let silenceTimeout: TimeInterval = 3.0
    // Push a translation every N words instead of waiting out a full silence,
    // so long monologues start showing English quickly.
    private static let wordFlushThreshold = 6
    // Short grace period so the Nth word is fully confirmed before we cut.
    private static let wordFlushDelay: TimeInterval = 0.15

    // Last partial result accumulated during the current task — rescued if the
    // task errors out before it can send a proper isFinal result.
    private var lastPartialText: String = ""
    private var lastPartialTokens: [WordToken] = []

    // Identifies the flush (if any) that triggered the endAudio() call
    // currently awaiting a result. Set the instant a flush fires, consumed
    // (read once, then cleared) by whichever final/error follows — the only
    // reliable way to tell the caller which speculative translation (if any)
    // corresponds to this final. Matching by text or by queue position both
    // failed in production (see onFinalResult's flushID param below); an
    // explicit id threaded end-to-end has neither failure mode.
    private var pendingFlushID: UUID?

    var onPartialResult: ((String) -> Void)?
    // Third param is the raw speaker label ("0", "1", …) from Apple; nil when
    // unavailable. Fourth param is the id of the flush that produced this
    // final (see onFlushReady), or nil if no flush preceded it — e.g. Apple's
    // own silence detection finalized before our flush timer fired.
    var onFinalResult: (([WordToken], String, String?, UUID?) -> Void)?
    var onError: ((Error) -> Void)?
    // Fired the instant a chunk is about to be cut (right before endAudio()),
    // with a fresh id for this flush and the snapshotted text — lets the
    // caller start translating in parallel with SFSpeechRecognizer's
    // finalization instead of waiting for isFinal first. The id reappears in
    // onFinalResult once this flush's result comes back.
    var onFlushReady: ((UUID, String) -> Void)?

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
        pendingFlushID = nil
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
                        self.emitFinalResult(from: transcription)
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
                    let wordCount = text.split(separator: " ").count
                    if wordCount >= Self.wordFlushThreshold {
                        self.scheduleFlush(text: text, after: Self.wordFlushDelay, reason: "wordThreshold")
                    } else {
                        self.scheduleFlush(text: text, after: Self.silenceTimeout, reason: "silence")
                    }
                }
            }
            if let error = error {
                let nsError = error as NSError
                print("FrenchLive: recognition error \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
                if !restarted {
                    // A short utterance (<6 words) schedules its flush after a long
                    // silenceTimeout (3s). If the recognizer errors out (e.g. "no
                    // speech detected") before that timer fires — common during a
                    // long pause — the timer is left dangling. Left alone, it later
                    // fires against the NEW request created below, calling endAudio()
                    // on whatever the user is saying next and truncating it. Cancel it
                    // now so the fresh task below starts with no stale timer armed.
                    self.cancelSilenceTimer()

                    // This error follows whatever flush (if any) triggered the
                    // endAudio() call now failing — consume it once so it
                    // travels with the rescued final below, then clear it so a
                    // later, unrelated final can never inherit a stale id.
                    let flushID = self.pendingFlushID
                    self.pendingFlushID = nil

                    // Rescue any partial text the task accumulated before erroring
                    // so the sentence isn't silently dropped from the transcript.
                    let savedText = self.lastPartialText
                    let savedTokens = self.lastPartialTokens
                    self.lastPartialText = ""
                    self.lastPartialTokens = []
                    if !savedText.isEmpty {
                        self.onFinalResult?(savedTokens, savedText, nil, flushID)
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

    // MARK: - Result emission

    private func emitFinalResult(from transcription: SFTranscription) {
        let segments = transcription.segments
        guard !segments.isEmpty else { return }
        let tokens = segments.map { WordToken(word: $0.substring, confidence: $0.confidence) }
        // Consume+clear here too: a NATURAL isFinal (Apple's own silence
        // detection, preempting our flush timer) leaves pendingFlushID nil,
        // which is correct — there's genuinely no speculative translation for
        // it. Clearing unconditionally prevents a stale id from ever leaking
        // into an unrelated later final.
        let flushID = pendingFlushID
        pendingFlushID = nil
        onFinalResult?(tokens, transcription.formattedString, nil, flushID)
    }

    // MARK: - Silence detection

    private func scheduleFlush(text: String, after delay: TimeInterval, reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.silenceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let flushID = UUID()
                self.pendingFlushID = flushID
                print("FrenchLive: [debug] onFlushReady firing reason=\(reason) id=\(flushID) text=\"\(text)\"")
                self.onFlushReady?(flushID, text)
                self.request?.endAudio()
            }
            self.silenceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func cancelSilenceTimer() {
        DispatchQueue.main.async { [weak self] in
            if self?.silenceWorkItem != nil {
                print("FrenchLive: [debug] cancelSilenceTimer — cancelled a scheduled flush before it fired (onFlushReady never fired for that utterance)")
            }
            self?.silenceWorkItem?.cancel()
            self?.silenceWorkItem = nil
        }
    }
}
