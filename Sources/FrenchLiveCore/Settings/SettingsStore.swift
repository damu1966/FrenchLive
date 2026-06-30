import Foundation

@MainActor
final class SettingsStore: ObservableObject {

    struct LanguageOption: Identifiable {
        var id: String { code }
        let code: String
        let label: String
    }

    static let sourceLanguages: [LanguageOption] = [
        LanguageOption(code: "fr-FR", label: "French"),
        LanguageOption(code: "es-ES", label: "Spanish"),
        LanguageOption(code: "it-IT", label: "Italian"),
        LanguageOption(code: "de-DE", label: "German"),
        LanguageOption(code: "pt-BR", label: "Portuguese"),
    ]

    static let targetLanguages: [LanguageOption] = [
        LanguageOption(code: "en", label: "English"),
        LanguageOption(code: "es", label: "Spanish"),
        LanguageOption(code: "fr", label: "French"),
        LanguageOption(code: "de", label: "German"),
        LanguageOption(code: "it", label: "Italian"),
        LanguageOption(code: "pt", label: "Portuguese"),
    ]

    @Published var sourceLanguage: String {
        didSet { UserDefaults.standard.set(sourceLanguage, forKey: Keys.sourceLanguage) }
    }
    @Published var targetLanguage: String {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: Keys.targetLanguage) }
    }
    @Published var outputFolderPath: String {
        didSet { UserDefaults.standard.set(outputFolderPath, forKey: Keys.outputFolderPath) }
    }
    @Published var autoSaveInterval: Int {
        didSet { UserDefaults.standard.set(autoSaveInterval, forKey: Keys.autoSaveInterval) }
    }

    private enum Keys {
        static let sourceLanguage    = "sourceLanguage"
        static let targetLanguage    = "targetLanguage"
        static let outputFolderPath  = "outputFolderPath"
        static let autoSaveInterval  = "autoSaveInterval"
    }

    init() {
        let ud = UserDefaults.standard
        let defaultFolder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrenchTranscripts").path
        sourceLanguage   = ud.string(forKey: Keys.sourceLanguage)   ?? "fr-FR"
        targetLanguage   = ud.string(forKey: Keys.targetLanguage)   ?? "en"
        outputFolderPath = ud.string(forKey: Keys.outputFolderPath) ?? defaultFolder
        autoSaveInterval = ud.object(forKey: Keys.autoSaveInterval) as? Int ?? 0
    }
}
