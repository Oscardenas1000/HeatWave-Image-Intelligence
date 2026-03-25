import AppKit
import Foundation
import HeatWaveImageClientCore
import Observation
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel
    @Bindable var settings: AppSettings
    @State private var isPresentingUpload = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaPadding(.top, 8)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isPresentingUpload = true
                } label: {
                    Label("Upload", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("u", modifiers: [.command])
                .accessibilityIdentifier("upload_button")

                Button {
                    Task {
                        await viewModel.refreshLibrary()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .accessibilityIdentifier("refresh_button")

                SettingsLink {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $isPresentingUpload) {
            UploadSheetView(viewModel: viewModel)
                .frame(minWidth: 880, minHeight: 600)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Image Library")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Search, select, and inspect records.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            HStack(spacing: 10) {
                pill(title: "Images", value: "\(viewModel.appInfo?.recordCount ?? viewModel.records.count)")
                pill(title: "Model", value: viewModel.appInfo?.aiModelId ?? "Waiting")
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find an image by name", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )

            if let banner = viewModel.bannerMessage {
                HStack {
                    Text(banner)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.dismissBanner()
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.green.opacity(0.12))
                )
            }

            if let errorMessage = viewModel.libraryErrorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.red.opacity(0.1))
                    )
            }

            List(selection: selectionBinding) {
                ForEach(viewModel.records) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.imageName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text("#\(record.id) • \(record.originalFilename)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(record.base64Length.formatted()) base64 chars")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 5)
                    .accessibilityIdentifier("library_row_\(record.id)")
                    .tag(record.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .accessibilityIdentifier("library_list")
            .overlay {
                if viewModel.records.isEmpty, !viewModel.isLoadingLibrary {
                    ContentUnavailableView(
                        "No Images Yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Upload an image or adjust the current search.")
                    )
                }
            }

            runtimeFooter
        }
        .padding(20)
        .background(sidebarBackground)
        .overlay(alignment: .center) {
            if viewModel.isLoadingLibrary, viewModel.records.isEmpty {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private var detailPane: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let detail = viewModel.selectedDetail {
                        detailHeader(detail: detail)

                        // Breakpoint is based on the *detail* column width (sidebar is separate),
                        // so use a lower threshold to keep the two-column layout in the default window.
                        if proxy.size.width > 900 {
                            let insightPanelWidth = min(max(proxy.size.width * 0.36, 360), 460)
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 18) {
                                    imageCard
                                    descriptionCard(detail: detail)
                                    metadataCard(detail: detail)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                                insightCard
                                    .frame(width: insightPanelWidth, alignment: .topLeading)
                            }
                        } else {
                            imageCard
                            descriptionCard(detail: detail)
                            metadataCard(detail: detail)
                            insightCard
                        }
                    } else if let errorMessage = viewModel.detailErrorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .primaryCard()
                    } else if viewModel.isLoadingDetail {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text("Loading image detail...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        ContentUnavailableView(
                            "Select an Image",
                            systemImage: "rectangle.stack.person.crop",
                            description: Text("Choose a record from the library to review metadata and ask for an AI insight.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 420)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(detailBackground)
        }
    }

    private func detailHeader(detail: ImageDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.imageName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(detail.originalFilename)
                    .lineLimit(1)
                Text("•")
                Text(detail.mimeType)
                    .lineLimit(1)
                Text("•")
                Text("#\(detail.id)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let data = viewModel.selectedImageData {
                ImageDataView(data: data)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.035))
                    )
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .primaryCard()
    }

    private func descriptionCard(detail: ImageDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Description")
                .font(.title3.weight(.semibold))

            Text("Stored with the image and used as context for later AI insight generation.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Generation Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    PromptTextView(
                        text: $viewModel.descriptionGenerationPrompt,
                        accessibilityIdentifier: "description_generation_prompt_editor"
                    )
                    .frame(height: 72)

                    if viewModel.descriptionGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Optional guidance for regenerating the description.")
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
                Text("Stored Description")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    PromptTextView(
                        text: $viewModel.descriptionDraft,
                        accessibilityIdentifier: "image_description_editor"
                    )
                    .frame(height: 170)

                    if viewModel.descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(detail.description?.isEmpty == false ? detail.description ?? "" : "Write a description manually or generate one from the image.")
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

            if let errorMessage = viewModel.descriptionErrorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await viewModel.generateDescription()
                    }
                } label: {
                    if viewModel.isGeneratingDescription {
                        ProgressView()
                    } else {
                        Label("Update Description", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedRecordID == nil || viewModel.isSavingDescription)
                .accessibilityIdentifier("generate_description_button")

                Button {
                    Task {
                        await viewModel.saveDescription()
                    }
                } label: {
                    if viewModel.isSavingDescription {
                        ProgressView()
                    } else {
                        Label("Save Description", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    viewModel.selectedRecordID == nil ||
                    viewModel.isGeneratingDescription ||
                    viewModel.descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("save_description_button")

                Spacer()
            }
        }
        .primaryCard()
    }

    private func metadataCard(detail: ImageDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metadata")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    metadataItem(title: "Record", value: "#\(detail.id)")
                }
                GridRow {
                    metadataItem(title: "Original File", value: detail.originalFilename)
                }
                GridRow {
                    metadataItem(title: "MIME Type", value: detail.mimeType)
                }
                GridRow {
                    metadataItem(title: "Payload", value: "\(detail.base64Length.formatted()) chars")
                }
                GridRow {
                    metadataItem(title: "Created", value: detail.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                GridRow {
                    metadataItem(title: "Updated", value: detail.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .secondaryCard()
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Insight")
                .font(.title3.weight(.semibold))
            Text("Ask a focused question about the selected image.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    PromptTextView(
                        text: $viewModel.insightPrompt,
                        accessibilityIdentifier: "insight_prompt_editor"
                    )
                        .frame(height: 88)

                    if viewModel.insightPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(AppViewModel.defaultInsightPrompt)
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

            HStack {
                Button {
                    Task {
                        await viewModel.generateInsight()
                    }
                } label: {
                    if viewModel.isGeneratingInsight {
                        ProgressView()
                    } else {
                        Label("Generate Insight", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.insightPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedRecordID == nil)
                .accessibilityIdentifier("generate_insight_button")

                if viewModel.isGeneratingInsight {
                    Text("Generating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let errorMessage = viewModel.insightErrorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Response")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let detectedLanguage = viewModel.insightDetectedLanguage,
                       !detectedLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        InsightLanguageBadge(languageCode: detectedLanguage)
                            .accessibilityIdentifier("insight_language_badge")
                    }
                }

                Group {
                    if let insight = viewModel.insightText, !insight.isEmpty {
                        MarkdownInsightText(markdown: insight)
                            .accessibilityIdentifier("insight_result_text")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No insight generated yet")
                                .font(.subheadline.weight(.semibold))
                            Text("Enter a prompt and run insight generation to see the model response.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .primaryCard()
    }

    private func metadataItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var runtimeFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Run Stamp")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(settings.runStamp)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .accessibilityIdentifier("runtime_run_stamp_sidebar")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var selectionBinding: Binding<Int?> {
        Binding(
            get: { viewModel.selectedRecordID },
            set: { viewModel.selectRecord($0) }
        )
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 0.98),
                Color(nsColor: .underPageBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.98, blue: 0.99),
                Color(nsColor: .windowBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ImageDataView: View {
    let data: Data

    var body: some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            ContentUnavailableView(
                "Image Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The selected image content could not be rendered.")
            )
        }
    }
}

private struct MarkdownInsightText: View {
    private let blocks: [MarkdownInsightBlock]

    init(markdown: String) {
        blocks = MarkdownInsightParser.parse(markdown: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    InlineMarkdownLine(markdown: text, baseFont: headingFont(for: level))
                case let .paragraph(lines):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            InlineMarkdownLine(markdown: line)
                        }
                    }
                case let .unorderedList(items):
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            MarkdownListItemView(marker: "\u{2022}", item: item)
                        }
                    }
                case let .orderedList(items):
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            MarkdownListItemView(marker: item.marker, item: item)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2.weight(.bold)
        case 2:
            return .title3.weight(.semibold)
        case 3:
            return .headline.weight(.semibold)
        default:
            return .body.weight(.semibold)
        }
    }
}

private struct InsightLanguageBadge: View {
    let languageCode: String

    private var normalizedCode: String {
        languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var displayName: String {
        if let englishName = Locale(identifier: "en").localizedString(forLanguageCode: normalizedCode),
           !englishName.isEmpty
        {
            return englishName
        }

        if let localizedName = Locale.autoupdatingCurrent.localizedString(forLanguageCode: normalizedCode),
           !localizedName.isEmpty
        {
            return localizedName
        }

        return normalizedCode.uppercased()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.caption.weight(.semibold))

            Text("Detected: \(displayName) (\(normalizedCode.uppercased()))")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color(red: 0.08, green: 0.34, blue: 0.70))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.08, green: 0.34, blue: 0.70).opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color(red: 0.08, green: 0.34, blue: 0.70).opacity(0.18), lineWidth: 1)
        )
    }
}

