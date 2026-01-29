import Foundation
import os

/// Errors that can occur during OpenAI transcription
enum OpenAITranscriptionError: LocalizedError {
    case invalidAPIKey
    case rateLimitExceeded
    case networkError(Error)
    case serverError(statusCode: Int)
    case invalidResponse
    case audioEncodingFailed
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your OpenAI API key in Settings."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please wait and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let statusCode):
            return "Server error (HTTP \(statusCode)). Please try again later."
        case .invalidResponse:
            return "Invalid response from OpenAI API."
        case .audioEncodingFailed:
            return "Failed to encode audio for transcription."
        case .notConfigured:
            return "OpenAI transcription is not configured. Please add your API key in Settings."
        }
    }
}

/// Thread-safe observer for OpenAITranscriptionService state changes.
final class OpenAIStateObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: OpenAITranscriptionService.State = .notConfigured
    private var _stateCallback: (@Sendable (OpenAITranscriptionService.State) -> Void)?

    var state: OpenAITranscriptionService.State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    func setState(_ value: OpenAITranscriptionService.State) {
        lock.lock()
        _state = value
        let callback = _stateCallback
        lock.unlock()
        callback?(value)
    }

    func setCallback(_ callback: @escaping @Sendable (OpenAITranscriptionService.State) -> Void) {
        lock.lock()
        _stateCallback = callback
        lock.unlock()
    }
}

