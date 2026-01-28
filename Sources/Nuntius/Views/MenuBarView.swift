import SwiftUI

struct MenuBarView: View {
    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("selectedLanguage") private var selectedLanguage = Constants.defaultLanguage
    @AppStorage("transcriptionService") private var transcriptionService = "local"
    @AppStorage("openAIModel") private var openAIModel = Constants.OpenAI.defaultModel.rawValue
    @AppStorage("openAIKeyValidated") private var openAIKeyValidated = false
    @State private var modelManager = ModelManager.shared
    @State private var coordinator = TranscriptionCoordinator.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @ObservedObject var updaterController: UpdaterController

    /// Combined ID for the unified model picker
    private var unifiedModelSelection: String {
        if transcriptionService == "openai" {
            return "openai:\(openAIModel)"
        }
        return selectedModel
    }

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

                if modelManager.downloadedModels.isEmpty && !openAIKeyValidated {
                    Text("No models available")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Model:")
                        Picker("", selection: Binding(
                            get: { unifiedModelSelection },
                            set: { newValue in
                                if newValue.hasPrefix("openai:") {
                                    let modelId = String(newValue.dropFirst("openai:".count))
                                    openAIModel = modelId
                                    transcriptionService = "openai"
                                    coordinator.selectService(.openai)
                                } else {
                                    let previousModelId = selectedModel
                                    if modelManager.selectModel(newValue, previousModelId: previousModelId) {
                                        selectedModel = newValue
                                        transcriptionService = "local"
                                        coordinator.selectService(.local)
                                    }
                                }
                            }
                        )) {
                            // Local models section
                            if !modelManager.downloadedModels.isEmpty {
                                Section("Local") {
                                    ForEach(modelManager.downloadedModels) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                            }

                            // Cloud models section
                            if openAIKeyValidated {
                                Section("Cloud") {
                                    ForEach(Constants.UnifiedModel.cloudModels()) { cloudModel in
                                        Label(cloudModel.name, systemImage: "cloud.fill")
                                            .tag(cloudModel.id)
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Language:")
                        LanguagePicker(selectedLanguage: $selectedLanguage)
                            .labelsHidden()
                    }

                    if transcriptionService == "openai" && !networkMonitor.isConnected {
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
