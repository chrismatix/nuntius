import SwiftUI

struct SettingsView: View {
    @ObservedObject var updaterController: UpdaterController

    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("outputMode") private var outputMode = "paste"
    @AppStorage("hotkeyDisplay") private var hotkeyDisplay = "⌥ Space"
    @AppStorage("vocabularyPrompt") private var vocabularyPrompt = ""
    @AppStorage("selectedLanguage") private var selectedLanguage = Constants.defaultLanguage
    @AppStorage("transcriptionService") private var transcriptionService = "local"
    @AppStorage("openAIKeyValidated") private var openAIKeyValidated = false
    @AppStorage("openAIModel") private var openAIModel = Constants.OpenAI.defaultModel.rawValue

    @State private var modelManager = ModelManager.shared
    @State private var coordinator = TranscriptionCoordinator.shared
    @State private var errorMessage: String?
    @State private var showError = false

    @State private var selectedTab = "general"

    // Cloud tab state
    @State private var apiKeyInput = ""
    @State private var isValidatingKey = false
    @State private var validationError: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tag("general")
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            modelsTab
                .tag("models")
                .tabItem {
                    Label("Models", systemImage: "cube.box")
                }

            vocabularyTab
                .tag("vocabulary")
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed")
                }

            cloudTab
                .tag("cloud")
                .tabItem {
                    Label("Cloud", systemImage: "cloud")
                }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            modelManager.refreshModels()
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { }
        } message: { message in
            Text(message)
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker("After transcription", selection: $outputMode) {
                    Text("Copy to clipboard").tag("clipboard")
                    Text("Paste into active app").tag("paste")
                }
                .pickerStyle(.radioGroup)

                if outputMode == "paste" {
                    Text("Requires Accessibility permission in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Output")
            }

            Section {
                HStack {
                    Text("Press to talk:")
                    Spacer()
                    Text(hotkeyDisplay)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text("Hotkey customization will be available in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkey")
            }

            Section {
                LanguagePicker(selectedLanguage: $selectedLanguage)

                Text("Select a specific language or use auto-detect to identify it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Language")
            }

            Section {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { updaterController.automaticallyChecksForUpdates },
                        set: { enabled in
                            updaterController.setAutomaticallyChecksForUpdates(enabled)
                        }
                    )
                )
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }

    private var modelsTab: some View {
        Form {
            Section {
                ForEach(modelManager.models) { model in
                    ModelRow(
                        model: model,
                        isSelected: selectedModel == model.id,
                        onSelect: {
                            guard model.isDownloaded else { return }
                            let previousModelId = selectedModel
                            guard modelManager.selectModel(model.id, previousModelId: previousModelId) else { return }
                            selectedModel = model.id
                        },
                        onDownload: {
                            Task {
                                do {
                                    try await modelManager.downloadModel(model.id)
                                } catch {
                                    presentError("Failed to download \(model.name): \(error.localizedDescription)")
                                }
                            }
                        },
                        onDelete: {
                            do {
                                try modelManager.deleteModel(model.id)
                            } catch {
                                presentError("Failed to delete \(model.name): \(error.localizedDescription)")
                            }
                        }
                    )
                }

                Text("Larger models are more accurate but slower and use more memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Models")
            }
        }
        .formStyle(.grouped)
    }

    private var vocabularyTab: some View {
        Form {
            Section {
                TextEditor(text: $vocabularyPrompt)
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .font(.body.monospaced())

                Text("Add names, technical terms, or jargon to improve recognition. One per line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Custom Vocabulary")
            }
        }
        .formStyle(.grouped)
    }

    private var cloudTab: some View {
        Form {
            Section {
                Picker("Transcription Service", selection: $transcriptionService) {
                    Text("Local (WhisperKit)").tag("local")
                    if openAIKeyValidated {
                        Text("OpenAI Cloud").tag("openai")
                    } else {
                        Text("OpenAI Cloud (API key required)").tag("openai")
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: transcriptionService) { _, newValue in
                    // Prevent selecting OpenAI without a validated key
                    if newValue == "openai" && !openAIKeyValidated {
                        transcriptionService = "local"
                        return
                    }
                    if let service = TranscriptionCoordinator.ServiceType(rawValue: newValue) {
                        coordinator.selectService(service)
                    }
                }

                if transcriptionService == "local" {
                    Text("Uses on-device WhisperKit models. Works offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Uses OpenAI cloud transcription. Falls back to local when offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Service")
            }

            if transcriptionService == "openai" {
                Section {
                    Picker("Model", selection: $openAIModel) {
                        ForEach(Constants.OpenAI.TranscriptionModel.allCases, id: \.rawValue) { model in
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                            }
                            .tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if let selectedModel = Constants.OpenAI.TranscriptionModel(rawValue: openAIModel) {
                        Text(selectedModel.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("OpenAI Model")
                }
            }

            Section {
                HStack {
                    SecureField("OpenAI API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    if isValidatingKey {
                        ProgressView()
                            .controlSize(.small)
                    } else if openAIKeyValidated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if validationError != nil {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }

                    Button("Validate") {
                        validateAPIKey()
                    }
                    .disabled(apiKeyInput.isEmpty || isValidatingKey)
                }

                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if openAIKeyValidated {
                    HStack {
                        Text("API key validated and stored securely in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Spacer()

                        Button("Remove Key") {
                            removeAPIKey()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                } else {
                    Text("Your API key is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("OpenAI API Key")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get an API key:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Visit platform.openai.com")
                        Text("2. Sign in or create an account")
                        Text("3. Go to API Keys in your account settings")
                        Text("4. Create a new secret key and paste it above")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Help")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Load existing key if available (masked)
            if openAIKeyValidated {
                apiKeyInput = "sk-••••••••••••••••"
            }
        }
    }

    private func validateAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        // Don't validate if it's the masked placeholder
        guard !apiKeyInput.hasPrefix("sk-••") else { return }

        isValidatingKey = true
        validationError = nil

        Task {
            do {
                let isValid = try await OpenAITranscriptionService.shared.validateAPIKey(apiKeyInput)
                await MainActor.run {
                    isValidatingKey = false
                    if isValid {
                        openAIKeyValidated = true
                        apiKeyInput = "sk-••••••••••••••••"
                        validationError = nil
                    } else {
                        validationError = "Invalid API key. Please check and try again."
                    }
                }
            } catch {
                await MainActor.run {
                    isValidatingKey = false
                    validationError = error.localizedDescription
                }
            }
        }
    }

    private func removeAPIKey() {
        Task {
            await OpenAITranscriptionService.shared.clearAPIKey()
            await MainActor.run {
                openAIKeyValidated = false
                apiKeyInput = ""
                validationError = nil
                // Switch back to local if currently using OpenAI
                if transcriptionService == "openai" {
                    transcriptionService = "local"
                    coordinator.selectService(.local)
                }
            }
        }
    }
}

struct LanguagePicker: View {
    @Binding var selectedLanguage: String

    var body: some View {
        Picker("Language", selection: $selectedLanguage) {
            Text("Auto-detect").tag("auto")
            Divider()
            ForEach(Constants.sortedLanguages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        }
    }
}

struct ModelRow: View {
    let model: ModelManager.Model
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(model.sizeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailingContent
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded {
                onSelect()
            }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if model.isDownloading {
            downloadingContent
        } else if model.isDownloaded {
            downloadedContent
        } else {
            downloadButton
        }
    }

    @ViewBuilder
    private var downloadingContent: some View {
        ProgressView(value: model.downloadProgress)
            .progressViewStyle(.linear)
            .frame(width: 80)

        Text("\(Int(model.downloadProgress * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 35, alignment: .trailing)
    }

    @ViewBuilder
    private var downloadedContent: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        } else {
            selectButton
        }

        deleteButton
    }

    private var selectButton: some View {
        Button("Select") {
            onSelect()
        }
        .buttonStyle(.borderless)
    }

    private var deleteButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Delete model")
    }

    private var downloadButton: some View {
        Button("Download") {
            onDownload()
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    SettingsView(updaterController: UpdaterController())
}
