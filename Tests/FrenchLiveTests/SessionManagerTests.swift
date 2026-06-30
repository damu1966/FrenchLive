// Tests/FrenchLiveTests/SessionManagerTests.swift
import Testing
import Foundation
@testable import FrenchLiveCore

@Suite struct SessionManagerTests {

    @Test func testInitialStateIsIdle() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let manager = SessionManager(store: store, translator: translator, settings: settings)
            #expect(manager.state == .idle)
        }
    }

    @Test func testDefaultSourceIsBoth() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let manager = SessionManager(store: store, translator: translator, settings: settings)
            #expect(manager.selectedSource == .both)
        }
    }

    @Test func testElapsedSecondsStartsAtZero() async {
        await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let manager = SessionManager(store: store, translator: translator, settings: settings)
            #expect(manager.elapsedSeconds == 0)
        }
    }

    @Test func testStartWhenAlreadyRecordingIsNoOp() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let m = SessionManager(store: store, translator: translator, settings: settings)
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
            let settings = SettingsStore()
            return SessionManager(store: store, translator: translator, settings: settings)
        }
        #expect(await MainActor.run { manager.state } == .idle)
        await manager.stop()
        #expect(await MainActor.run { manager.state } == .idle)
    }

    @Test func testPauseFromRecordingTransitionsToPaused() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let m = SessionManager(store: store, translator: translator, settings: settings)
            m.testSetState(.recording)
            return m
        }
        await manager.pause()
        let state = await MainActor.run { manager.state }
        #expect(state == .paused)
    }

    @Test func testPauseWhenIdleIsNoOp() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            return SessionManager(store: store, translator: translator, settings: settings)
        }
        await manager.pause()
        let state = await MainActor.run { manager.state }
        #expect(state == .idle)
    }

    @Test func testResumeFromPausedTransitionsToRecording() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let m = SessionManager(store: store, translator: translator, settings: settings)
            m.testSetState(.paused)
            return m
        }
        await manager.resume()
        let state = await MainActor.run { manager.state }
        #expect(state == .recording)
    }

    @Test func testResumeWhenIdleIsNoOp() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            return SessionManager(store: store, translator: translator, settings: settings)
        }
        await manager.resume()
        let state = await MainActor.run { manager.state }
        #expect(state == .idle)
    }

    @Test func testStopFromPausedTransitionsToIdle() async {
        let manager: SessionManager = await MainActor.run {
            let store = TranscriptStore()
            let translator = Translator()
            let settings = SettingsStore()
            let m = SessionManager(store: store, translator: translator, settings: settings)
            m.testSetState(.paused)
            return m
        }
        await manager.stop()
        let state = await MainActor.run { manager.state }
        #expect(state == .idle)
    }
}
