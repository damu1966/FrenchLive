import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published var liveText: String = ""

    func append(_ entry: TranscriptEntry) {
        entries.append(entry)
        liveText = ""
    }

    func clear() {
        entries = []
        liveText = ""
    }
}
