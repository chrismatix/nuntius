import SwiftUI

struct MenuBarView: View {
    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("selectedLanguage") private var selectedLanguage = Constants.defaultLanguage
    @AppStorage("transcriptionService") private var transcriptionService = "local"
    @AppStorage("openAIModel") private var openAIModel = Constants.OpenAI.defaultModel.rawValue
    @State private var modelManager = ModelManager.shared
    @State private var coordinator = TranscriptionCoordinator.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @ObservedObject var updaterController: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nuntius")
                    .font(.headline)

                Spacer()

                serviceIndicator
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Press ⌥ Space to dictate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if modelManager.downloadedModels.isEmpty && transcriptionService == "local" {
                    Text("No models downloaded")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if transcriptionService == "local" {
                    HStack {
                        Text("Model:")
                        Picker("", selection: $selectedModel) {
                            ForEach(modelManager.downloadedModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Language:")
                        LanguagePicker(selectedLanguage: $selectedLanguage)
                            .labelsHidden()
                    }
                } else {
                    // OpenAI service selected
                    if let model = Constants.OpenAI.TranscriptionModel(rawValue: openAIModel) {
                        HStack {
                            Text("Model:")
                            Text(model.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Language:")
                        LanguagePicker(selectedLanguage: $selectedLanguage)
                            .labelsHidden()
                    }

                    if !networkMonitor.isConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi.slash")
                                .foregroundStyle(.orange)
                            Text("Offline - will use local model")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Divider()

            Button("Check for Updates...") {
                updaterController.checkForUpdates()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(!updaterController.canCheckForUpdates)

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            modelManager.refreshModels()
        }
        .onChange(of: selectedModel) { oldValue, newValue in
            _ = modelManager.selectModel(newValue, previousModelId: oldValue)
        }
    }

    @ViewBuilder
    private var serviceIndicator: some View {
        HStack(spacing: 4) {
            if transcriptionService == "openai" {
                if !networkMonitor.isConnected {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Offline - using local model")
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .help("Using OpenAI Cloud")
                }
                Text("Cloud")
                    .font(.caption)
                    .foregroundStyle(networkMonitor.isConnected ? .blue : .orange)
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Using local model")
                Text("Local")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    MenuBarView(updaterController: UpdaterController())
}
