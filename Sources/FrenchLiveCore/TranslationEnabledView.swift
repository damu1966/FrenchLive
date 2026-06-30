// Sources/FrenchLiveCore/TranslationEnabledView.swift
import SwiftUI
import Translation

@available(macOS 15.0, *)
struct TranslationEnabledView<Content: View>: View {
    let content: Content
    let translator: Translator
    let sourceLanguage: String
    let targetLanguage: String

    @State private var config: TranslationSession.Configuration

    init(content: Content, translator: Translator, sourceLanguage: String, targetLanguage: String) {
        self.content = content
        self.translator = translator
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        let srcCode = sourceLanguage.components(separatedBy: "-").first ?? "fr"
        _config = State(initialValue: TranslationSession.Configuration(
            source: Locale.Language(identifier: srcCode),
            target: Locale.Language(identifier: targetLanguage)
        ))
    }

    var body: some View {
        content
            .translationTask(config) { session in
                await translator.setSession(session)
            }
            .onChange(of: sourceLanguage) { _, newValue in
                let srcCode = newValue.components(separatedBy: "-").first ?? "fr"
                config = TranslationSession.Configuration(
                    source: Locale.Language(identifier: srcCode),
                    target: Locale.Language(identifier: targetLanguage)
                )
            }
            .onChange(of: targetLanguage) { _, newValue in
                let srcCode = sourceLanguage.components(separatedBy: "-").first ?? "fr"
                config = TranslationSession.Configuration(
                    source: Locale.Language(identifier: srcCode),
                    target: Locale.Language(identifier: newValue)
                )
            }
    }
}
