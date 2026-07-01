import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published var liveText: String = ""
    @Published var liveSource: AudioSource? = nil

    // O(1) lookup by entry ID instead of O(n) linear scan.
    private var indexByID: [UUID: Int] = [:]

    func append(_ entry: TranscriptEntry) {
        indexByID[entry.id] = entries.count
        entries.append(entry)
        liveText = ""
        liveSource = nil
    }

    func updateEnglish(for id: UUID, english: String) {
        guard let index = indexByID[id] else { return }
        entries[index].english = english
    }

    func clear() {
        entries = []
        indexByID = [:]
        liveText = ""
        liveSource = nil
    }
}
