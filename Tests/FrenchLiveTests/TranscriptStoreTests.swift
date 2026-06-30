import Testing
import Foundation
@testable import FrenchLiveCore

@Suite struct TranscriptStoreTests {

    @Test func testInitialStateIsEmpty() async {
        await MainActor.run {
            let store = TranscriptStore()
            #expect(store.entries.isEmpty)
            #expect(store.liveText.isEmpty)
        }
    }

    @Test func testAppendAddsEntry() async {
        await MainActor.run {
            let store = TranscriptStore()
            let entry = TranscriptEntry(timestamp: Date(), source: .mic, french: "Bonjour", english: "Hello")
            store.append(entry)
            #expect(store.entries.count == 1)
            #expect(store.entries[0].french == "Bonjour")
        }
    }

    @Test func testAppendClearsLiveText() async {
        await MainActor.run {
            let store = TranscriptStore()
            store.liveText = "En cours..."
            let entry = TranscriptEntry(timestamp: Date(), source: .mic, french: "Bonjour", english: "Hello")
            store.append(entry)
            #expect(store.liveText.isEmpty)
        }
    }

    @Test func testClearRemovesEntriesAndLiveText() async {
        await MainActor.run {
            let store = TranscriptStore()
            store.append(TranscriptEntry(timestamp: Date(), source: .mic, french: "Un", english: "One"))
            store.liveText = "Deux..."
            store.clear()
            #expect(store.entries.isEmpty)
            #expect(store.liveText.isEmpty)
        }
    }

    @Test func testOrderPreservedOnMultipleAppends() async {
        await MainActor.run {
            let store = TranscriptStore()
            store.append(TranscriptEntry(timestamp: Date(), source: .mic, french: "Un", english: "One"))
            store.append(TranscriptEntry(timestamp: Date(), source: .system, french: "Deux", english: "Two"))
            #expect(store.entries[0].french == "Un")
            #expect(store.entries[1].french == "Deux")
        }
    }

    @Test func testLiveSourceDefaultsToNil() async {
        await MainActor.run {
            let store = TranscriptStore()
            #expect(store.liveSource == nil)
        }
    }

    @Test func testClearResetsLiveSource() async {
        await MainActor.run {
            let store = TranscriptStore()
            store.liveSource = .mic
            store.clear()
            #expect(store.liveSource == nil)
        }
    }
}
