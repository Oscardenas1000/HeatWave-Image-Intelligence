import Foundation

public protocol HeatWaveAPIClientProtocol: Sendable {
    func fetchAppInfo() async throws -> AppInfo
    func fetchImages(search: String) async throws -> [ImageSummary]
    func fetchImage(id: Int) async throws -> ImageDetail
    func fetchImageContent(id: Int) async throws -> Data
    func uploadImage(
        name: String,
        filename: String,
        mimeType: String?,
        data: Data,
        description: String?
    ) async throws -> ImageDetail
    func generateUploadDescription(
        filename: String,
        mimeType: String?,
        data: Data,
        prompt: String
    ) async throws -> GeneratedDescriptionResponse
    func updateImageDescription(id: Int, description: String) async throws -> ImageDetail
    func generateImageDescription(id: Int, prompt: String) async throws -> ImageDetail
    func generateInsight(id: Int, prompt: String) async throws -> InsightResponse
}

public enum APIClientError: LocalizedError, Equatable, Sendable {
    case invalidBaseURL(String)
    case invalidResponse
    case server(statusCode: Int, message: String)
    case transport(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            return "Invalid backend URL: \(value)"
        case .invalidResponse:
            return "The backend returned an invalid response."
        case let .server(_, message):
            return message
        case let .transport(message):
            return message
        case let .decoding(message):
            return message
        }
    }
}

public struct HeatWaveAPIClient: HeatWaveAPIClientProtocol, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let uiTestHeaders: [String: String]

    public init(
        baseURL: URL,
        session: URLSession? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.baseURL = baseURL
        self.decoder = JSONDecoder.heatWave
        self.encoder = JSONEncoder()

        if let session {
            self.session = session
            self.uiTestHeaders = [:]
            return
        }

        if environment["HEATWAVE_UI_TEST_MODE"] == "1" {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [UITestMockURLProtocol.self]
            self.session = URLSession(configuration: configuration)
            self.uiTestHeaders = [
                UITestMockHeader.mode: "1",
                UITestMockHeader.fixturePath: environment["HEATWAVE_UI_TEST_IMAGE_PATH"] ?? "",
            ]
            return
        }

        self.session = .shared
        self.uiTestHeaders = [:]
    }

    public func fetchAppInfo() async throws -> AppInfo {
        try await decode(
            AppInfo.self,
            from: request(path: "app-info", queryItems: [])
        )
    }

    public func fetchImages(search: String) async throws -> [ImageSummary] {
        let queryItems = search.isEmpty ? [] : [URLQueryItem(name: "search", value: search)]
        return try await decode(
            [ImageSummary].self,
            from: request(path: "images", queryItems: queryItems)
        )
    }

    public func fetchImage(id: Int) async throws -> ImageDetail {
        try await decode(ImageDetail.self, from: request(path: "images/\(id)"))
    }

    public func fetchImageContent(id: Int) async throws -> Data {
        try await data(from: request(path: "images/\(id)/content"))
    }

    public func uploadImage(
        name: String,
        filename: String,
        mimeType: String?,
        data: Data,
        description: String?
    ) async throws -> ImageDetail {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try request(path: "images", method: "POST")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        var formData = MultipartFormDataBuilder(boundary: boundary)
            .addTextField(named: "image_name", value: name)
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formData = formData.addTextField(named: "description", value: description)
        }
        request.httpBody = formData
            .addFileField(
                named: "file",
                filename: filename,
                mimeType: mimeType ?? "application/octet-stream",
                data: data
            )
            .build()
        return try await decode(ImageDetail.self, from: request)
    }

    public func generateUploadDescription(
        filename: String,
        mimeType: String?,
        data: Data,
        prompt: String
    ) async throws -> GeneratedDescriptionResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try request(path: "descriptions/generate-upload", method: "POST")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = MultipartFormDataBuilder(boundary: boundary)
            .addTextField(named: "prompt", value: prompt)
            .addFileField(
                named: "file",
                filename: filename,
                mimeType: mimeType ?? "application/octet-stream",
                data: data
            )
            .build()
        return try await decode(GeneratedDescriptionResponse.self, from: request)
    }

    public func updateImageDescription(id: Int, description: String) async throws -> ImageDetail {
        var request = try request(path: "images/\(id)/description", method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(DescriptionUpdateRequest(description: description))
        return try await decode(ImageDetail.self, from: request)
    }

    public func generateImageDescription(id: Int, prompt: String) async throws -> ImageDetail {
        var request = try request(path: "images/\(id)/description/generate", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(DescriptionGenerationRequest(prompt: prompt))
        return try await decode(ImageDetail.self, from: request)
    }

    public func generateInsight(id: Int, prompt: String) async throws -> InsightResponse {
        var request = try request(path: "images/\(id)/insights", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(InsightRequest(prompt: prompt))
        return try await decode(InsightResponse.self, from: request)
    }

    private func request(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let resolvedURL = baseURL.appending(path: path)
        guard var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidBaseURL(baseURL.absoluteString)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIClientError.invalidBaseURL(baseURL.absoluteString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in uiTestHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let payload = try await data(from: request)
        do {
            return try decoder.decode(T.self, from: payload)
        } catch {
            throw APIClientError.decoding(error.localizedDescription)
        }
    }

    private func data(from request: URLRequest) async throws -> Data {
        let payload: Data
        let response: URLResponse
        do {
            (payload, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = decodeErrorMessage(from: payload) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw APIClientError.server(statusCode: httpResponse.statusCode, message: message)
        }

        return payload
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            let error: String
        }

        return try? decoder.decode(ErrorEnvelope.self, from: data).error
    }
}

private struct MultipartFormDataBuilder {
    let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addTextField(named name: String, value: String) -> Self {
        var updated = self
        updated.body.append("--\(boundary)\r\n")
        updated.body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        updated.body.append("\(value)\r\n")
        return updated
    }

    func addFileField(named name: String, filename: String, mimeType: String, data: Data) -> Self {
        var updated = self
        updated.body.append("--\(boundary)\r\n")
        updated.body.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        updated.body.append("Content-Type: \(mimeType)\r\n\r\n")
        updated.body.append(data)
        updated.body.append("\r\n")
        return updated
    }

    func build() -> Data {
        var finalized = body
        finalized.append("--\(boundary)--\r\n")
        return finalized
    }
}

private enum HeatWaveDateParser {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        let fallbackISO8601 = ISO8601DateFormatter()
        fallbackISO8601.formatOptions = [.withInternetDateTime]
        if let date = fallbackISO8601.date(from: value) {
            return date
        }

        let naiveFractional = DateFormatter()
        naiveFractional.locale = Locale(identifier: "en_US_POSIX")
        naiveFractional.timeZone = TimeZone(secondsFromGMT: 0)
        naiveFractional.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = naiveFractional.date(from: value) {
            return date
        }

        let naive = DateFormatter()
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = TimeZone(secondsFromGMT: 0)
        naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return naive.date(from: value)
    }
}

private extension JSONDecoder {
    static let heatWave: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = HeatWaveDateParser.parse(rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(rawValue)"
            )
        }
        return decoder
    }()
}

