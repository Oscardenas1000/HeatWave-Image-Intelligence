import Foundation
import XCTest
@testable import HeatWaveImageClientCore

@MainActor
final class AppViewModelTests: XCTestCase {
    func testLoadInitialDataSelectsFirstRecordLoadsDetailAndSeedsDescriptionDraft() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.appInfoResult = .success(AppInfo(aiModelId: "gemini", recordCount: 2))
        client.fetchImagesResults = [
            .success([
                makeSummary(id: 2, name: "Newest"),
                makeSummary(id: 1, name: "Older"),
            ]),
        ]
        client.fetchImageResultByID = [
            2: .success(makeDetail(id: 2, name: "Newest", description: "Newest description.")),
            1: .success(makeDetail(id: 1, name: "Older", description: "Older description.")),
        ]
        client.fetchImageContentResultByID = [
            2: .success(Data([0x01])),
            1: .success(Data([0x02])),
        ]

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client },
            searchDebounceNanoseconds: 5_000_000
        )

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.selectedRecordID, 2)
        XCTAssertEqual(viewModel.selectedDetail?.imageName, "Newest")
        XCTAssertEqual(viewModel.appInfo?.recordCount, 2)
        XCTAssertEqual(viewModel.descriptionDraft, "Newest description.")
    }

    func testSearchRefreshFallsBackToFirstVisibleRecord() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.appInfoResult = .success(AppInfo(aiModelId: "gemini", recordCount: 2))
        client.fetchImagesResults = [
            .success([
                makeSummary(id: 2, name: "Truck"),
                makeSummary(id: 1, name: "Barn"),
            ]),
            .success([
                makeSummary(id: 1, name: "Barn"),
            ]),
        ]
        client.fetchImageResultByID = [
            2: .success(makeDetail(id: 2, name: "Truck", description: "Truck description.")),
            1: .success(makeDetail(id: 1, name: "Barn", description: "Barn description.")),
        ]
        client.fetchImageContentResultByID = [
            2: .success(Data([0x01])),
            1: .success(Data([0x02])),
        ]

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client },
            searchDebounceNanoseconds: 5_000_000
        )

        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.selectedRecordID, 2)

        viewModel.searchQuery = "Barn"
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(viewModel.selectedRecordID, 1)
        XCTAssertEqual(client.fetchImagesQueries, ["", "Barn"])
    }

    func testUploadRefreshesLibrarySelectsNewRecordAndSendsDescription() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.appInfoResult = .success(AppInfo(aiModelId: "gemini", recordCount: 2))
        client.fetchImagesResults = [
            .success([
                makeSummary(id: 1, name: "Existing"),
            ]),
            .success([
                makeSummary(id: 2, name: "New Upload"),
                makeSummary(id: 1, name: "Existing"),
            ]),
        ]
        client.fetchImageResultByID = [
            1: .success(makeDetail(id: 1, name: "Existing", description: "Existing description.")),
            2: .success(makeDetail(id: 2, name: "New Upload", description: "New upload description.")),
        ]
        client.fetchImageContentResultByID = [
            1: .success(Data([0x01])),
            2: .success(Data([0x02])),
        ]
        client.uploadResult = .success(
            makeDetail(id: 2, name: "New Upload", description: "New upload description.")
        )

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client },
            searchDebounceNanoseconds: 5_000_000
        )

        await viewModel.loadIfNeeded()
        _ = try await viewModel.uploadImage(
            name: "New Upload",
            filename: "upload.png",
            mimeType: "image/png",
            data: Data([0x0A]),
            description: "New upload description."
        )

        XCTAssertEqual(viewModel.selectedRecordID, 2)
        XCTAssertEqual(viewModel.selectedDetail?.imageName, "New Upload")
        XCTAssertEqual(viewModel.bannerMessage, "Added \"New Upload\" to the library.")
        XCTAssertEqual(client.lastUploadDescription, "New upload description.")
    }

    func testGenerateUploadDescriptionReturnsGeneratedText() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.generateUploadDescriptionResult = .success(
            GeneratedDescriptionResponse(
                description: "Generated upload description.",
                detectedLanguage: "en"
            )
        )

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client }
        )

        let response = try await viewModel.generateUploadDescription(
            filename: "upload.png",
            mimeType: "image/png",
            data: Data([0x0A]),
            prompt: "Focus on the truck"
        )

        XCTAssertEqual(response.description, "Generated upload description.")
        XCTAssertEqual(response.detectedLanguage, "en")
        XCTAssertEqual(client.lastGenerateUploadPrompt, "Focus on the truck")
    }

    func testSaveDescriptionUpdatesSelectedDetailState() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.appInfoResult = .success(AppInfo(aiModelId: "gemini", recordCount: 1))
        client.fetchImagesResults = [
            .success([
                makeSummary(id: 1, name: "Truck"),
            ]),
        ]
        client.fetchImageResultByID = [
            1: .success(makeDetail(id: 1, name: "Truck", description: "Existing description.")),
        ]
        client.fetchImageContentResultByID = [
            1: .success(Data([0x01])),
        ]
        client.updateDescriptionResult = .success(
            makeDetail(id: 1, name: "Truck", description: "Updated reusable description.")
        )

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client },
            searchDebounceNanoseconds: 5_000_000
        )

        await viewModel.loadIfNeeded()
        viewModel.descriptionDraft = "Updated reusable description."
        await viewModel.saveDescription()

        XCTAssertEqual(viewModel.selectedDetail?.description, "Updated reusable description.")
        XCTAssertEqual(viewModel.descriptionDraft, "Updated reusable description.")
        XCTAssertNil(viewModel.descriptionErrorMessage)
        XCTAssertEqual(client.lastUpdatedDescription?.0, 1)
        XCTAssertEqual(client.lastUpdatedDescription?.1, "Updated reusable description.")
    }

    func testGenerateDescriptionUpdatesSelectedDetailState() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.appInfoResult = .success(AppInfo(aiModelId: "gemini", recordCount: 1))
        client.fetchImagesResults = [
            .success([
                makeSummary(id: 1, name: "Truck"),
            ]),
        ]
        client.fetchImageResultByID = [
            1: .success(makeDetail(id: 1, name: "Truck", description: "Existing description.")),
        ]
        client.fetchImageContentResultByID = [
            1: .success(Data([0x01])),
        ]
        client.generateDescriptionResult = .success(
            makeDetail(id: 1, name: "Truck", description: "Generated description guided by: Focus on the truck")
        )

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client },
            searchDebounceNanoseconds: 5_000_000
        )

        await viewModel.loadIfNeeded()
        viewModel.descriptionGenerationPrompt = "Focus on the truck"
        await viewModel.generateDescription()

        XCTAssertEqual(
            viewModel.selectedDetail?.description,
            "Generated description guided by: Focus on the truck"
        )
        XCTAssertEqual(client.lastGeneratedDescriptionRequest?.0, 1)
        XCTAssertEqual(client.lastGeneratedDescriptionRequest?.1, "Focus on the truck")
        XCTAssertNil(viewModel.descriptionErrorMessage)
    }

    func testGenerateInsightUpdatesState() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.appInfoResult = .success(AppInfo(aiModelId: "gemini", recordCount: 1))
        client.fetchImagesResults = [
            .success([
                makeSummary(id: 1, name: "Truck"),
            ]),
        ]
        client.fetchImageResultByID = [
            1: .success(makeDetail(id: 1, name: "Truck", description: "Truck description.")),
        ]
        client.fetchImageContentResultByID = [
            1: .success(Data([0x01])),
        ]
        client.insightResult = .success(
            InsightResponse(
                text: "The truck is parked under clear skies.",
                detectedLanguage: "en"
            )
        )

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client },
            searchDebounceNanoseconds: 5_000_000
        )

        await viewModel.loadIfNeeded()
        viewModel.insightPrompt = "Describe it"
        await viewModel.generateInsight()

        XCTAssertEqual(viewModel.insightText, "The truck is parked under clear skies.")
        XCTAssertEqual(viewModel.insightDetectedLanguage, "en")
        XCTAssertNil(viewModel.insightErrorMessage)
    }

    func testGenerateInsightSurfacesErrorState() async throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults, environment: [:])
        let client = MockClient()
        client.appInfoResult = .success(AppInfo(aiModelId: "gemini", recordCount: 1))
        client.fetchImagesResults = [
            .success([
                makeSummary(id: 1, name: "Truck"),
            ]),
        ]
        client.fetchImageResultByID = [
            1: .success(makeDetail(id: 1, name: "Truck", description: "Truck description.")),
        ]
        client.fetchImageContentResultByID = [
            1: .success(Data([0x01])),
        ]
        client.insightResult = .failure(
            APIClientError.server(statusCode: 500, message: "HeatWave did not return a response.")
        )

        let viewModel = AppViewModel(
            settings: settings,
            clientFactory: { _ in client },
            searchDebounceNanoseconds: 5_000_000
        )

        await viewModel.loadIfNeeded()
        viewModel.insightPrompt = "Describe it"
        await viewModel.generateInsight()

        XCTAssertNil(viewModel.insightText)
        XCTAssertNil(viewModel.insightDetectedLanguage)
        XCTAssertEqual(viewModel.insightErrorMessage, "HeatWave did not return a response.")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "HeatWaveImageClientCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSummary(id: Int, name: String) -> ImageSummary {
        ImageSummary(
            id: id,
            imageName: name,
            originalFilename: "\(name).png",
            mimeType: "image/png",
            base64Length: 128,
            createdAt: Date(timeIntervalSince1970: TimeInterval(id)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(id))
        )
    }

    private func makeDetail(id: Int, name: String, description: String) -> ImageDetail {
        ImageDetail(
            id: id,
            imageName: name,
            originalFilename: "\(name).png",
            mimeType: "image/png",
            description: description,
            base64Length: 128,
            createdAt: Date(timeIntervalSince1970: TimeInterval(id)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(id))
        )
    }
}

