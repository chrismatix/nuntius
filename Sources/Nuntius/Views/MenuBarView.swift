import SwiftUI

struct MenuBarView: View {
    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("selectedLanguage") private var selectedLanguage = Constants.defaultLanguage
    @AppStorage("transcriptionService") private var transcriptionService = "local"
    @AppStorage("openAIModel") private var openAIModel = Constants.OpenAI.defaultModel.rawValue
    @AppStorage("openAIKeyValidated") private var openAIKeyValidated = false
    @AppStorage("recordingMode") private var recordingMode = "pushToTalk"
    @State private var modelManager = ModelManager.shared
    @State private var coordinator = TranscriptionCoordinator.shared
    @State private var networkMonitor = NetworkMonitor.shared

    /// Combined ID for the unified model picker
    private var unifiedModelSelection: String {
        if transcriptionService == "openai" {
            return "openai:\(openAIModel)"
        }
        return selectedModel
    }

    private var hotkeyHint: String {
        recordingMode == "tapToToggle" ? "Tap ⌥ Space to start/stop" : "Hold ⌥ Space to dictate"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)

            // Hotkey hint
            hotkeySection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 12)

            // Options
            if modelManager.downloadedModels.isEmpty && !openAIKeyValidated {
                noModelsSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                optionsSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            // Offline warning
            if transcriptionService == "openai" && !networkMonitor.isConnected {
                offlineWarning
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()
                .padding(.horizontal, 12)

            // Footer
            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 280)
        .onAppear {
            modelManager.refreshModels()
        }
        .onChange(of: selectedModel) { oldValue, newValue in
            _ = modelManager.selectModel(newValue, previousModelId: oldValue)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text("Nuntius")
                    .font(.headline)
            }

            Spacer()

            serviceIndicator
        }
    }

    @ViewBuilder
    private var serviceIndicator: some View {
        HStack(spacing: 4) {
            if transcriptionService == "openai" {
                if !networkMonitor.isConnected {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Text("Cloud")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(networkMonitor.isConnected ? .blue : .orange)
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Local")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.8))
        .clipShape(Capsule())
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        Text(hotkeyHint)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - No Models

    private var noModelsSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("No models available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Spacer()

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
                    if !modelManager.downloadedModels.isEmpty {
                        Section("Local") {
                            ForEach(modelManager.downloadedModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }

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
                Text("Language")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Spacer()

                LanguagePicker(selectedLanguage: $selectedLanguage)
                    .labelsHidden()
            }

            HStack {
                Text("Mode")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Spacer()

                Picker("", selection: $recordingMode) {
                    Text("Hold to talk").tag("pushToTalk")
                    Text("Tap to toggle").tag("tapToToggle")
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Offline Warning

    private var offlineWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text("Offline – using local model")
                .font(.caption)
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            SettingsLink {
                Label("Settings", systemImage: "gear")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    MenuBarView()
}
