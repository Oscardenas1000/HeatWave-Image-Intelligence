import Foundation
import XCTest

final class HeatWaveImageIntelligenceMacUITests: XCTestCase {
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    override func tearDownWithError() throws {
        app?.terminate()
    }

    @MainActor
    func testLaunchUploadSelectAndGenerateInsight() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureImageURL = repoRoot.appendingPathComponent("BluebonnetLonghorn.png")

        let app = XCUIApplication()
        self.app = app
        app.launchEnvironment["HEATWAVE_API_BASE_URL"] = "http://127.0.0.1:8000"
        app.launchEnvironment["HEATWAVE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["HEATWAVE_UI_TEST_IMAGE_PATH"] = fixtureImageURL.path
        app.launchEnvironment["HEATWAVE_UI_TEST_AUTO_IMPORT"] = "1"
        app.launchEnvironment["HEATWAVE_UI_TEST_UPLOAD_NAME"] = "UI Smoke Upload"
        app.launch()

        let uploadButton = app.buttons.matching(identifier: "upload_button").firstMatch
        XCTAssertTrue(uploadButton.waitForExistence(timeout: 10))
        uploadButton.click()

        let saveButton = app.buttons.matching(identifier: "save_upload_button").firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))

        let generateDescriptionButton = app.buttons
            .matching(identifier: "upload_generate_description_button")
            .firstMatch
        XCTAssertTrue(generateDescriptionButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilEnabled(generateDescriptionButton, timeout: 5))
        generateDescriptionButton.click()

        XCTAssertTrue(waitUntilEnabled(saveButton, timeout: 5))
        saveButton.click()

        let detailTitle = app.staticTexts["UI Smoke Upload"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 10))

        let promptEditor = app.textViews.matching(identifier: "insight_prompt_editor").firstMatch
        XCTAssertTrue(promptEditor.waitForExistence(timeout: 10))
        promptEditor.click()
        promptEditor.typeText("Describe the uploaded image.")

        let generateButton = app.buttons.matching(identifier: "generate_insight_button").firstMatch
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilEnabled(generateButton, timeout: 5))
        generateButton.click()

        XCTAssertTrue(app.staticTexts["Smoke insight for uploaded image."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Detected: English (EN)"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["Main subject: The uploaded fixture renders correctly."].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.staticTexts["In short, markdown structure should remain readable."].waitForExistence(timeout: 10)
        )
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