private final class MockClient: HeatWaveAPIClientProtocol, @unchecked Sendable {
    var appInfoResult: Result<AppInfo, Error> = .failure(APIClientError.invalidResponse)
    var fetchImagesResults: [Result<[ImageSummary], Error>] = []
    var fetchImagesQueries: [String] = []
    var fetchImageResultByID: [Int: Result<ImageDetail, Error>] = [:]
    var fetchImageContentResultByID: [Int: Result<Data, Error>] = [:]
    var uploadResult: Result<ImageDetail, Error> = .failure(APIClientError.invalidResponse)
    var generateUploadDescriptionResult: Result<GeneratedDescriptionResponse, Error> = .failure(APIClientError.invalidResponse)
    var updateDescriptionResult: Result<ImageDetail, Error> = .failure(APIClientError.invalidResponse)
    var generateDescriptionResult: Result<ImageDetail, Error> = .failure(APIClientError.invalidResponse)
    var insightResult: Result<InsightResponse, Error> = .failure(APIClientError.invalidResponse)
    var lastUploadDescription: String?
    var lastGenerateUploadPrompt: String?
    var lastUpdatedDescription: (Int, String)?
    var lastGeneratedDescriptionRequest: (Int, String)?

    func fetchAppInfo() async throws -> AppInfo {
        try appInfoResult.get()
    }

