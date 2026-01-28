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
        guard let wavData = encodeWAV(samples: samples, sampleRate: 16000) else {
            throw OpenAITranscriptionError.audioEncodingFailed
        }

        logger.debug("Encoded \(samples.count) samples to WAV (\(wavData.count) bytes)")

        // Build multipart form data request
        let boundary = UUID().uuidString
        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.append("\r\n")

        // Add model field
        let modelId = UserDefaults.standard.string(forKey: "openAIModel") ?? Constants.OpenAI.defaultModel.rawValue
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("\(modelId)\r\n")

        // Add language field if specified
        if let language = language, language != "auto", !language.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.append("\(language)\r\n")
        }

        // Add prompt field if specified
        if let prompt = prompt, !prompt.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.append("\(prompt)\r\n")
        }

        body.append("--\(boundary)--\r\n")

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

    /// Encodes audio samples as a WAV file.
    /// - Parameters:
    ///   - samples: Audio samples as Float array (normalized to -1.0 to 1.0)
    ///   - sampleRate: Sample rate in Hz (default 16000)
    /// - Returns: WAV file data, or nil if encoding failed
    private func encodeWAV(samples: [Float], sampleRate: Int = 16000) -> Data? {
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign: Int16 = numChannels * (bitsPerSample / 8)
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let chunkSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: chunkSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: Int32(16)) // Subchunk1Size (16 for PCM)
        data.append(littleEndian: Int16(1))  // AudioFormat (1 for PCM)
        data.append(littleEndian: numChannels)
        data.append(littleEndian: Int32(sampleRate))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bitsPerSample)

        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)

        // Convert Float samples to Int16
        for sample in samples {
            // Clamp and convert to Int16 range
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * Float(Int16.max))
            data.append(littleEndian: int16Sample)
        }

        return data
    }
}

// MARK: - Data Extension for WAV Encoding

private extension Data {
    mutating func append(littleEndian value: Int16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { buffer in
            append(contentsOf: buffer)
        }
    }

    mutating func append(littleEndian value: Int32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { buffer in
            append(contentsOf: buffer)
        }
    }

    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
