import Foundation
import os

/// Application-wide constants and notification names
enum Constants {
    /// Notification names used throughout the application
    enum Notifications {
        /// Posted when the selected Whisper model changes
        static let modelDidChange = Notification.Name("com.chrismatix.nuntius.modelDidChange")

        /// Posted when a model download starts/progresses/finishes
        static let modelDownloadStateDidChange = Notification.Name("com.chrismatix.nuntius.modelDownloadStateDidChange")

        /// Posted when the transcription service (local vs cloud) changes
        static let transcriptionServiceDidChange = Notification.Name("com.chrismatix.nuntius.transcriptionServiceDidChange")
    }

    /// OpenAI API configuration
    enum OpenAI {
        /// Transcription API endpoint
        static let transcriptionEndpoint = "https://api.openai.com/v1/audio/transcriptions"

        /// Models API endpoint for validation
        static let modelsEndpoint = "https://api.openai.com/v1/models"

        /// Available transcription models
        enum TranscriptionModel: String, CaseIterable {
            case gpt4oTranscribe = "gpt-4o-transcribe"
            case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
            case whisper1 = "whisper-1"

            var displayName: String {
                switch self {
                case .gpt4oTranscribe: return "GPT-4o Transcribe (Best)"
                case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
                case .whisper1: return "Whisper"
                }
            }

            var description: String {
                switch self {
                case .gpt4oTranscribe: return "Highest accuracy, $0.006/min"
                case .gpt4oMiniTranscribe: return "Good accuracy, $0.003/min"
                case .whisper1: return "Legacy model, $0.006/min"
                }
            }
        }

        /// Default transcription model
        static let defaultModel: TranscriptionModel = .gpt4oTranscribe

        /// Keychain service identifier for API key storage
        static let keychainService = "com.chrismatix.nuntius.openai"
    }

    /// Unified model representation for both local and cloud models
    struct UnifiedModel: Identifiable, Hashable {
        enum ModelType: Hashable {
            case local
            case cloud(OpenAI.TranscriptionModel)
        }

        let id: String
        let name: String
        let description: String
        let sizeOrCost: String
        let type: ModelType

        var isCloud: Bool {
            if case .cloud = type { return true }
            return false
        }

        var cloudModel: OpenAI.TranscriptionModel? {
            if case .cloud(let model) = type { return model }
            return nil
        }

        /// Creates a unified model from a local ModelManager.Model
        static func fromLocal(_ model: ModelManager.Model) -> UnifiedModel {
            UnifiedModel(
                id: model.id,
                name: model.name,
                description: model.description,
                sizeOrCost: model.sizeHint,
                type: .local
            )
        }

        /// Creates unified models for all available OpenAI cloud models
        static func cloudModels() -> [UnifiedModel] {
            OpenAI.TranscriptionModel.allCases.map { model in
                UnifiedModel(
                    id: "openai:\(model.rawValue)",
                    name: model.displayName,
                    description: model.description,
                    sizeOrCost: "Cloud",
                    type: .cloud(model)
                )
            }
        }
    }

    /// Supported Whisper transcription languages (from WhisperKit)
    static let languages: [String: String] = [
        "afrikaans": "af", "albanian": "sq", "amharic": "am", "arabic": "ar",
        "armenian": "hy", "assamese": "as", "azerbaijani": "az", "bashkir": "ba",
        "basque": "eu", "belarusian": "be", "bengali": "bn", "bosnian": "bs",
        "breton": "br", "bulgarian": "bg", "burmese": "my", "cantonese": "yue",
        "castilian": "es", "catalan": "ca", "chinese": "zh", "croatian": "hr",
        "czech": "cs", "danish": "da", "dutch": "nl", "english": "en",
        "estonian": "et", "faroese": "fo", "finnish": "fi", "flemish": "nl",
        "french": "fr", "galician": "gl", "georgian": "ka", "german": "de",
        "greek": "el", "gujarati": "gu", "haitian": "ht", "haitian creole": "ht",
        "hausa": "ha", "hawaiian": "haw", "hebrew": "he", "hindi": "hi",
        "hungarian": "hu", "icelandic": "is", "indonesian": "id", "italian": "it",
        "japanese": "ja", "javanese": "jw", "kannada": "kn", "kazakh": "kk",
        "khmer": "km", "korean": "ko", "lao": "lo", "latin": "la",
        "latvian": "lv", "letzeburgesch": "lb", "lingala": "ln", "lithuanian": "lt",
        "luxembourgish": "lb", "macedonian": "mk", "malagasy": "mg", "malay": "ms",
        "malayalam": "ml", "maltese": "mt", "mandarin": "zh", "maori": "mi",
        "marathi": "mr", "moldavian": "ro", "moldovan": "ro", "mongolian": "mn",
        "myanmar": "my", "nepali": "ne", "norwegian": "no", "nynorsk": "nn",
        "occitan": "oc", "panjabi": "pa", "pashto": "ps", "persian": "fa",
        "polish": "pl", "portuguese": "pt", "punjabi": "pa", "pushto": "ps",
        "romanian": "ro", "russian": "ru", "sanskrit": "sa", "serbian": "sr",
        "shona": "sn", "sindhi": "sd", "sinhala": "si", "sinhalese": "si",
        "slovak": "sk", "slovenian": "sl", "somali": "so", "spanish": "es",
        "sundanese": "su", "swahili": "sw", "swedish": "sv", "tagalog": "tl",
        "tajik": "tg", "tamil": "ta", "tatar": "tt", "telugu": "te",
        "thai": "th", "tibetan": "bo", "turkish": "tr", "turkmen": "tk",
        "ukrainian": "uk", "urdu": "ur", "uzbek": "uz", "valencian": "ca",
        "vietnamese": "vi", "welsh": "cy", "yiddish": "yi", "yoruba": "yo"
    ]

