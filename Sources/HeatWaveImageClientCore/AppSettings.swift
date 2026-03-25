import Foundation
import Observation

@MainActor
@Observable
public final class AppSettings {
    public static let defaultBaseURLString = "http://127.0.0.1:8000"
    public static let storageKey = "heatwave.backend.base-url"
    public static let runStampEnvironmentKey = "HEATWAVE_BUILD_STAMP"
    public static let launchSourceEnvironmentKey = "HEATWAVE_LAUNCH_SOURCE"
    public static let promptLogPathEnvironmentKey = "HEATWAVE_PROMPT_LOG_PATH"

    public var baseURLString: String {
        didSet {
            defaults.set(baseURLString, forKey: Self.storageKey)
        }
    }

    public let runStamp: String
    public let launchSource: String
    public let promptDiagnosticsLogPath: String?

    private let defaults: UserDefaults
    private let environment: [String: String]

    public init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.environment = environment

        if let override = Self.trimmedNonEmpty(environment["HEATWAVE_API_BASE_URL"]) {
            self.baseURLString = override
        } else {
            self.baseURLString = defaults.string(forKey: Self.storageKey) ?? Self.defaultBaseURLString
        }
        self.runStamp = Self.trimmedNonEmpty(environment[Self.runStampEnvironmentKey]) ?? Self.makeFallbackRunStamp()
        self.launchSource = Self.trimmedNonEmpty(environment[Self.launchSourceEnvironmentKey]) ?? "direct-swift-run"
        self.promptDiagnosticsLogPath = Self.trimmedNonEmpty(environment[Self.promptLogPathEnvironmentKey])
    }

    public var resolvedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else {
            return nil
        }
        guard url.host != nil else {
            return nil
        }
        return url
    }

    public var validationMessage: String? {
        resolvedBaseURL == nil ? "Enter a valid backend URL including the scheme and host." : nil
    }

    public func resetToDefault() {
        let fallback = Self.trimmedNonEmpty(environment["HEATWAVE_API_BASE_URL"]) ?? Self.defaultBaseURLString
        baseURLString = fallback
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func makeFallbackRunStamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        return "direct-\(timestamp)"
    }
}
