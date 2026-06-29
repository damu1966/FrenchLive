// Sources/FrenchLiveCore/Translation/Translator.swift
import Foundation

#if canImport(Translation)
import Translation
#endif

actor Translator {
    // Stored as Any? because @available cannot annotate stored properties
    private var _session: Any?

    @available(macOS 15.0, *)
    func setSession(_ session: TranslationSession) {
        _session = session
    }

    func translate(_ text: String) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if #available(macOS 15.0, *), let session = _session as? TranslationSession {
            return await translateWithApple(text, session: session)
        }
        return await translateWithMyMemory(text)
    }

    @available(macOS 15.0, *)
    private func translateWithApple(_ text: String, session: TranslationSession) async -> String {
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            return "[translation unavailable]"
        }
    }

    private func translateWithMyMemory(_ text: String) async -> String {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=fr|en")
        else { return "[translation unavailable]" }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            return decoded.responseData.translatedText
        } catch {
            return "[translation unavailable]"
        }
    }
}

private struct MyMemoryResponse: Decodable {
    let responseData: ResponseData
    struct ResponseData: Decodable {
        let translatedText: String
    }
}
