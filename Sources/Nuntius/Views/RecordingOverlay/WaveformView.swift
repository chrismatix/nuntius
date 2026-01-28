import Foundation
import SwiftUI

struct OverlayMessage: Equatable {
    let text: String
    let icon: String
}

@MainActor
final class WaveformView: ObservableObject {
    @Published private var circularBuffer: [Float] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var message: OverlayMessage?

    private let maxSamples = 60
    private var writeIndex = 0
    private var isFull = false

    var levels: [Float] {
        guard isFull else {
            return circularBuffer
        }
        // Return levels in chronological order (oldest to newest)
        return Array(circularBuffer[writeIndex...]) + Array(circularBuffer[..<writeIndex])
    }

    func addLevel(_ level: Float) {
        if circularBuffer.count < maxSamples {
            circularBuffer.append(level)
        } else {
            // Use circular buffer: overwrite oldest sample
            isFull = true
            circularBuffer[writeIndex] = level
            writeIndex = (writeIndex + 1) % maxSamples
        }
    }

    func reset() {
        circularBuffer.removeAll()
        writeIndex = 0
        isFull = false
        isProcessing = false
        message = nil
    }

    func showProcessing() {
        isProcessing = true
        message = nil
    }

    func showMessage(_ text: String, icon: String) {
        isProcessing = false
        message = OverlayMessage(text: text, icon: icon)
    }
}
