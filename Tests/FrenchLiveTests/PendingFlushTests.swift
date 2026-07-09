// Tests/FrenchLiveTests/PendingFlushTests.swift
import Testing
import Foundation
@testable import FrenchLiveCore

@Suite struct PendingFlushTests {

    @Test func testNoPendingFlushReturnsNone() {
        let result = resolveFlush(nil, finalText: "Bonjour le monde")
        guard case .none = result else {
            Issue.record("expected .none, got \(result)")
            return
        }
    }

    @Test func testMismatchedTextReturnsNone() {
        let pending = PendingFlush(text: "Bonjour le monde", english: "Hello world", entryID: nil)
        let result = resolveFlush(pending, finalText: "Bonjour le monde entier")
        guard case .none = result else {
            Issue.record("expected .none, got \(result)")
            return
        }
    }

    @Test func testMatchedTextWithResolvedEnglishReturnsReady() {
        let pending = PendingFlush(text: "Bonjour le monde", english: "Hello world", entryID: nil)
        let result = resolveFlush(pending, finalText: "Bonjour le monde")
        guard case .ready(let english) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(english == "Hello world")
    }

    @Test func testMatchedTextWithoutResolvedEnglishReturnsPendingText() {
        let pending = PendingFlush(text: "Bonjour le monde", english: nil, entryID: nil)
        let result = resolveFlush(pending, finalText: "Bonjour le monde")
        guard case .pendingText = result else {
            Issue.record("expected .pendingText, got \(result)")
            return
        }
    }

    @Test func testMatchingFlushIndexFindsUnclaimedMatch() {
        let queue = [PendingFlush(text: "Bonjour", english: nil, entryID: nil)]
        let index = matchingFlushIndex(in: queue, finalText: "Bonjour")
        #expect(index == 0)
    }

    @Test func testMatchingFlushIndexReturnsNilOnTextMismatch() {
        let queue = [PendingFlush(text: "Bonjour", english: nil, entryID: nil)]
        let index = matchingFlushIndex(in: queue, finalText: "Bonsoir")
        #expect(index == nil)
    }

    @Test func testMatchingFlushIndexSkipsAlreadyClaimedEntry() {
        // Regression test: a repeated identical phrase must not steal a pending
        // flush that an earlier final has already claimed (entryID != nil) —
        // doing so silently starves the earlier entry of its translation forever.
        let claimedEntryID = UUID()
        let queue = [PendingFlush(text: "Merci beaucoup", english: nil, entryID: claimedEntryID)]
        let index = matchingFlushIndex(in: queue, finalText: "Merci beaucoup")
        #expect(index == nil)
    }

    @Test func testMatchingFlushIndexFindsUnclaimedMatchAfterClaimedDuplicate() {
        // Two queue entries share identical text; the first is already claimed.
        // The second (unclaimed) match must still be found for the new final.
        let claimedEntryID = UUID()
        let queue = [
            PendingFlush(text: "Merci beaucoup", english: nil, entryID: claimedEntryID),
            PendingFlush(text: "Merci beaucoup", english: nil, entryID: nil),
        ]
        let index = matchingFlushIndex(in: queue, finalText: "Merci beaucoup")
        #expect(index == 1)
    }
}
