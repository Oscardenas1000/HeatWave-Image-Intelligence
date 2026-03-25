import Foundation
import XCTest
@testable import HeatWaveImageClientCore

@MainActor
final class AppSettingsTests: XCTestCase {
    func testLaunchEnvironmentOverridesBaseURLAndRuntimeMetadata() {
        let defaults = makeDefaults()
        defaults.set("http://persisted.example:9000", forKey: AppSettings.storageKey)

        let settings = AppSettings(
            defaults: defaults,
            environment: [
                "HEATWAVE_API_BASE_URL": "http://127.0.0.1:8123",
                AppSettings.runStampEnvironmentKey: "launcher-mock-20260324T180000Z-abc1234",
                AppSettings.launchSourceEnvironmentKey: "run_heatwave_image_intelligence.command --mock-backend",
                AppSettings.promptLogPathEnvironmentKey: "/tmp/heatwave-prompt.log",
            ]
        )

        XCTAssertEqual(settings.baseURLString, "http://127.0.0.1:8123")
        XCTAssertEqual(settings.resolvedBaseURL?.absoluteString, "http://127.0.0.1:8123")
        XCTAssertEqual(settings.runStamp, "launcher-mock-20260324T180000Z-abc1234")
        XCTAssertEqual(settings.launchSource, "run_heatwave_image_intelligence.command --mock-backend")
        XCTAssertEqual(settings.promptDiagnosticsLogPath, "/tmp/heatwave-prompt.log")
    }

    func testDefaultsAndFallbackRuntimeMetadataAreUsedWithoutEnvironment() {
        let defaults = makeDefaults()
        defaults.set("http://persisted.example:9000", forKey: AppSettings.storageKey)

        let settings = AppSettings(defaults: defaults, environment: [:])

        XCTAssertEqual(settings.baseURLString, "http://persisted.example:9000")
        XCTAssertEqual(settings.launchSource, "direct-swift-run")
        XCTAssertTrue(settings.runStamp.hasPrefix("direct-"))
        XCTAssertNil(settings.promptDiagnosticsLogPath)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
