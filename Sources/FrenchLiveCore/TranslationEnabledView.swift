// Sources/FrenchLiveCore/TranslationEnabledView.swift
import SwiftUI
import Translation

@available(macOS 15.0, *)
struct TranslationEnabledView<Content: View>: View {
    let content: Content
    let translator: Translator

    @State private var config = TranslationSession.Configuration(
        source: Locale.Language(identifier: "fr"),
        target: Locale.Language(identifier: "en")
    )

    var body: some View {
        content
            .translationTask(config) { session in
                await translator.setSession(session)
            }
    }
}
