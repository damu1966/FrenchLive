import Foundation

struct TranscriptFileWriter {
    let folderURL: URL

    init(folderURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("FrenchTranscripts")
    }()) {
        self.folderURL = folderURL
    }

    func write(_ entries: [TranscriptEntry], startDate: Date) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folderURL.path) {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let fileNameFormatter = DateFormatter()
        fileNameFormatter.dateFormat = "yyyy-MM-dd_HH-mm"

        let fileURL = folderURL.appendingPathComponent(fileNameFormatter.string(from: startDate) + ".txt")

        let content = entries.map { entry in
            "[\(timeFormatter.string(from: entry.timestamp))] \(entry.french) → \(entry.english)"
        }.joined(separator: "\n")

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