    // some language codes have multiple names in WhisperKit; pick one for UI
    private static let preferredLanguageNameByCode: [String: String] = [
        "ca": "catalan",
        "es": "spanish",
        "ht": "haitian creole",
        "lb": "luxembourgish",
        "my": "burmese",
        "nl": "dutch",
        "pa": "punjabi",
        "ps": "pashto",
        "ro": "romanian",
        "si": "sinhala",
        "zh": "chinese"
    ]

    private static let languageDisplayNameByCode: [String: String] = {
        var byCode: [String: String] = [:]

        for (name, code) in languages {
            if let preferred = preferredLanguageNameByCode[code], name == preferred {
                byCode[code] = name
                continue
            }
            if byCode[code] == nil {
                byCode[code] = name
            }
        }

        // ensure preferred names win deterministically
        for (code, preferredName) in preferredLanguageNameByCode {
            if languages[preferredName] == code {
                byCode[code] = preferredName
            }
        }

        return byCode
    }()

    /// Pre-sorted languages for UI display (cached to avoid repeated sorting)
    static let sortedLanguages: [(name: String, code: String)] = {
        languageDisplayNameByCode
            .map { (name: $0.value.capitalized, code: $0.key) }
            .sorted { $0.name < $1.name }
    }()

    /// Valid language codes for validation (includes all unique codes from languages dict)
    static let validLanguageCodes: Set<String> = Set(languageDisplayNameByCode.keys)

    /// Default language based on system locale, falls back to "auto" if unsupported
    static let defaultLanguage: String = {
        guard let languageCode = Locale.current.language.languageCode?.identifier else {
            return "auto"
        }

        // Check if the system language is supported by Whisper
        if validLanguageCodes.contains(languageCode) {
            return languageCode
        }

        return "auto"
    }()

    /// Helper for locating Whisper model files
    enum ModelPaths {
        private static let repoName = "argmaxinc/whisperkit-coreml"
        private static let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "ModelPaths")

        /// Returns the base directory where models are stored
        static func modelsBaseURL() -> URL? {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return docs
                .appendingPathComponent("huggingface")
                .appendingPathComponent("models")
                .appendingPathComponent(repoName)
        }

        /// Finds the local folder for a specific model ID
        /// - Parameter modelId: The model identifier (e.g., "base", "tiny", "large-v3")
        /// - Returns: URL to the model folder if found, nil otherwise
        static func localModelFolder(for modelId: String) -> URL? {
            guard let base = modelsBaseURL() else { return nil }

            let fm = FileManager.default
            guard fm.fileExists(atPath: base.path) else { return nil }

            let contents: [String]
            do {
                contents = try fm.contentsOfDirectory(atPath: base.path)
            } catch {
                logger.warning("Failed to read model directory at \(base.path): \(error.localizedDescription)")
                return nil
            }

            let suffixPattern = "-\(modelId)"

            for folder in contents {
                let matchesExactSuffix = folder.hasSuffix(suffixPattern)
                let matchesExactName = folder == modelId

                guard matchesExactSuffix || matchesExactName else {
                    continue
                }

                let folderURL = base.appendingPathComponent(folder)
                let configPath = folderURL.appendingPathComponent("config.json")

                guard fm.fileExists(atPath: configPath.path) else {
                    continue
                }

                return folderURL
            }

            return nil
        }
    }
}
