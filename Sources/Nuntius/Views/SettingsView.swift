import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("outputMode") private var outputMode = "paste"
    @AppStorage("hotkeyDisplay") private var hotkeyDisplay = "⌥ Space"
    @AppStorage("vocabularyPrompt") private var vocabularyPrompt = ""
    @AppStorage("selectedLanguage") private var selectedLanguage = Constants.defaultLanguage
    @AppStorage("transcriptionService") private var transcriptionService = "local"
    @AppStorage("openAIKeyValidated") private var openAIKeyValidated = false
    @AppStorage("openAIModel") private var openAIModel = Constants.OpenAI.defaultModel.rawValue
    @AppStorage("gptPostProcessingEnabled") private var gptPostProcessingEnabled = false
    @AppStorage("saveRecordingsEnabled") private var saveRecordingsEnabled = false
    @AppStorage("saveTranscriptsEnabled") private var saveTranscriptsEnabled = false
    @AppStorage("recordingsFolder") private var recordingsFolder = ""

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

            snippetsTab
                .tag("snippets")
                .tabItem {
                    Label("Snippets", systemImage: "text.badge.plus")
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
                Toggle("Save audio recordings", isOn: $saveRecordingsEnabled)
                Toggle("Save transcripts", isOn: $saveTranscriptsEnabled)

                HStack {
                    Text("Folder:")
                    Spacer()
                    Text(displayFolderPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") {
                        selectFolder()
                    }
                }

                Text("Recordings and transcripts will be saved to the selected folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Storage")
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
                            transcriptionService = "local"
                            coordinator.selectService(.local)
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
                Text("Local Models")
            }

            if openAIKeyValidated {
                Section {
                    ForEach(Constants.UnifiedModel.cloudModels()) { cloudModel in
                        CloudModelRow(
                            model: cloudModel,
                            isSelected: transcriptionService == "openai" && openAIModel == cloudModel.cloudModel?.rawValue,
                            onSelect: {
                                if let model = cloudModel.cloudModel {
                                    openAIModel = model.rawValue
                                    transcriptionService = "openai"
                                    coordinator.selectService(.openai)
                                }
                            }
                        )
                    }

                    Text("Cloud models require internet. Falls back to local model when offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Cloud Models (OpenAI)")
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "cloud")
                            .foregroundStyle(.secondary)
                        Text("Configure an OpenAI API key in the Cloud tab to enable cloud models.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Cloud Models")
                }
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

    private var snippetsTab: some View {
        SnippetsView()
    }

    private var cloudTab: some View {
        Form {
            Section {
                if openAIKeyValidated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("OpenAI cloud models are enabled")
                    }
                    Text("Select a cloud model in the Models tab to use OpenAI transcription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Text("API key required to enable cloud models")
                    }
                    Text("Add your OpenAI API key below to unlock cloud transcription models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            }

            if openAIKeyValidated {
                Section {
                    Toggle("GPT post-processing", isOn: $gptPostProcessingEnabled)

                    Text("Uses GPT to improve transcription formatting: adds punctuation, fixes capitalization, and corrects obvious errors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Post-Processing")
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

    private var displayFolderPath: String {
        if recordingsFolder.isEmpty {
            return defaultRecordingsFolder
        }
        return (recordingsFolder as NSString).abbreviatingWithTildeInPath
    }

    private var defaultRecordingsFolder: String {
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsURL.appendingPathComponent("nuntius").path
        }
        return "~/Documents/nuntius"
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to store recordings and transcripts"
        panel.prompt = "Select"

        // Set initial directory
        if !recordingsFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: recordingsFolder)
        } else if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = documentsURL
        }

        if panel.runModal() == .OK, let url = panel.url {
            recordingsFolder = url.path
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

struct CloudModelRow: View {
    let model: Constants.UnifiedModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Image(systemName: "cloud.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            } else {
                Button("Select") {
                    onSelect()
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

#Preview {
    SettingsView()
}