private extension URL {
    func appending(path: String) -> URL {
        path.split(separator: "/").reduce(self) { partialResult, component in
            partialResult.appendingPathComponent(String(component))
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private enum UITestMockHeader {
    static let mode = "X-HeatWave-UI-Test-Mode"
    static let fixturePath = "X-HeatWave-UI-Test-Fixture-Path"
}

private final class UITestMockURLProtocol: URLProtocol, @unchecked Sendable {
    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: UITestMockHeader.mode) == "1"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client else { return }
        let currentRequest = request

        loadingTask = Task {
            do {
                let mockResponse = try await UITestMockStore.shared.response(for: currentRequest)
                guard !Task.isCancelled else { return }
                let response = HTTPURLResponse(
                    url: currentRequest.url ?? URL(string: "http://127.0.0.1")!,
                    statusCode: mockResponse.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: mockResponse.headers
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: mockResponse.body)
                client.urlProtocolDidFinishLoading(self)
            } catch {
                guard !Task.isCancelled else { return }
                client.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}

private actor UITestMockStore {
    static let shared = UITestMockStore()

    struct StoredRecord {
        let id: Int
        let imageName: String
        let originalFilename: String
        let mimeType: String
        var description: String?
        let data: Data
        let createdAt: Date
        var updatedAt: Date

        var base64Length: Int {
            Data(data.base64EncodedString().utf8).count
        }
    }

    struct MockResponse {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    struct ImageWireModel: Encodable {
        let id: Int
        let imageName: String
        let originalFilename: String
        let mimeType: String
        let description: String?
        let base64Length: Int
        let createdAt: String
        let updatedAt: String
    }

    private var isConfigured = false
    private var nextID = 2
    private var records: [StoredRecord] = []

    func response(for request: URLRequest) throws -> MockResponse {
        try configureIfNeeded(using: request)

        guard let url = request.url else {
            throw APIClientError.invalidResponse
        }

        let method = request.httpMethod ?? "GET"
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if method == "GET", pathComponents == ["app-info"] {
            return try jsonResponse(
                statusCode: 200,
                payload: AppInfo(aiModelId: "mock-ui-test-model", recordCount: records.count)
            )
        }

        if method == "GET", pathComponents == ["images"] {
            let search = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "search" })?
                .value ?? ""
            let payload = listRecords(search: search).map(imageWireModel(for:))
            return try jsonResponse(statusCode: 200, payload: payload)
        }

        if method == "GET", pathComponents.count == 2, pathComponents.first == "images" {
            guard let identifier = pathComponents.last,
                  let record = record(for: identifier)
            else {
                return try errorResponse(statusCode: 404, message: "Image record not found.")
            }
            return try jsonResponse(statusCode: 200, payload: imageWireModel(for: record))
        }

        if method == "GET",
           pathComponents.count == 3,
           pathComponents.first == "images",
           pathComponents.last == "content"
        {
            guard let identifier = pathComponents.dropLast().last,
                  let record = record(for: identifier)
            else {
                return try errorResponse(statusCode: 404, message: "Image record not found.")
            }
            return MockResponse(
                statusCode: 200,
                headers: [
                    "Content-Type": record.mimeType,
                    "Content-Length": "\(record.data.count)",
                ],
                body: record.data
            )
        }

        if method == "POST", pathComponents == ["images"] {
            let created = try createUploadedRecord(from: request)
            return try jsonResponse(statusCode: 201, payload: imageWireModel(for: created))
        }

        if method == "POST", pathComponents == ["descriptions", "generate-upload"] {
            return try jsonResponse(
                statusCode: 200,
                payload: GeneratedDescriptionResponse(
                    description: "Generated upload description for the selected image.",
                    detectedLanguage: "en"
                )
            )
        }

        if method == "PUT",
           pathComponents.count == 3,
           pathComponents.first == "images",
           pathComponents.last == "description"
        {
            guard let identifier = pathComponents.dropLast().last,
                  let id = Int(identifier),
                  let updated = try updateDescription(for: id, request: request)
            else {
                return try errorResponse(statusCode: 404, message: "Image record not found.")
            }
            return try jsonResponse(statusCode: 200, payload: imageWireModel(for: updated))
        }

        if method == "POST",
           pathComponents.count == 4,
           pathComponents.first == "images",
           pathComponents.dropLast().last == "description",
           pathComponents.last == "generate"
        {
            guard let identifier = pathComponents.dropLast(2).last,
                  let id = Int(identifier),
                  let updated = generateDescription(for: id, request: request)
            else {
                return try errorResponse(statusCode: 404, message: "Image record not found.")
            }
            return try jsonResponse(statusCode: 200, payload: imageWireModel(for: updated))
        }

        if method == "POST",
           pathComponents.count == 3,
           pathComponents.first == "images",
           pathComponents.last == "insights"
        {
            guard let identifier = pathComponents.dropLast().last,
                  record(for: identifier) != nil
            else {
                return try errorResponse(statusCode: 404, message: "Image record not found.")
            }
            return try jsonResponse(
                statusCode: 200,
                payload: InsightResponse(
                    text: """
                    Smoke insight for uploaded image.

                    - **Main subject:** The uploaded fixture renders correctly.
                    - **Formatting:** Bold text, blank lines, and bullet points should stay intact.

                    In short, **markdown structure should remain readable.**
                    """,
                    detectedLanguage: "en"
                )
            )
        }

        return try errorResponse(statusCode: 404, message: "Image record not found.")
    }

    private func configureIfNeeded(using request: URLRequest) throws {
        guard !isConfigured else { return }

        guard let fixturePath = request.value(forHTTPHeaderField: UITestMockHeader.fixturePath),
              !fixturePath.isEmpty
        else {
            throw APIClientError.transport("UI test fixture path is missing.")
        }

        let fixtureURL = URL(fileURLWithPath: fixturePath)
        let data = try Data(contentsOf: fixtureURL)
        let createdAt = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 3,
            day: 23,
            hour: 12,
            minute: 0,
            second: 0
        ).date ?? Date(timeIntervalSince1970: 0)

        records = [
            StoredRecord(
                id: 1,
                imageName: "Existing Library Image",
                originalFilename: fixtureURL.lastPathComponent,
                mimeType: mimeType(for: fixtureURL.pathExtension),
                description: "Existing reusable description for the image.",
                data: data,
                createdAt: createdAt,
                updatedAt: createdAt
            ),
        ]
        nextID = 2
        isConfigured = true
    }

    private func listRecords(search: String) -> [StoredRecord] {
        let lowered = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [StoredRecord]
        if lowered.isEmpty {
            filtered = records
        } else {
            filtered = records.filter { $0.imageName.lowercased().contains(lowered) }
        }
        return filtered.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id > $1.id
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private func record(for identifier: String) -> StoredRecord? {
        guard let id = Int(identifier) else { return nil }
        return records.first(where: { $0.id == id })
    }

    private func createUploadedRecord(from request: URLRequest) throws -> StoredRecord {
        guard let seedRecord = records.first else {
            throw APIClientError.transport("UI test fixture record is unavailable.")
        }

        let body = request.httpBody ?? Data()
        let imageName = extractMultipartField(named: "image_name", from: body) ?? "UI Smoke Upload"
        let description = extractMultipartField(named: "description", from: body)
            ?? "Generated upload description for the selected image."
        let createdAt = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 3,
            day: 23,
            hour: 12,
            minute: 5,
            second: nextID
        ).date ?? seedRecord.createdAt

        let record = StoredRecord(
            id: nextID,
            imageName: imageName,
            originalFilename: seedRecord.originalFilename,
            mimeType: seedRecord.mimeType,
            description: description,
            data: seedRecord.data,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        nextID += 1
        records.append(record)
        return record
    }

    private func imageWireModel(for record: StoredRecord) -> ImageWireModel {
        ImageWireModel(
            id: record.id,
            imageName: record.imageName,
            originalFilename: record.originalFilename,
            mimeType: record.mimeType,
            description: record.description,
            base64Length: record.base64Length,
            createdAt: iso8601String(for: record.createdAt),
            updatedAt: iso8601String(for: record.updatedAt)
        )
    }

    private func jsonResponse<T: Encodable>(statusCode: Int, payload: T) throws -> MockResponse {
        let body = try JSONEncoder().encode(payload)
        return MockResponse(
            statusCode: statusCode,
            headers: [
                "Content-Type": "application/json",
                "Content-Length": "\(body.count)",
            ],
            body: body
        )
    }

    private func errorResponse(statusCode: Int, message: String) throws -> MockResponse {
        try jsonResponse(statusCode: statusCode, payload: ["error": message])
    }

    private func extractMultipartField(named fieldName: String, from body: Data) -> String? {
        let text = String(decoding: body, as: UTF8.self)
        let pattern = #"name="\#(fieldName)"\r\n\r\n([^\r\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateDescription(for id: Int, request: URLRequest) throws -> StoredRecord? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        let body = request.httpBody ?? Data()
        let payload = try JSONDecoder().decode(DescriptionUpdateRequest.self, from: body)
        let trimmed = payload.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIClientError.server(statusCode: 400, message: "Image description is required.")
        }
        records[index].description = trimmed
        records[index].updatedAt = records[index].updatedAt.addingTimeInterval(60)
        return records[index]
    }

    private func generateDescription(for id: Int, request: URLRequest) -> StoredRecord? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        let body = request.httpBody ?? Data()
        let prompt = (try? JSONDecoder().decode(DescriptionGenerationRequest.self, from: body).prompt) ?? ""
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrompt.isEmpty {
            records[index].description = "Generated updated description for the selected image."
        } else {
            records[index].description = "Generated description guided by: \(trimmedPrompt)"
        }
        records[index].updatedAt = records[index].updatedAt.addingTimeInterval(60)
        return records[index]
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }

    private func iso8601String(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
