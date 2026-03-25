import AppKit
import HeatWaveImageClientCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct UploadSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: AppViewModel

    @State private var draft: UploadDraft
    @State private var isPresentingImporter = false
    private let uiTestFixturePath: String?
    private let shouldAutoImportTestFixture: Bool

    private struct ImportedFile: Sendable {
        let filename: String
        let mimeType: String?
        let data: Data
    }

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let environment = ProcessInfo.processInfo.environment
        uiTestFixturePath = environment["HEATWAVE_UI_TEST_IMAGE_PATH"]
        shouldAutoImportTestFixture = environment["HEATWAVE_UI_TEST_AUTO_IMPORT"] == "1"
        let initialImageName = environment["HEATWAVE_UI_TEST_UPLOAD_NAME"] ?? ""
        let initialDraft = UploadSheetView.makeInitialDraft(
            imageName: initialImageName,
            fixturePath: uiTestFixturePath,
            autoImportFixture: shouldAutoImportTestFixture
        )
        _draft = State(
            initialValue: initialDraft
        )
    }

    var body: some View {
        HStack(spacing: 20) {
            uploadFormPanel
            previewPanel
        }
        .padding(24)
        .background(sheetBackground)
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                importFile(at: url)
            case let .failure(error):
                draft.errorMessage = error.localizedDescription
            }
        }
    }

    private var uploadFormPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Upload Image")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Name the image, attach a file, then save it to the library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Image Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Image name", text: $draft.imageName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityIdentifier("upload_name_field")
            }

            HStack(spacing: 10) {
                Button {
                    isPresentingImporter = true
                } label: {
                    Label(draft.filename ?? "Choose Image", systemImage: "photo.badge.plus")
                }
                .accessibilityIdentifier("upload_choose_image_button")

                if let uiTestFixturePath {
                    Button("Use Test Image") {
                        importFile(at: URL(fileURLWithPath: uiTestFixturePath))
                    }
                    .accessibilityIdentifier("upload_test_fixture_button")
                }
            }

            if let errorMessage = draft.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.red.opacity(0.1))
                    )
            }

            if let filename = draft.filename {
                VStack(alignment: .leading, spacing: 6) {
                    Text(filename)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(draft.mimeType ?? "Unknown type")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    PromptTextView(
                        text: $draft.descriptionGenerationPrompt,
                        accessibilityIdentifier: "upload_description_prompt_editor"
                    )
                    .frame(height: 72)

                    if draft.descriptionGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Optional guidance for auto-generating the image description.")
                            .font(.body)
                            .foregroundStyle(Color(nsColor: .placeholderTextColor))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        .allowsHitTesting(false)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        generateDescription()
                    } label: {
                        if draft.isGeneratingDescription {
                            ProgressView()
                        } else {
                            Label("Auto-Generate", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.imageData == nil || draft.isUploading || draft.isGeneratingDescription)
                    .accessibilityIdentifier("upload_generate_description_button")
                }

                ZStack(alignment: .topLeading) {
                    PromptTextView(
                        text: $draft.description,
                        accessibilityIdentifier: "upload_description_editor"
                    )
                    .frame(height: 160)

                    if draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Enter a manual description or generate one from the image.")
                            .font(.body)
                            .foregroundStyle(Color(nsColor: .placeholderTextColor))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        .allowsHitTesting(false)
                )
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button {
                    submitUpload()
                } label: {
                    if draft.isUploading {
                        ProgressView()
                    } else {
                        Text("Save To Library")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSubmit)
                .accessibilityIdentifier("save_upload_button")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                if let data = draft.imageData {
                    ImageDataPreview(data: data)
                } else {
                    ContentUnavailableView(
                        "Preview Appears Here",
                        systemImage: "photo.artframe",
                        description: Text("Import an image and give it a name to prepare it for upload.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func importFile(at url: URL) {
        Task {
            do {
                let importedFile = try await loadImportedFile(from: url)
                draft.setImportedFile(
                    filename: importedFile.filename,
                    mimeType: importedFile.mimeType,
                    data: importedFile.data
                )
            } catch {
                draft.errorMessage = error.localizedDescription
            }
        }
    }

    private func submitUpload() {
        guard let data = draft.imageData, let filename = draft.filename else {
            draft.errorMessage = "Choose an image before saving."
            return
        }

        Task {
            draft.isUploading = true
            draft.errorMessage = nil
            do {
                try await viewModel.uploadImage(
                    name: draft.imageName,
                    filename: filename,
                    mimeType: draft.mimeType,
                    data: data,
                    description: draft.description
                )
                draft.isUploading = false
                dismiss()
            } catch {
                draft.isUploading = false
                draft.errorMessage = error.localizedDescription
            }
        }
    }

    private func generateDescription() {
        guard let data = draft.imageData, let filename = draft.filename else {
            draft.errorMessage = "Choose an image before generating a description."
            return
        }

        Task {
            draft.isGeneratingDescription = true
            draft.errorMessage = nil
            do {
                let response = try await viewModel.generateUploadDescription(
                    filename: filename,
                    mimeType: draft.mimeType,
                    data: data,
                    prompt: draft.descriptionGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                draft.description = response.description
                draft.isGeneratingDescription = false
            } catch {
                draft.isGeneratingDescription = false
                draft.errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated private static func inferredMimeType(for url: URL) -> String? {
        if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let mimeType = resourceType.preferredMIMEType
        {
            return mimeType
        }

        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }

    private func loadImportedFile(from url: URL) async throws -> ImportedFile {
        try await Task.detached(priority: .userInitiated) {
            try Self.loadImportedFileSync(from: url)
        }.value
    }

    private static func makeInitialDraft(
        imageName: String,
        fixturePath: String?,
        autoImportFixture: Bool
    ) -> UploadDraft {
        let draft = UploadDraft(initialImageName: imageName)

        guard autoImportFixture, let fixturePath else {
            return draft
        }

        do {
            let importedFile = try loadImportedFileSync(from: URL(fileURLWithPath: fixturePath))
            draft.setImportedFile(
                filename: importedFile.filename,
                mimeType: importedFile.mimeType,
                data: importedFile.data
            )
        } catch {
            draft.errorMessage = error.localizedDescription
        }

        return draft
    }

    nonisolated private static func loadImportedFileSync(from url: URL) throws -> ImportedFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let mimeType = inferredMimeType(for: url)
        return ImportedFile(
            filename: url.lastPathComponent,
            mimeType: mimeType,
            data: data
        )
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(nsColor: .underPageBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ImageDataPreview: View {
    let data: Data

    var body: some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The selected file could not be rendered as an image.")
            )
        }
    }
}
