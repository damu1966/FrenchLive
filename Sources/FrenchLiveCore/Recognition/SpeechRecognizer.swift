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
