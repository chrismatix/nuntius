import XCTest
@testable import Nuntius

final class AudioWAVEncoderTests: XCTestCase {
    func testEncodeProducesValidWAVHeaderAndSamples() {
        let samples: [Float] = [0.0, 1.0, -1.0]
        guard let data = AudioWAVEncoder.encode(samples: samples, sampleRate: 16_000) else {
            XCTFail("Expected WAV data")
            return
        }

        XCTAssertEqual(data.count, 44 + samples.count * 2)
        XCTAssertEqual(readString(data, offset: 0, length: 4), "RIFF")
        XCTAssertEqual(readString(data, offset: 8, length: 4), "WAVE")
        XCTAssertEqual(readString(data, offset: 12, length: 4), "fmt ")
        XCTAssertEqual(readString(data, offset: 36, length: 4), "data")

        XCTAssertEqual(readInt32LE(data, offset: 4), 36 + Int32(samples.count * 2))
        XCTAssertEqual(readInt32LE(data, offset: 16), 16)
        XCTAssertEqual(readInt16LE(data, offset: 20), 1)
        XCTAssertEqual(readInt16LE(data, offset: 22), 1)
        XCTAssertEqual(readInt32LE(data, offset: 24), 16_000)
        XCTAssertEqual(readInt32LE(data, offset: 28), 32_000)
        XCTAssertEqual(readInt16LE(data, offset: 32), 2)
        XCTAssertEqual(readInt16LE(data, offset: 34), 16)
        XCTAssertEqual(readInt32LE(data, offset: 40), Int32(samples.count * 2))

        XCTAssertEqual(readInt16LE(data, offset: 44), 0)
        XCTAssertEqual(readInt16LE(data, offset: 46), Int16.max)
        XCTAssertEqual(readInt16LE(data, offset: 48), -Int16.max)
    }

    func testEncodeClampsSamplesToInt16Range() {
        let samples: [Float] = [2.0, -2.0]
        guard let data = AudioWAVEncoder.encode(samples: samples, sampleRate: 16_000) else {
            XCTFail("Expected WAV data")
            return
        }

        XCTAssertEqual(readInt16LE(data, offset: 44), Int16.max)
        XCTAssertEqual(readInt16LE(data, offset: 46), -Int16.max)
    }

    private func readInt16LE(_ data: Data, offset: Int) -> Int16 {
        let bytes = data[offset..<offset + 2]
        return Int16(littleEndian: bytes.withUnsafeBytes { $0.load(as: Int16.self) })
    }

    private func readInt32LE(_ data: Data, offset: Int) -> Int32 {
        let bytes = data[offset..<offset + 4]
        return Int32(littleEndian: bytes.withUnsafeBytes { $0.load(as: Int32.self) })
    }

    private func readString(_ data: Data, offset: Int, length: Int) -> String {
        let slice = data[offset..<offset + length]
        return String(decoding: slice, as: UTF8.self)
    }
}
