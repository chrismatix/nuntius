import Foundation
import os

/// Coordinates between local WhisperKit and cloud OpenAI transcription services.
/// Handles automatic fallback to local when OpenAI is selected but unavailable.
@MainActor
@Observable
final class TranscriptionCoordinator {
    static let shared = TranscriptionCoordinator()

    /// The type of transcription service
    enum ServiceType: String, CaseIterable {
        case local = "local"
        case openai = "openai"

        var displayName: String {
            switch self {
            case .local: return "Local (WhisperKit)"
            case .openai: return "OpenAI Cloud"
            }
        }
    }

    /// Reason for the last fallback to local service
    enum FallbackReason {
        case offline
        case apiError(String)
    }

    /// The currently selected transcription service
    private(set) var selectedService: ServiceType = .local

    /// Whether the coordinator is using fallback (OpenAI selected but using local)
    private(set) var isUsingFallback: Bool = false

    /// The reason for the current fallback, if any
    private(set) var fallbackReason: FallbackReason?

    /// Whether the coordinator is ready to transcribe
    var isReady: Bool {
        switch effectiveService {
        case .local:
            return whisperService.isReady
        case .openai:
            return openAIService.isReady && networkMonitor.isConnected
        }
    }

    /// The service that will actually be used for the next transcription
    var effectiveService: ServiceType {
        if selectedService == .openai {
            if !networkMonitor.isConnected || !openAIService.isReady {
                return .local
            }
        }
        return selectedService
    }

    private let whisperService: WhisperService
    private let openAIService: OpenAITranscriptionService
    private let networkMonitor: NetworkMonitor
    private let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "TranscriptionCoordinator")

    private init(
        whisperService: WhisperService = WhisperService(),
        openAIService: OpenAITranscriptionService = .shared,
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.whisperService = whisperService
        self.openAIService = openAIService
        self.networkMonitor = networkMonitor ?? NetworkMonitor.shared

        // Load saved preference
        let savedService = UserDefaults.standard.string(forKey: "transcriptionService") ?? "local"
        self.selectedService = ServiceType(rawValue: savedService) ?? .local
    }

    /// Provides access to the underlying WhisperService for model management
    var localService: WhisperService {
        whisperService
    }

    /// Sets the state callback for the WhisperService
    func setWhisperStateCallback(_ callback: @escaping @Sendable (WhisperService.State) -> Void) {
        whisperService.setStateCallback(callback)
    }

    /// Ensures the local model is loaded
    func ensureLocalModelLoaded() async throws {
        try await whisperService.ensureModelLoaded()
    }

    /// Unloads the local model
    func unloadLocalModel() async {
        await whisperService.unloadModel()
    }

    /// Selects the transcription service to use
    /// - Parameter service: The service type to select
    func selectService(_ service: ServiceType) {
        guard selectedService != service else { return }

        // Don't allow OpenAI if not configured
        if service == .openai && !openAIService.isReady {
            logger.warning("Cannot select OpenAI service - not configured")
            return
        }

        selectedService = service
        isUsingFallback = false
        fallbackReason = nil
        UserDefaults.standard.set(service.rawValue, forKey: "transcriptionService")

        NotificationCenter.default.post(
            name: Constants.Notifications.transcriptionServiceDidChange,
            object: nil
        )

        logger.info("Transcription service changed to: \(service.rawValue)")
    }

    /// Transcribes audio samples using the selected service (with fallback if needed).
    /// - Parameter samples: Audio samples as Float array
    /// - Returns: Transcribed text
    func transcribe(samples: [Float]) async throws -> String {
        let language = UserDefaults.standard.string(forKey: "selectedLanguage") ?? Constants.defaultLanguage
        let vocab = UserDefaults.standard.string(forKey: "vocabularyPrompt") ?? ""
        let postProcessingEnabled = UserDefaults.standard.bool(forKey: "gptPostProcessingEnabled")

        // Determine which service to use
        if selectedService == .openai {
            if networkMonitor.isConnected && openAIService.isReady {
                // Try OpenAI
                do {
                    var text = try await openAIService.transcribe(
                        samples: samples,
                        language: language == "auto" ? nil : language,
                        prompt: vocab.isEmpty ? nil : vocab
                    )
                    isUsingFallback = false
                    fallbackReason = nil

                    // Apply GPT post-processing if enabled
                    if postProcessingEnabled && !text.isEmpty {
                        text = try await applyPostProcessing(text)
                    }

                    return text
                } catch {
                    // OpenAI failed - fall back to local
                    logger.warning("OpenAI transcription failed, falling back to local: \(error.localizedDescription)")
                    isUsingFallback = true
                    fallbackReason = .apiError(error.localizedDescription)
                    showFallbackNotification(reason: error.localizedDescription)
                    return try await transcribeLocally(samples: samples, language: language, vocab: vocab)
                }
            } else {
                // Offline - fall back to local
                if !networkMonitor.isConnected {
                    logger.info("No network connection, using local transcription")
                    isUsingFallback = true
                    fallbackReason = .offline
                    showFallbackNotification(reason: "No network connection")
                } else if !openAIService.isReady {
                    logger.info("OpenAI not ready, using local transcription")
                    isUsingFallback = true
                    fallbackReason = .apiError("OpenAI service not configured")
                }
                return try await transcribeLocally(samples: samples, language: language, vocab: vocab)
            }
        } else {
            // Local service selected
            isUsingFallback = false
            fallbackReason = nil
            return try await transcribeLocally(samples: samples, language: language, vocab: vocab)
        }
    }

    /// Applies GPT post-processing to improve transcription formatting
    private func applyPostProcessing(_ text: String) async throws -> String {
        do {
            return try await openAIService.postProcess(text: text)
        } catch {
            // If post-processing fails, log and return original text
            logger.warning("Post-processing failed, using original transcription: \(error.localizedDescription)")
            return text
        }
    }

    /// Transcribes using the local WhisperKit service
    private func transcribeLocally(samples: [Float], language: String, vocab: String) async throws -> String {
        await whisperService.setVocabularyPrompt(vocab)
        await whisperService.setLanguage(language)
        return try await whisperService.transcribe(samples: samples)
    }

    /// Shows a notification when falling back to local transcription
    private func showFallbackNotification(reason: String) {
        Task { @MainActor in
            NotificationService.shared.showWarning(
                title: "Using Local Transcription",
                message: "OpenAI unavailable (\(reason)). Using local model instead."
            )
        }
    }
}
