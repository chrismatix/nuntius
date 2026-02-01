import AVFoundation
import Foundation
import os

final class AudioCaptureService {
    private var engine: AVAudioEngine?
    private let targetSampleRate: Double = 16_000
    private let converterQueue = DispatchQueue(label: "com.chrismatix.nuntius.audioconverter")
    private var converter: AVAudioConverter?

    private let queue = DispatchQueue(label: "com.chrismatix.nuntius.audiocapture")
    private var capturedSamples: [Float] = []
    private var _isCapturing = false
    private var _isEngineRunning = false
    private let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "AudioCaptureService")

    var onAudioLevel: ((Float) -> Void)?
    var onConversionError: ((Error) -> Void)?

    private var isCapturing: Bool {
        get { queue.sync { _isCapturing } }
        set { queue.sync { _isCapturing = newValue } }
    }

    private var isEngineRunning: Bool {
        get { queue.sync { _isEngineRunning } }
        set { queue.sync { _isEngineRunning = newValue } }
    }

    private func getConverter() -> AVAudioConverter? {
        converterQueue.sync { converter }
    }

    private func setConverter(_ newConverter: AVAudioConverter?) {
        converterQueue.sync { converter = newConverter }
    }

    /// Warms up the audio engine by starting it without collecting samples.
    /// This keeps the microphone hardware active so recording can start instantly.
    func warmUp() throws {
        guard !isEngineRunning else { return }

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidFormat
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        setConverter(converter)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            isEngineRunning = true
            logger.info("Audio engine warmed up and running")
        } catch {
            shutDown()
            throw error
        }
    }

    /// Shuts down the audio engine completely, releasing the microphone.
    func shutDown() {
        isCapturing = false
        isEngineRunning = false

        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        self.engine = nil
        setConverter(nil)
        logger.info("Audio engine shut down")
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        queue.sync { capturedSamples.removeAll() }

        // If engine isn't already warm, start it now
        if !isEngineRunning {
            try warmUp()
        }

        isCapturing = true
        logger.info("Audio capture started")
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        shutDown()
        logger.info("Audio capture stopped and engine shut down")
    }

    func currentSamples() -> [Float] {
        queue.sync { capturedSamples }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // Safely capture converter reference before checking state
        guard let converter = getConverter() else { return }

        // Always calculate audio level for visual feedback when capturing
        if isCapturing {
            let rms = calculateRms(from: buffer)
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(rms)
            }
        }

        // Only collect samples when actively capturing
        guard isCapturing else { return }

        let conversionResult = convertBuffer(buffer, using: converter)
        if let error = conversionResult.error {
            logger.error("Audio conversion failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onConversionError?(AudioCaptureError.conversionFailed(error))
            }
            return
        }

        guard let convertedBuffer = conversionResult.buffer else { return }

        if let channelData = convertedBuffer.floatChannelData?[0] {
            let frames = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))

            queue.async { [weak self] in
                self?.capturedSamples.append(contentsOf: samples)
            }
        }
    }

    private func calculateRms(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames {
            sum += channelData[i] * channelData[i]
        }
        return sqrt(sum / Float(frames))
    }

    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> (buffer: AVAudioPCMBuffer?, error: Error?) {
        // Convert to 16kHz mono
        let outputFormat = converter.outputFormat
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(targetSampleRate / 10)
        ) else {
            return (nil, nil)
        }

        var error: NSError?
        var hasProvidedBuffer = false

        // Capture buffer in the conversion callback to avoid race conditions
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            guard !hasProvidedBuffer else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            hasProvidedBuffer = true
            return buffer
        }

        return (convertedBuffer, error)
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case invalidFormat
    case converterUnavailable
    case conversionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format configuration"
        case .converterUnavailable:
            return "Audio converter could not be created"
        case .conversionFailed(let error):
            return "Audio conversion failed: \(error.localizedDescription)"
        }
    }
}
