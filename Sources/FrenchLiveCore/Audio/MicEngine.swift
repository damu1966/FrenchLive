// Sources/FrenchLiveCore/Audio/MicEngine.swift
import AVFoundation

final class MicEngine {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    // SFSpeech works best at 16 kHz mono float32.
    private static let speechFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func start() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let speechFormat = Self.speechFormat

        if let conv = AVAudioConverter(from: inputFormat, to: speechFormat) {
            converter = conv
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self, let conv = self.converter else { return }
                let ratio = speechFormat.sampleRate / inputFormat.sampleRate
                let outFrameCount = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
                guard let converted = AVAudioPCMBuffer(pcmFormat: speechFormat, frameCapacity: outFrameCount) else { return }
                var error: NSError?
                conv.convert(to: converted, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                guard error == nil, converted.frameLength > 0 else { return }
                self.onBuffer?(converted)
            }
        } else {
            // Fallback: converter unavailable for this hardware format.
            // Send native format directly; SFSpeech handles resampling internally.
            print("FrenchLive: AVAudioConverter unavailable — using native format")
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                self?.onBuffer?(buffer)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        converter = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
