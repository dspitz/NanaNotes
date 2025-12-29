import Foundation

struct AppConfiguration {
    static var openAIAPIKey: String {
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }

        if let path = Bundle.main.path(forResource: "Config", ofType: "xcconfig"),
           let contents = try? String(contentsOfFile: path),
           let keyLine = contents.split(separator: "\n").first(where: { $0.contains("OPENAI_API_KEY") }) {
            let parts = keyLine.split(separator: "=")
            if parts.count == 2 {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        return ""
    }

    static var isOpenAIConfigured: Bool {
        !openAIAPIKey.isEmpty
    }
}