/// Actor-based service for transcription using OpenAI's gpt-4o-transcribe model.
actor OpenAITranscriptionService {
    static let shared = OpenAITranscriptionService()

    private let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "OpenAITranscriptionService")
    nonisolated let stateObserver = OpenAIStateObserver()

    enum State: Sendable, Equatable {
        case notConfigured
        case ready
        case validating
        case error(String)
    }

    private var apiKey: String?

    private init() {
        // Try to load existing API key on init
        if let key = KeychainService.loadAPIKey(), !key.isEmpty {
            apiKey = key
            // Check if previously validated
            if UserDefaults.standard.bool(forKey: "openAIKeyValidated") {
                stateObserver.setState(.ready)
            }
        }
    }

    nonisolated func setStateCallback(_ callback: @escaping @Sendable (State) -> Void) {
        stateObserver.setCallback(callback)
    }

    nonisolated var currentState: State {
        stateObserver.state
    }

    nonisolated var isReady: Bool {
        stateObserver.state == .ready
    }

    /// Validates an API key by making a lightweight request to the models endpoint.
    /// - Parameter key: The API key to validate
    /// - Returns: True if the key is valid
    func validateAPIKey(_ key: String) async throws -> Bool {
        stateObserver.setState(.validating)

        guard let url = URL(string: Constants.OpenAI.modelsEndpoint) else {
            stateObserver.setState(.error("Invalid API endpoint"))
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                stateObserver.setState(.error("Invalid response"))
                return false
            }

            switch httpResponse.statusCode {
            case 200:
                // Key is valid - save it
                KeychainService.saveAPIKey(key)
                apiKey = key
                UserDefaults.standard.set(true, forKey: "openAIKeyValidated")
                stateObserver.setState(.ready)
                logger.info("API key validated successfully")
                return true

            case 401:
                stateObserver.setState(.error("Invalid API key"))
                UserDefaults.standard.set(false, forKey: "openAIKeyValidated")
                return false

            default:
                stateObserver.setState(.error("Validation failed (HTTP \(httpResponse.statusCode))"))
                return false
            }
        } catch {
            logger.error("API key validation failed: \(error.localizedDescription)")
            stateObserver.setState(.error("Network error: \(error.localizedDescription)"))
            throw OpenAITranscriptionError.networkError(error)
        }
    }

    /// Clears the stored API key and resets state
    func clearAPIKey() {
        KeychainService.deleteAPIKey()
        apiKey = nil
        UserDefaults.standard.set(false, forKey: "openAIKeyValidated")
        stateObserver.setState(.notConfigured)
        logger.info("API key cleared")
    }

    /// Transcribes audio samples using the OpenAI API.
    /// - Parameters:
    ///   - samples: Audio samples as Float array (normalized to -1.0 to 1.0)
    ///   - language: Optional ISO-639-1 language code (e.g., "en", "es")
    ///   - prompt: Optional vocabulary hint to improve recognition
    /// - Returns: Transcribed text
    func transcribe(samples: [Float], language: String? = nil, prompt: String? = nil) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw OpenAITranscriptionError.notConfigured
        }

        // Encode samples as WAV
        guard let wavData = AudioWAVEncoder.encode(samples: samples, sampleRate: 16000) else {
            throw OpenAITranscriptionError.audioEncodingFailed
        }

        logger.debug("Encoded \(samples.count) samples to WAV (\(wavData.count) bytes)")

        // Build multipart form data request
        let boundary = UUID().uuidString
        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        // Add file field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n")

        // Add model field
        let modelId = UserDefaults.standard.string(forKey: "openAIModel") ?? Constants.OpenAI.defaultModel.rawValue
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(modelId)\r\n")

        // Add language field if specified
        if let language = language, language != "auto", !language.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(language)\r\n")
        }

        // Add prompt field if specified
        if let prompt = prompt, !prompt.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(prompt)\r\n")
        }

        append("--\(boundary)--\r\n")

        guard let url = URL(string: Constants.OpenAI.transcriptionEndpoint) else {
            throw OpenAITranscriptionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAITranscriptionError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                // Parse JSON response
                struct TranscriptionResponse: Decodable {
                    let text: String
                }

                let transcription = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                logger.info("Transcription successful: \(transcription.text.prefix(50))...")
                return transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)

            case 401:
                // API key became invalid
                UserDefaults.standard.set(false, forKey: "openAIKeyValidated")
                stateObserver.setState(.error("API key invalid"))
                throw OpenAITranscriptionError.invalidAPIKey

            case 429:
                throw OpenAITranscriptionError.rateLimitExceeded

            default:
                logger.error("Transcription failed with status \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("Error response: \(errorText)")
                }
                throw OpenAITranscriptionError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as OpenAITranscriptionError {
            throw error
        } catch {
            logger.error("Transcription request failed: \(error.localizedDescription)")
            throw OpenAITranscriptionError.networkError(error)
        }
    }

    /// Post-processes a transcription using GPT to improve formatting and accuracy.
    /// - Parameter text: The raw transcription text
    /// - Returns: Post-processed text with improved formatting
    func postProcess(text: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw OpenAITranscriptionError.notConfigured
        }

        guard let url = URL(string: Constants.OpenAI.chatCompletionsEndpoint) else {
            throw OpenAITranscriptionError.invalidResponse
        }

        let systemPrompt = """
            You are a transcription post-processor. Your task is to clean up and improve speech-to-text output.

            Rules:
            - Add proper punctuation (periods, commas, question marks, exclamation points)
            - Fix capitalization (sentence starts, proper nouns)
            - Correct obvious speech-to-text errors where context makes the intended word clear
            - Format numbers appropriately (e.g., "two hundred dollars" → "$200")
            - Keep the original meaning exactly - never add, remove, or change the substance
            - Do not add any commentary - output only the cleaned transcription
            - If the input is already well-formatted, return it as-is
            """

        let requestBody: [String: Any] = [
            "model": Constants.OpenAI.postProcessingModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.1,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAITranscriptionError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                struct ChatResponse: Decodable {
                    struct Choice: Decodable {
                        struct Message: Decodable {
                            let content: String
                        }
                        let message: Message
                    }
                    let choices: [Choice]
                }

                let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
                guard let content = chatResponse.choices.first?.message.content else {
                    logger.warning("Post-processing returned empty response, using original text")
                    return text
                }
                logger.info("Post-processing successful")
                return content.trimmingCharacters(in: .whitespacesAndNewlines)

            case 401:
                UserDefaults.standard.set(false, forKey: "openAIKeyValidated")
                stateObserver.setState(.error("API key invalid"))
                throw OpenAITranscriptionError.invalidAPIKey

            case 429:
                throw OpenAITranscriptionError.rateLimitExceeded

            default:
                logger.error("Post-processing failed with status \(httpResponse.statusCode)")
                throw OpenAITranscriptionError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as OpenAITranscriptionError {
            throw error
        } catch {
            logger.error("Post-processing request failed: \(error.localizedDescription)")
            throw OpenAITranscriptionError.networkError(error)
        }
    }

}
