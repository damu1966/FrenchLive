// Tests/FrenchLiveTests/PendingFlushTests.swift
import Testing
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
}
