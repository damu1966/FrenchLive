import Testing
import Foundation
@testable import FrenchLiveCore

@Suite struct TranscriptFileWriterTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func testWritesFileAtExpectedPath() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let writer = TranscriptFileWriter(folderURL: tempDir)
        let start = Date()
        let entry = TranscriptEntry(timestamp: start, source: .mic, french: "Bonjour", english: "Hello")
        let url = try writer.write([entry], startDate: start)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func testLineFormat() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let writer = TranscriptFileWriter(folderURL: tempDir)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 29
        comps.hour = 14; comps.minute = 2; comps.second = 0
        let ts = Calendar.current.date(from: comps)!
        let entry = TranscriptEntry(timestamp: ts, source: .mic, french: "Bonjour", english: "Hello")
        let url = try writer.write([entry], startDate: ts)
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("[14:02] Bonjour → Hello"))
    }

    @Test func testCreatesFolderIfMissing() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let missing = tempDir.appendingPathComponent("sub/folder")
        let writer = TranscriptFileWriter(folderURL: missing)
        let entry = TranscriptEntry(timestamp: Date(), source: .mic, french: "Test", english: "Test")
        _ = try writer.write([entry], startDate: Date())
        #expect(FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func testMultipleEntriesProduceMultipleLines() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let writer = TranscriptFileWriter(folderURL: tempDir)
        let now = Date()
        let entries = [
            TranscriptEntry(timestamp: now, source: .mic,    french: "Un",   english: "One"),
            TranscriptEntry(timestamp: now, source: .system, french: "Deux", english: "Two"),
        ]
        let url = try writer.write(entries, startDate: now)
        let lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        #expect(lines.count == 2)
    }

    @Test func testEmptyEntriesWritesEmptyFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let writer = TranscriptFileWriter(folderURL: tempDir)
        let url = try writer.write([], startDate: Date())
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.isEmpty)
    }
}