    func fetchImages(search: String) async throws -> [ImageSummary] {
        fetchImagesQueries.append(search)
        guard !fetchImagesResults.isEmpty else {
            throw APIClientError.invalidResponse
        }
        return try fetchImagesResults.removeFirst().get()
    }

    func fetchImage(id: Int) async throws -> ImageDetail {
        guard let result = fetchImageResultByID[id] else {
            throw APIClientError.server(statusCode: 404, message: "Missing detail")
        }
        return try result.get()
    }

    func fetchImageContent(id: Int) async throws -> Data {
        guard let result = fetchImageContentResultByID[id] else {
            throw APIClientError.server(statusCode: 404, message: "Missing content")
        }
        return try result.get()
    }

    func uploadImage(
        name: String,
        filename: String,
        mimeType: String?,
        data: Data,
        description: String?
    ) async throws -> ImageDetail {
        lastUploadDescription = description
        return try uploadResult.get()
    }

    func generateUploadDescription(
        filename: String,
        mimeType: String?,
        data: Data,
        prompt: String
    ) async throws -> GeneratedDescriptionResponse {
        lastGenerateUploadPrompt = prompt
        return try generateUploadDescriptionResult.get()
    }

    func updateImageDescription(id: Int, description: String) async throws -> ImageDetail {
        lastUpdatedDescription = (id, description)
        return try updateDescriptionResult.get()
    }

    func generateImageDescription(id: Int, prompt: String) async throws -> ImageDetail {
        lastGeneratedDescriptionRequest = (id, prompt)
        return try generateDescriptionResult.get()
    }

    func generateInsight(id: Int, prompt: String) async throws -> InsightResponse {
        try insightResult.get()
    }
}
