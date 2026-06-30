import Testing
@testable import FrenchLiveCore

@Suite struct SettingsStoreTests {

    @Test func testSourceLanguagesNonEmpty() {
        #expect(!SettingsStore.sourceLanguages.isEmpty)
    }

    @Test func testTargetLanguagesNonEmpty() {
        #expect(!SettingsStore.targetLanguages.isEmpty)
    }

    @Test func testSourceLanguagesContainsFrench() {
        #expect(SettingsStore.sourceLanguages.contains { $0.code == "fr-FR" })
    }

    @Test func testTargetLanguagesContainsEnglish() {
        #expect(SettingsStore.targetLanguages.contains { $0.code == "en" })
    }

    @Test func testSourceLanguagesHaveNonEmptyLabels() {
        for lang in SettingsStore.sourceLanguages {
            #expect(!lang.label.isEmpty)
        }
    }

    @Test func testTargetLanguagesHaveNonEmptyLabels() {
        for lang in SettingsStore.targetLanguages {
            #expect(!lang.label.isEmpty)
        }
    }
}
