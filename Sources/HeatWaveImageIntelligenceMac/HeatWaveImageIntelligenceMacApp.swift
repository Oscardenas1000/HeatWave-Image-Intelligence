import HeatWaveImageClientCore
import SwiftUI

@main
struct HeatWaveImageIntelligenceMacApp: App {
    @State private var settings: AppSettings
    @State private var viewModel: AppViewModel

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _viewModel = State(initialValue: AppViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("HeatWave Image Intelligence") {
            ContentView(viewModel: viewModel, settings: settings)
                .frame(minWidth: 1240, minHeight: 820)
        }

        Settings {
            SettingsView(settings: settings, viewModel: viewModel)
                .frame(width: 460)
                .frame(minHeight: 320)
                .padding(24)
        }
    }
}
