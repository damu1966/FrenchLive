// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init() {
        // fr-FR is always available on macOS — force-unwrap is safe here
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))!
        recognizer.defaultTaskHint = .dictation
    }

    func start() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Allow on-device if available, fall back to network otherwise
        req.requiresOnDeviceRecognition = false
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self?.onFinalResult?(text)
                } else {
                    self?.onPartialResult?(text)
                }
            }
            if let error = error {
                self?.onError?(error)
            }
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
    }
}
