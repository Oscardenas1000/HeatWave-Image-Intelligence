import Foundation
import Observation

@MainActor
@Observable
public final class UploadDraft {
    public var imageName = ""
    public var description = ""
    public var descriptionGenerationPrompt = ""
    public var errorMessage: String?
    public var isUploading = false
    public var isGeneratingDescription = false
    public private(set) var filename: String?
    public private(set) var mimeType: String?
    public private(set) var imageData: Data?

    public init(initialImageName: String = "") {
        imageName = initialImageName
    }

    public var canSubmit: Bool {
        imageData != nil
            && !imageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isUploading
            && !isGeneratingDescription
    }

    public func setImportedFile(filename: String, mimeType: String?, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.imageData = data
        self.errorMessage = nil
    }

    public func clear() {
        imageName = ""
        description = ""
        descriptionGenerationPrompt = ""
        errorMessage = nil
        isUploading = false
        isGeneratingDescription = false
        filename = nil
        mimeType = nil
        imageData = nil
    }
}