private struct InlineMarkdownLine: View {
    let renderedText: AttributedString
    let baseFont: Font

    init(markdown: String, baseFont: Font = .body) {
        self.baseFont = baseFont

        let inlineOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        if let parsed = try? AttributedString(markdown: markdown, options: inlineOptions) {
            renderedText = parsed
        } else {
            renderedText = AttributedString(markdown)
        }
    }

    var body: some View {
        Text(renderedText)
            .font(baseFont)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MarkdownListItemView: View {
    let marker: String
    let item: MarkdownInsightListItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(marker)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(item.lines.enumerated()), id: \.offset) { _, line in
                    InlineMarkdownLine(markdown: line)
                }
            }
        }
        .padding(.leading, CGFloat(item.indentLevel) * 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum MarkdownInsightBlock {
    case heading(level: Int, text: String)
    case paragraph(lines: [String])
    case unorderedList(items: [MarkdownInsightListItem])
    case orderedList(items: [MarkdownInsightListItem])
}

private struct MarkdownInsightListItem {
    let marker: String
    let indentLevel: Int
    var lines: [String]
}

private enum MarkdownInsightParser {
    static func parse(markdown: String) -> [MarkdownInsightBlock] {
        let normalizedMarkdown = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")

        var blocks: [MarkdownInsightBlock] = []
        var paragraphLines: [String] = []
        var unorderedItems: [MarkdownInsightListItem] = []
        var orderedItems: [MarkdownInsightListItem] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(lines: paragraphLines))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            blocks.append(.unorderedList(items: unorderedItems))
            unorderedItems.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            blocks.append(.orderedList(items: orderedItems))
            orderedItems.removeAll(keepingCapacity: true)
        }

        func flushLists() {
            flushUnorderedList()
            flushOrderedList()
        }

        for line in normalizedMarkdown.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                flushParagraph()
                flushLists()
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                flushLists()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let item = parseUnorderedListItem(line) {
                flushParagraph()
                flushOrderedList()
                unorderedItems.append(item)
                continue
            }

            if let item = parseOrderedListItem(line) {
                flushParagraph()
                flushUnorderedList()
                orderedItems.append(item)
                continue
            }

            if hasLeadingIndent(line) {
                if !unorderedItems.isEmpty {
                    unorderedItems[unorderedItems.count - 1].lines.append(trimmedLine)
                    continue
                }

                if !orderedItems.isEmpty {
                    orderedItems[orderedItems.count - 1].lines.append(trimmedLine)
                    continue
                }
            }

            flushLists()
            paragraphLines.append(line)
        }

        flushParagraph()
        flushLists()

        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "#" else { return nil }

        let headingMarks = trimmed.prefix { $0 == "#" }
        guard !headingMarks.isEmpty, headingMarks.count <= 6 else { return nil }

        let remainder = trimmed.dropFirst(headingMarks.count)
        guard remainder.first?.isWhitespace == true else { return nil }

        return (headingMarks.count, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func parseUnorderedListItem(_ line: String) -> MarkdownInsightListItem? {
        let leadingWhitespace = line.prefix { $0.isWhitespace }
        let trimmed = line.dropFirst(leadingWhitespace.count)

        guard
            let marker = trimmed.first,
            ["-", "*", "+", "\u{2022}"].contains(marker),
            trimmed.dropFirst().first?.isWhitespace == true
        else {
            return nil
        }

        let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }

        return MarkdownInsightListItem(
            marker: String(marker),
            indentLevel: leadingWhitespace.count / 2,
            lines: [content]
        )
    }

    private static func parseOrderedListItem(_ line: String) -> MarkdownInsightListItem? {
        let leadingWhitespace = line.prefix { $0.isWhitespace }
        let trimmed = line.dropFirst(leadingWhitespace.count)

        var digits = ""
        var index = trimmed.startIndex

        while index < trimmed.endIndex, trimmed[index].isNumber {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }

        guard !digits.isEmpty, index < trimmed.endIndex else { return nil }

        let punctuation = trimmed[index]
        guard punctuation == "." || punctuation == ")" else { return nil }

        index = trimmed.index(after: index)
        guard index < trimmed.endIndex, trimmed[index].isWhitespace else { return nil }

        let content = trimmed[index...].trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }

        return MarkdownInsightListItem(
            marker: "\(digits)\(punctuation)",
            indentLevel: leadingWhitespace.count / 2,
            lines: [content]
        )
    }

    private static func hasLeadingIndent(_ line: String) -> Bool {
        guard let firstCharacter = line.first else { return false }
        return firstCharacter.isWhitespace
    }
}

struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    let accessibilityIdentifier: String
    private let diagnosticsLogger = PromptDiagnosticsLogger()

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, diagnosticsLogger: diagnosticsLogger)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PromptScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = PromptNSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.diagnosticsLogger = diagnosticsLogger
        scrollView.documentView = textView
        scrollView.promptTextView = textView
        scrollView.diagnosticsLogger = diagnosticsLogger

        configure(textView, coordinator: context.coordinator)

        scrollView.setAccessibilityLabel("Insight Prompt")
        scrollView.setAccessibilityIdentifier(accessibilityIdentifier)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.setAccessibilityIdentifier(accessibilityIdentifier)
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    private func configure(_ textView: NSTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.font = .preferredFont(forTextStyle: .body)
        textView.setAccessibilityLabel("Insight Prompt")
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        private let diagnosticsLogger: PromptDiagnosticsLogger

        fileprivate init(text: Binding<String>, diagnosticsLogger: PromptDiagnosticsLogger) {
            _text = text
            self.diagnosticsLogger = diagnosticsLogger
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            diagnosticsLogger.log("textDidChange length=\(textView.string.count)")
        }
    }
}

private final class PromptScrollView: NSScrollView {
    weak var promptTextView: NSTextView?
    var diagnosticsLogger: PromptDiagnosticsLogger?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        diagnosticsLogger?.log("scrollView.mouseDown")
        window?.makeFirstResponder(promptTextView)
        super.mouseDown(with: event)
    }
}

