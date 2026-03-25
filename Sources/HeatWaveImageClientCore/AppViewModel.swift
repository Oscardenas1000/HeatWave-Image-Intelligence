import Foundation
import Observation

@MainActor
@Observable
public final class AppViewModel {
    public typealias ClientFactory = @Sendable (URL) -> any HeatWaveAPIClientProtocol

    public static let defaultInsightPrompt = "Describe this image and call out the most important visible details."

    public let settings: AppSettings
    public var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            scheduleSearch()
        }
    }
    public var insightPrompt = ""
    public private(set) var appInfo: AppInfo?
    public private(set) var records: [ImageSummary] = []
    public private(set) var selectedRecordID: Int?
    public private(set) var selectedDetail: ImageDetail?
    public private(set) var selectedImageData: Data?
    public private(set) var bannerMessage: String?
    public private(set) var isLoadingLibrary = false
    public private(set) var isLoadingDetail = false
    public private(set) var isGeneratingInsight = false
    public private(set) var libraryErrorMessage: String?
    public private(set) var detailErrorMessage: String?
    public var descriptionDraft = ""
    public var descriptionGenerationPrompt = ""
    public private(set) var descriptionErrorMessage: String?
    public private(set) var isSavingDescription = false
    public private(set) var isGeneratingDescription = false
    public private(set) var insightErrorMessage: String?
    public private(set) var insightText: String?
    public private(set) var insightDetectedLanguage: String?
    public private(set) var hasLoaded = false

    private let clientFactory: ClientFactory
    private let searchDebounceNanoseconds: UInt64
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    public init(
        settings: AppSettings,
        clientFactory: @escaping ClientFactory = { HeatWaveAPIClient(baseURL: $0) },
        searchDebounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.settings = settings
        self.clientFactory = clientFactory
        self.searchDebounceNanoseconds = searchDebounceNanoseconds
    }

    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refreshLibrary()
    }

    public func refreshLibrary(selecting preferredSelection: Int? = nil) async {
        let client: any HeatWaveAPIClientProtocol
        do {
            client = try makeClient()
        } catch {
            libraryErrorMessage = error.localizedDescription
            return
        }

        isLoadingLibrary = true
        libraryErrorMessage = nil

        do {
            let summaries = try await client.fetchImages(search: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
            let info = try await client.fetchAppInfo()
            records = summaries
            appInfo = info

            let nextSelection = resolvedSelection(preferredSelection: preferredSelection, records: summaries)
            isLoadingLibrary = false

            guard let nextSelection else {
                clearSelection()
                return
            }

            if nextSelection != selectedRecordID {
                selectedRecordID = nextSelection
                resetInsightState()
            }

            detailTask?.cancel()
            await loadDetail(for: nextSelection)
        } catch {
            isLoadingLibrary = false
            libraryErrorMessage = error.localizedDescription
        }
    }

    public func selectRecord(_ recordID: Int?) {
        guard selectedRecordID != recordID else { return }
        selectedRecordID = recordID

        guard let recordID else {
            clearSelection()
            return
        }

        resetInsightState()
        detailTask?.cancel()
        detailTask = Task { [weak self] in
            await self?.loadDetail(for: recordID)
        }
    }

    @discardableResult
    public func uploadImage(
        name: String,
        filename: String,
        mimeType: String?,
        data: Data,
        description: String
    ) async throws -> ImageDetail {
        let client = try makeClient()
        let created = try await client.uploadImage(
            name: name,
            filename: filename,
            mimeType: mimeType,
            data: data,
            description: description
        )
        bannerMessage = "Added \"\(created.imageName)\" to the library."
        await refreshLibrary(selecting: created.id)
        return created
    }

    public func generateUploadDescription(
        filename: String,
        mimeType: String?,
        data: Data,
        prompt: String
    ) async throws -> GeneratedDescriptionResponse {
        let client = try makeClient()
        return try await client.generateUploadDescription(
            filename: filename,
            mimeType: mimeType,
            data: data,
            prompt: prompt
        )
    }

    public func saveDescription() async {
        guard let selectedRecordID else {
            descriptionErrorMessage = "Choose an image before saving a description."
            return
        }

        let cleanedDescription = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDescription.isEmpty else {
            descriptionErrorMessage = "Image description is required."
            return
        }

        let client: any HeatWaveAPIClientProtocol
        do {
            client = try makeClient()
        } catch {
            descriptionErrorMessage = error.localizedDescription
            return
        }

        isSavingDescription = true
        descriptionErrorMessage = nil

        do {
            let detail = try await client.updateImageDescription(
                id: selectedRecordID,
                description: cleanedDescription
            )
            applyLoadedDetail(detail)
        } catch {
            descriptionErrorMessage = error.localizedDescription
        }

        isSavingDescription = false
    }

    public func generateDescription() async {
        guard let selectedRecordID else {
            descriptionErrorMessage = "Choose an image before generating a description."
            return
        }

        let client: any HeatWaveAPIClientProtocol
        do {
            client = try makeClient()
        } catch {
            descriptionErrorMessage = error.localizedDescription
            return
        }

        isGeneratingDescription = true
        descriptionErrorMessage = nil

        do {
            let detail = try await client.generateImageDescription(
                id: selectedRecordID,
                prompt: descriptionGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            applyLoadedDetail(detail)
        } catch {
            descriptionErrorMessage = error.localizedDescription
        }

        isGeneratingDescription = false
    }

    public func generateInsight() async {
        guard let selectedRecordID else {
            insightErrorMessage = "Choose an image before asking for insight."
            return
        }

        let prompt = insightPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            insightErrorMessage = "Enter a prompt before generating an AI response."
            return
        }

        let client: any HeatWaveAPIClientProtocol
        do {
            client = try makeClient()
        } catch {
            insightErrorMessage = error.localizedDescription
            return
        }

        isGeneratingInsight = true
        insightErrorMessage = nil

        do {
            let response = try await client.generateInsight(id: selectedRecordID, prompt: prompt)
            insightText = response.text
            insightDetectedLanguage = response.detectedLanguage
        } catch {
            insightText = nil
            insightDetectedLanguage = nil
            insightErrorMessage = error.localizedDescription
        }

        isGeneratingInsight = false
    }

    public func dismissBanner() {
        bannerMessage = nil
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: searchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await refreshLibrary()
        }
    }

    private func loadDetail(for recordID: Int) async {
        let client: any HeatWaveAPIClientProtocol
        do {
            client = try makeClient()
        } catch {
            detailErrorMessage = error.localizedDescription
            return
        }

        isLoadingDetail = true
        detailErrorMessage = nil
        defer {
            if selectedRecordID == recordID {
                isLoadingDetail = false
            }
        }

        do {
            async let detail = client.fetchImage(id: recordID)
            async let content = client.fetchImageContent(id: recordID)
            let resolvedDetail = try await detail
            let resolvedContent = try await content
            guard selectedRecordID == recordID else { return }
            applyLoadedDetail(resolvedDetail)
            selectedImageData = resolvedContent
        } catch {
            guard selectedRecordID == recordID else { return }
            selectedDetail = nil
            selectedImageData = nil
            detailErrorMessage = error.localizedDescription
        }
    }

    private func makeClient() throws -> any HeatWaveAPIClientProtocol {
        guard let baseURL = settings.resolvedBaseURL else {
            throw APIClientError.invalidBaseURL(settings.baseURLString)
        }
        return clientFactory(baseURL)
    }

    private func applyLoadedDetail(_ detail: ImageDetail) {
        selectedDetail = detail
        descriptionDraft = detail.description ?? ""
        descriptionErrorMessage = nil
    }

    private func clearSelection() {
        selectedRecordID = nil
        selectedDetail = nil
        selectedImageData = nil
        detailErrorMessage = nil
        descriptionDraft = ""
        descriptionGenerationPrompt = ""
        descriptionErrorMessage = nil
        resetInsightState()
    }

    private func resetInsightState() {
        insightPrompt = ""
        insightText = nil
        insightDetectedLanguage = nil
        insightErrorMessage = nil
        descriptionGenerationPrompt = ""
        descriptionErrorMessage = nil
    }

    private func resolvedSelection(
        preferredSelection: Int?,
        records: [ImageSummary]
    ) -> Int? {
        let candidate = preferredSelection ?? selectedRecordID
        if let candidate, records.contains(where: { $0.id == candidate }) {
            return candidate
        }
        return records.first?.id
    }
}
