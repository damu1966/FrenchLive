import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published var liveText: String = ""
    @Published var liveSource: AudioSource? = nil
    // True while the most-recently committed entry is still awaiting its translation.
    // ContentView uses this to hold the scroll on the committed row.
    @Published private(set) var lastEntryPendingTranslation: Bool = false

    // O(1) lookup by entry ID instead of O(n) linear scan.
    private var indexByID: [UUID: Int] = [:]

    func append(_ entry: TranscriptEntry) {
        indexByID[entry.id] = entries.count
        entries.append(entry)
        liveText = ""
        liveSource = nil
        lastEntryPendingTranslation = true
    }

    func updateEnglish(for id: UUID, english: String) {
        guard let index = indexByID[id] else { return }
        entries[index].english = english
        // Only clear the flag when the newest entry's translation arrives.
        if index == entries.count - 1 {
            lastEntryPendingTranslation = false
        }
    }

    func clear() {
        entries = []
        indexByID = [:]
        liveText = ""
        liveSource = nil
        lastEntryPendingTranslation = false
    }
}
