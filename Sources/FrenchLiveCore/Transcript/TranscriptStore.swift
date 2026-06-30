import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published var liveText: String = ""
    @Published var liveSource: AudioSource? = nil

    func append(_ entry: TranscriptEntry) {
        entries.append(entry)
        liveText = ""
        liveSource = nil
    }

    func clear() {
        entries = []
        liveText = ""
        liveSource = nil
    }
}
