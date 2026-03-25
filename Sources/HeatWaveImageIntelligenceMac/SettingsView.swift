import HeatWaveImageClientCore
import Observation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connection Settings")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("The app stores only the backend URL locally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Backend URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Base URL", text: $settings.baseURLString)
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

                if let validationMessage = settings.validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                } else {
                    Text("Database credentials remain on the FastAPI backend.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Runtime Diagnostics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                diagnosticRow(
                    title: "Run Stamp",
                    value: settings.runStamp,
                    accessibilityIdentifier: "runtime_run_stamp_value",
                    monospaced: true
                )

                diagnosticRow(
                    title: "Launch Source",
                    value: settings.launchSource,
                    accessibilityIdentifier: "runtime_launch_source_value"
                )

                diagnosticRow(
                    title: "Prompt Log",
                    value: settings.promptDiagnosticsLogPath ?? "Disabled",
                    accessibilityIdentifier: "runtime_prompt_log_value",
                    monospaced: settings.promptDiagnosticsLogPath != nil
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )

            HStack {
                Button("Reset to Default") {
                    settings.resetToDefault()
                }

                Spacer()

                Button("Refresh Data") {
                    Task {
                        await viewModel.refreshLibrary()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func diagnosticRow(
        title: String,
        value: String,
        accessibilityIdentifier: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(
                    monospaced
                        ? .system(size: 12, weight: .medium, design: .monospaced)
                        : .subheadline
                )
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.vertical, 2)
    }
}
