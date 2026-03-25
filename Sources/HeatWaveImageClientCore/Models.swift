import Foundation

public struct AppInfo: Codable, Equatable, Sendable {
    public let aiModelId: String
    public let recordCount: Int

    public init(aiModelId: String, recordCount: Int) {
        self.aiModelId = aiModelId
        self.recordCount = recordCount
    }
}

public struct ImageSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let imageName: String
    public let originalFilename: String
    public let mimeType: String
    public let base64Length: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int,
        imageName: String,
        originalFilename: String,
        mimeType: String,
        base64Length: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.imageName = imageName
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.base64Length = base64Length
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ImageDetail: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let imageName: String
    public let originalFilename: String
    public let mimeType: String
    public let description: String?
    public let base64Length: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int,
        imageName: String,
        originalFilename: String,
        mimeType: String,
        description: String? = nil,
        base64Length: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.imageName = imageName
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.description = description
        self.base64Length = base64Length
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct InsightRequest: Codable, Equatable, Sendable {
    public let prompt: String

    public init(prompt: String) {
        self.prompt = prompt
    }
}

public struct InsightResponse: Codable, Equatable, Sendable {
    public let text: String
    public let detectedLanguage: String?

    public init(text: String, detectedLanguage: String? = nil) {
        self.text = text
        self.detectedLanguage = detectedLanguage
    }
}

public struct DescriptionUpdateRequest: Codable, Equatable, Sendable {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

public struct DescriptionGenerationRequest: Codable, Equatable, Sendable {
    public let prompt: String

    public init(prompt: String = "") {
        self.prompt = prompt
    }
}

public struct GeneratedDescriptionResponse: Codable, Equatable, Sendable {
    public let description: String
    public let detectedLanguage: String?

    public init(description: String, detectedLanguage: String? = nil) {
        self.description = description
        self.detectedLanguage = detectedLanguage
    }
}
