// Sources/FrenchLiveCore/Recognition/SpeechRecognizer.swift
import Speech
import AVFoundation

final class SpeechRecognizer {
    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init() {
        // fr-FR is always available on macOS — force-unwrap is safe here
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))!
        recognizer.defaultTaskHint = .dictation
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Allow on-device if available, fall back to network otherwise
        req.requiresOnDeviceRecognition = false
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    if !text.isEmpty { self.onFinalResult?(text) }
                    // Restart to bypass the ~1-minute limit
                    self.stop()
                    self.start()
                } else {
                    self.onPartialResult?(text)
                }
            }
            if let error = error {
                let nsError = error as NSError
                // Restart on Apple's audio duration limit error, not on user-initiated stop
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 1110 {
                    self.stop()
                    self.start()
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
    }
}
