import AVFoundation
@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct AudioTranscoderTests {
    @Test
    func `m4a data is transcoded even when the provided extension is wrong`() async throws {
        try cleanTranscoderRoot()

        let result = try await AudioTranscoder.transcode(
            data: Data(contentsOf: fixtureM4AURL),
            fileExtension: "bin",
        )

        #expect(result.format == "m4a")
        #expect(!result.data.isEmpty)
        #expect(result.duration > 0)
        #expect(try transcoderWorkingDirectories().isEmpty)
    }

    @Test
    func `compressed wav output is normalized to mono 8k`() async throws {
        try cleanTranscoderRoot()

        let result = try await AudioTranscoder.transcode(
            data: makeWAVData(sampleRate: 44100, channelCount: 2, duration: 0.25),
            fileExtension: "wav",
            output: .compressedQualityWAV,
        )
        let audioProperties = try inspectAudioFile(data: result.data, pathExtension: result.format)

        #expect(result.format == "wav")
        #expect(result.duration > 0)
        #expect(audioProperties.sampleRate == 8000)
        #expect(audioProperties.channelCount == 1)
        #expect(try transcoderWorkingDirectories().isEmpty)
    }

    @Test
    func `url overload transcodes audio files from disk`() async throws {
        try cleanTranscoderRoot()

        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioTranscoderInput-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try Data(contentsOf: fixtureM4AURL)
            .write(to: inputURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let result = try await AudioTranscoder.transcode(url: inputURL)

        #expect(result.format == "m4a")
        #expect(!result.data.isEmpty)
        #expect(result.duration > 0)
        #expect(try transcoderWorkingDirectories().isEmpty)
    }

    @Test
    func `invalid audio bytes throw asset not supported and clean temporary directories`() async throws {
        try cleanTranscoderRoot()

        do {
            _ = try await AudioTranscoder.transcode(
                data: Data("definitely-not-audio".utf8),
                fileExtension: "dat",
            )
            Issue.record("Expected invalid audio data to be rejected.")
        } catch let error as AudioTranscoderError {
            switch error {
            case .assetNotSupported:
                break
            default:
                Issue.record("Expected assetNotSupported, got \(error).")
            }
        } catch {
            Issue.record("Expected AudioTranscoderError, got \(error).")
        }

        #expect(try transcoderWorkingDirectories().isEmpty)
    }
}

private extension AudioTranscoderTests {
    struct AudioProperties {
        let channelCount: Int
        let sampleRate: Int
    }

    var fixtureM4AURL: URL {
        repositoryRoot
            .appendingPathComponent("FlowDown/Resources/DialTune/dial_tune_0.m4a")
    }

    var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    var transcoderRoot: URL {
        disposableResourcesDir.appendingPathComponent("AudioTranscoder", isDirectory: true)
    }

    func cleanTranscoderRoot() throws {
        try? FileManager.default.removeItem(at: transcoderRoot)
    }

    func transcoderWorkingDirectories() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: transcoderRoot.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: transcoderRoot,
            includingPropertiesForKeys: nil,
        )
    }

    func inspectAudioFile(data: Data, pathExtension: String) throws -> AudioProperties {
        let url = disposableResourcesDir
            .appendingPathComponent("AudioTranscoderInspect-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forReading: url)
        return AudioProperties(
            channelCount: Int(file.fileFormat.channelCount),
            sampleRate: Int(file.fileFormat.sampleRate.rounded()),
        )
    }

    func makeWAVData(
        sampleRate: Int,
        channelCount: Int,
        duration: Double,
    ) -> Data {
        let frameCount = max(Int(Double(sampleRate) * duration), 1)
        let bitsPerSample = 16
        let blockAlign = channelCount * (bitsPerSample / 8)
        let byteRate = sampleRate * blockAlign
        let dataSize = frameCount * blockAlign
        let amplitude = Double(Int16.max) * 0.25

        var pcm = Data(capacity: dataSize)
        for frame in 0 ..< frameCount {
            let sample = Int16(
                (sin((2 * .pi * Double(frame) * 440.0) / Double(sampleRate)) * amplitude)
                    .rounded(),
            )
            for _ in 0 ..< channelCount {
                appendUInt16LE(UInt16(bitPattern: sample), to: &pcm)
            }
        }

        var data = Data(capacity: 44 + pcm.count)
        data.append(Data("RIFF".utf8))
        appendUInt32LE(UInt32(36 + pcm.count), to: &data)
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        appendUInt32LE(16, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt16LE(UInt16(channelCount), to: &data)
        appendUInt32LE(UInt32(sampleRate), to: &data)
        appendUInt32LE(UInt32(byteRate), to: &data)
        appendUInt16LE(UInt16(blockAlign), to: &data)
        appendUInt16LE(UInt16(bitsPerSample), to: &data)
        data.append(Data("data".utf8))
        appendUInt32LE(UInt32(pcm.count), to: &data)
        data.append(pcm)
        return data
    }

    func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00FF))
        data.append(UInt8((value >> 8) & 0x00FF))
    }

    func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x0000_00FF))
        data.append(UInt8((value >> 8) & 0x0000_00FF))
        data.append(UInt8((value >> 16) & 0x0000_00FF))
        data.append(UInt8((value >> 24) & 0x0000_00FF))
    }
}
