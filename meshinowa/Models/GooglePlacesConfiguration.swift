import Foundation
import GooglePlacesSwift
import GoogleMaps

struct GooglePlacesConfiguration {
    let apiKey: String

    enum ConfigurationError: LocalizedError {
        case invalidKey
        var errorDescription: String? { "Google PlacesのiOS用キーが正しくありません。" }
    }

    static func load(info: [String: Any]) throws -> GooglePlacesConfiguration? {
        let key = (info["GooglePlacesAPIKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return nil }
        guard key.hasPrefix("AIza"), key.count == 39,
              key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              !key.contains("REPLACE_ME") else { throw ConfigurationError.invalidKey }
        return GooglePlacesConfiguration(apiKey: key)
    }
}

@MainActor
enum GooglePlacesService {
    private(set) static var isConfigured = false
    private(set) static var isMapConfigured = false

    static func configure(bundle: Bundle = .main) {
        guard !isConfigured,
              let configuration = try? GooglePlacesConfiguration.load(info: bundle.infoDictionary ?? [:]) else { return }
        isMapConfigured = GMSServices.provideAPIKey(configuration.apiKey)
        isConfigured = PlacesClient.provideAPIKey(configuration.apiKey)
    }
}
