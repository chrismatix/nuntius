import Foundation

enum AudioWAVEncoder {
    /// Encodes audio samples as a WAV file.
    /// - Parameters:
    ///   - samples: Audio samples as Float array (normalized to -1.0 to 1.0)
    ///   - sampleRate: Sample rate in Hz (default 16000)
    /// - Returns: WAV file data, or nil if encoding failed
    static func encode(samples: [Float], sampleRate: Int = 16000) -> Data? {
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
