// Sources/FrenchLiveCore/Translation/Translator.swift
import Foundation

#if canImport(Translation)
import Translation
#endif

actor Translator {
    private var _session: Any?

    // Reused across all calls — JSONDecoder allocation is not free.
    private static let jsonDecoder = JSONDecoder()

    // Short timeout: MyMemory is best-effort; show "[translation unavailable]"
    // quickly rather than leaving the entry showing "…" for 60 seconds.
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    @available(macOS 15.0, *)
    func setSession(_ session: TranslationSession) {
        _session = session
    }

    func translate(_ text: String, from sourceLanguage: String = "fr-FR", to targetLanguage: String = "en") async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if #available(macOS 15.0, *), let session = _session as? TranslationSession {
            let result = await translateWithApple(text, session: session)
            // Apple session not yet warmed up or returned empty — fall through to MyMemory.
            if !result.isEmpty && result != "[translation unavailable]" {
                return result
            }
            print("FrenchLive: Apple translation returned '\(result)', falling back to MyMemory")
        }
        return await translateWithMyMemory(text, from: sourceLanguage, to: targetLanguage)
    }

    @available(macOS 15.0, *)
    private func translateWithApple(_ text: String, session: TranslationSession) async -> String {
        do {
            let response = try await session.translate(text)
            let result = response.targetText
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "[translation unavailable]"
            }
            return result
        } catch {
            print("FrenchLive: Apple translation error: \(error)")
            return "[translation unavailable]"
        }
    }

    private func translateWithMyMemory(_ text: String, from sourceLanguage: String, to targetLanguage: String) async -> String {
        let sourceLangCode = sourceLanguage.components(separatedBy: "-").first ?? "fr"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(sourceLangCode)|\(targetLanguage)")
        else { return "[translation unavailable]" }

        do {
            let (data, _) = try await Self.urlSession.data(from: url)
            let decoded = try Self.jsonDecoder.decode(MyMemoryResponse.self, from: data)
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