private final class PromptNSTextView: NSTextView {
    var diagnosticsLogger: PromptDiagnosticsLogger?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        diagnosticsLogger?.log("textView.becomeFirstResponder accepted=\(accepted)")
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        diagnosticsLogger?.log("textView.resignFirstResponder accepted=\(accepted)")
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        diagnosticsLogger?.log("textView.mouseDown")
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        diagnosticsLogger?.log("textView.keyDown keyCode=\(event.keyCode)")
        super.keyDown(with: event)
    }
}

fileprivate final class PromptDiagnosticsLogger {
    private let fileURL: URL?
    private let formatter: ISO8601DateFormatter
    private let lock = NSLock()

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let rawPath = environment["HEATWAVE_PROMPT_LOG_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty
        {
            fileURL = URL(fileURLWithPath: rawPath)
        } else {
            fileURL = nil
        }
    }

    func log(_ message: String) {
        guard let fileURL else { return }

        lock.lock()
        defer { lock.unlock() }

        let directoryURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer {
            handle.closeFile()
        }

        handle.seekToEndOfFile()
        handle.write(data)
    }
}

private struct PrimaryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

private struct SecondaryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

private extension View {
    func primaryCard() -> some View {
        modifier(PrimaryCardModifier())
    }

    func secondaryCard() -> some View {
        modifier(SecondaryCardModifier())
    }
}
