// Sources/FrenchLiveCore/Translation/Translator.swift
import Foundation

#if canImport(Translation)
import Translation
#endif

actor Translator {
    private var _session: Any?

    private static let jsonDecoder = JSONDecoder()
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    @available(macOS 15.0, *)
    func setSession(_ session: TranslationSession) {
        _session = session
    }

    // GCD-based translation — zero Swift Concurrency, works on macOS 26 where
    // actor executor scheduling is broken. Completion always called on main thread.
    nonisolated func translateGCD(_ text: String,
                                  from sourceLanguage: String = "fr-FR",
                                  to targetLanguage: String = "en",
                                  completion: @escaping (String) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(""); return }

        let srcCode = sourceLanguage.components(separatedBy: "-").first ?? "fr"
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(srcCode)|\(targetLanguage)")
        else { DispatchQueue.main.async { completion("[translation unavailable]") }; return }

        Self.urlSession.dataTask(with: url) { data, _, _ in
            let english: String
            if let data,
               let decoded = try? Self.jsonDecoder.decode(MyMemoryResponse.self, from: data),
               !decoded.responseData.translatedText.isEmpty {
                english = decoded.responseData.translatedText
            } else {
                english = "[translation unavailable]"
            }
            DispatchQueue.main.async { completion(english) }
        }.resume()
    }

    func translate(_ text: String, from sourceLanguage: String = "fr-FR", to targetLanguage: String = "en") async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if #available(macOS 15.0, *), let session = _session as? TranslationSession {
            let result = await translateWithApple(text, session: session)
            // translateWithApple returns "" on timeout or hard error so we can fall
            // through to MyMemory without hammering its quota on every throw.
            if !result.isEmpty { return result }
            print("FrenchLive: Apple timed out or errored — falling back to MyMemory")
        }
        return await translateWithMyMemory(text, from: sourceLanguage, to: targetLanguage)
    }

    @available(macOS 15.0, *)
    private func translateWithApple(_ text: String, session: TranslationSession) async -> String {
        // session.translate() can hang indefinitely on macOS 26 when the model is
        // loading or the session is in a bad state. Race it against an 8-second
        // deadline so the entry always gets an English value.
        do {
            let response = try await withThrowingTaskGroup(of: TranslationSession.Response.self) { group in
                group.addTask { try await session.translate(text) }
                group.addTask {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                    struct Timeout: Error {}
                    throw Timeout()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let result = response.targetText
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("FrenchLive: Apple translation returned empty string")
                return ""   // signal caller to try MyMemory
            }
            return result
        } catch {
            print("FrenchLive: Apple translation error/timeout: \(error)")
            return ""       // signal caller to try MyMemory
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
