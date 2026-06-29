// Tests/FrenchLiveTests/SessionManagerTests.swift
import Testing
import Foundation
@testable import FrenchLiveCore

@Suite struct SessionManagerTests {

    @Test func testInitialStateIsIdle() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let manager = SessionManager(store: store, translator: translator)
            #expect(manager.state == .idle)
        }
    }

    @Test func testDefaultSourceIsBoth() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let manager = SessionManager(store: store, translator: translator)
            #expect(manager.selectedSource == .both)
        }
    }

    @Test func testElapsedSecondsStartsAtZero() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let manager = SessionManager(store: store, translator: translator)
            #expect(manager.elapsedSeconds == 0)
        }
    }

    @Test func testStartWhenAlreadyRecordingIsNoOp() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let m = SessionManager(store: store, translator: translator)
            m.testSetState(.recording)
            return m
        }
        let stateBefore = await MainActor.run { manager.state }
        await manager.start()
        let stateAfter = await MainActor.run { manager.state }
        #expect(stateAfter == stateBefore)
    }

    @Test func testStopWhenIdleIsNoOp() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            return SessionManager(store: store, translator: translator)
        }
        #expect(await MainActor.run { manager.state } == .idle)
        await manager.stop()
        #expect(await MainActor.run { manager.state } == .idle)
    }
}
