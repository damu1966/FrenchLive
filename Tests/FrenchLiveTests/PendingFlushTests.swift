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
        let pending = PendingFlush(id: UUID(), text: "Bonjour le monde", english: "Hello world", entryID: nil)
        let result = resolveFlush(pending)
        guard case .ready(let english) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(english == "Hello world")
    }

    @Test func testUnresolvedEnglishReturnsPendingText() {
        let pending = PendingFlush(id: UUID(), text: "Bonjour le monde", english: nil, entryID: nil)
        let result = resolveFlush(pending)
        guard case .pendingText = result else {
            Issue.record("expected .pendingText, got \(result)")
            return
        }
    }
}
