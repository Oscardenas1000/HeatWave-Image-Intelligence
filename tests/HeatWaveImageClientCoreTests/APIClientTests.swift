import Foundation
import XCTest
@testable import HeatWaveImageClientCore

final class APIClientTests: XCTestCase {
    override class func tearDown() {
        super.tearDown()
        URLProtocolStub.reset()
    }

    func testFetchImagesDecodesResponse() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.path, "/images")
            let body = """
            [
              {
                "id": 7,
                "imageName": "Bluebonnet Longhorn",
                "originalFilename": "truck.png",
                "mimeType": "image/png",
                "base64Length": 1024,
                "createdAt": "2026-03-23T12:00:00",
                "updatedAt": "2026-03-23T12:00:00"
              }
            ]
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(body.utf8)
            )
        }

        let client = makeClient()
        let images = try await client.fetchImages(search: "")

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].imageName, "Bluebonnet Longhorn")
        XCTAssertEqual(images[0].mimeType, "image/png")
    }

    func testUploadImageSendsDescriptionFieldAndDecodesResponse() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.path, "/images")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try bodyString(from: request)
            XCTAssertTrue(body.contains("name=\"image_name\""))
            XCTAssertTrue(body.contains("Bluebonnet Longhorn"))
            XCTAssertTrue(body.contains("name=\"description\""))
            XCTAssertTrue(body.contains("Reusable upload description."))

            let responseBody = """
            {
              "id": 7,
              "imageName": "Bluebonnet Longhorn",
              "originalFilename": "truck.png",
              "mimeType": "image/png",
              "description": "Reusable upload description.",
              "base64Length": 1024,
              "createdAt": "2026-03-23T12:00:00",
              "updatedAt": "2026-03-23T12:00:00"
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(responseBody.utf8)
            )
        }

        let client = makeClient()
        let detail = try await client.uploadImage(
            name: "Bluebonnet Longhorn",
            filename: "truck.png",
            mimeType: "image/png",
            data: Data([0x01, 0x02]),
            description: "Reusable upload description."
        )

        XCTAssertEqual(detail.description, "Reusable upload description.")
    }

    func testGenerateUploadDescriptionDecodesResponse() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.path, "/descriptions/generate-upload")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try bodyString(from: request)
            XCTAssertTrue(body.contains("name=\"prompt\""))
            XCTAssertTrue(body.contains("Focus on the truck"))

            let responseBody = """
            {
              "description": "Generated upload description.",
              "detectedLanguage": "en"
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(responseBody.utf8)
            )
        }

        let client = makeClient()
        let response = try await client.generateUploadDescription(
            filename: "truck.png",
            mimeType: "image/png",
            data: Data([0x01, 0x02]),
            prompt: "Focus on the truck"
        )

        XCTAssertEqual(response.description, "Generated upload description.")
        XCTAssertEqual(response.detectedLanguage, "en")
    }

    func testUpdateImageDescriptionDecodesResponse() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.path, "/images/7/description")
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try requestBody(from: request)
            let payload = try JSONDecoder().decode(DescriptionUpdateRequest.self, from: body)
            XCTAssertEqual(payload.description, "Updated reusable description.")

            let responseBody = """
            {
              "id": 7,
              "imageName": "Bluebonnet Longhorn",
              "originalFilename": "truck.png",
              "mimeType": "image/png",
              "description": "Updated reusable description.",
              "base64Length": 1024,
              "createdAt": "2026-03-23T12:00:00",
              "updatedAt": "2026-03-23T12:01:00"
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(responseBody.utf8)
            )
        }

        let client = makeClient()
        let detail = try await client.updateImageDescription(
            id: 7,
            description: "Updated reusable description."
        )

        XCTAssertEqual(detail.description, "Updated reusable description.")
    }

    func testServerErrorMapsBackendMessage() async throws {
        URLProtocolStub.setHandler { request in
            let body = #"{"error":"Image record not found."}"#
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(body.utf8)
            )
        }

        let client = makeClient()

        do {
            _ = try await client.fetchImage(id: 404)
            XCTFail("Expected a server error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .server(statusCode: 404, message: "Image record not found."))
        }
    }

    func testGenerateInsightDecodesDetectedLanguage() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.path, "/images/7/insights")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = """
            {
              "text": "Detected a blue truck.",
              "detectedLanguage": "es"
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(body.utf8)
            )
        }

        let client = makeClient()
        let response = try await client.generateInsight(id: 7, prompt: "Describe this image")

        XCTAssertEqual(response.text, "Detected a blue truck.")
        XCTAssertEqual(response.detectedLanguage, "es")
    }
    private func makeClient() -> HeatWaveAPIClient {
        HeatWaveAPIClient(
            baseURL: try! XCTUnwrap(URL(string: "http://127.0.0.1:8000")),
            session: makeSession()
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private func bodyString(from request: URLRequest) throws -> String {
    String(decoding: try requestBody(from: request), as: UTF8.self)
}

private func requestBody(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        throw APIClientError.invalidResponse
    }

    stream.open()
    defer {
        stream.close()
    }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer {
        buffer.deallocate()
    }

    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            throw stream.streamError ?? APIClientError.invalidResponse
        }
        if readCount == 0 {
            break
        }
        data.append(buffer, count: readCount)
    }

    return data
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let state = LockedHandlerBox()

    static func setHandler(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        state.set(handler)
    }

    static func reset() {
        state.set(nil)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = Self.state.get()

        guard let handler else {
            XCTFail("URLProtocolStub.handler was not set")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    func set(_ newHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    func get() -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return handler
    }
}
