import Testing
@testable import FrenchLiveCore

@Suite struct TranslatorTests {

    @Test func testEmptyTextReturnsEmpty() async {
        let translator = Translator()
        let result = await translator.translate("", from: "fr-FR", to: "en")
        #expect(result == "")
    }

    @Test func testWhitespaceTextReturnsEmpty() async {
        let translator = Translator()
        let result = await translator.translate("   ", from: "fr-FR", to: "en")
        #expect(result == "")
    }
}
