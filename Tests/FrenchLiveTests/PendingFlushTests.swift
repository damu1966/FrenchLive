// Tests/FrenchLiveTests/PendingFlushTests.swift
import Testing
import Foundation
@testable import FrenchLiveCore

@Suite struct PendingFlushTests {

    @Test func testNoPendingFlushReturnsNone() {
        let result = resolveFlush(nil)
        guard case .none = result else {
            Issue.record("expected .none, got \(result)")
            return
        }
    }

    @Test func testResolvedEnglishReturnsReady() {
        let pending = PendingFlush(text: "Bonjour le monde", english: "Hello world", entryID: nil)
        let result = resolveFlush(pending)
        guard case .ready(let english) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(english == "Hello world")
    }

    @Test func testUnresolvedEnglishReturnsPendingText() {
        let pending = PendingFlush(text: "Bonjour le monde", english: nil, entryID: nil)
        let result = resolveFlush(pending)
        guard case .pendingText = result else {
            Issue.record("expected .pendingText, got \(result)")
            return
        }
    }

    @Test func testOldestUnclaimedFlushIndexOnEmptyQueueReturnsNil() {
        let index = oldestUnclaimedFlushIndex(in: [])
        #expect(index == nil)
    }

    @Test func testOldestUnclaimedFlushIndexFindsSoleEntry() {
        let queue = [PendingFlush(text: "Bonjour", english: nil, entryID: nil)]
        let index = oldestUnclaimedFlushIndex(in: queue)
        #expect(index == 0)
    }

    @Test func testOldestUnclaimedFlushIndexIgnoresTextEntirely() {
        // The final text SFSpeechRecognizer settles on almost always differs
        // slightly from the snapshot taken at flush time (a trailing word is
        // often still being finalized) — so matching must be purely positional,
        // not text-based. This is the fix for a real bug: text-matching caused
        // near-total match failures in production, silently doubling network
        // calls and leaking an ever-growing queue of orphaned entries.
        let queue = [PendingFlush(text: "Bonjour tout le", english: nil, entryID: nil)]
        let index = oldestUnclaimedFlushIndex(in: queue)
        #expect(index == 0)
    }

    @Test func testOldestUnclaimedFlushIndexSkipsAlreadyClaimedEntries() {
        // Regression test: a flush already claimed by an earlier final
        // (entryID != nil) must not be claimed again by a later final —
        // doing so would silently starve the earlier entry of its
        // translation forever.
        let claimedEntryID = UUID()
        let queue = [
            PendingFlush(text: "Merci beaucoup", english: nil, entryID: claimedEntryID),
            PendingFlush(text: "Autre chose", english: nil, entryID: nil),
        ]
        let index = oldestUnclaimedFlushIndex(in: queue)
        #expect(index == 1)
    }

    @Test func testOldestUnclaimedFlushIndexReturnsNilWhenAllClaimed() {
        let queue = [PendingFlush(text: "Merci beaucoup", english: "Thank you", entryID: UUID())]
        let index = oldestUnclaimedFlushIndex(in: queue)
        #expect(index == nil)
    }
}
