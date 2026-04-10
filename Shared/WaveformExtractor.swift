import AVFoundation

enum WaveformExtractor {

    /// Reads an audio file and returns `count` normalized amplitude samples (0...1).
    static func extractSamples(from url: URL, count: Int = 200) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return Array(repeating: 0, count: count)
        }

        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            return Array(repeating: 0, count: count)
        }

        let totalFrames = Int(buffer.frameLength)
        let framesPerBin = max(totalFrames / count, 1)
        var result = [Float]()
        result.reserveCapacity(count)

        for i in 0..<count {
            let start = i * framesPerBin
            let end = min(start + framesPerBin, totalFrames)
            guard start < end else {
                result.append(0)
                continue
            }
            var peak: Float = 0
            for j in start..<end {
                peak = max(peak, abs(channelData[j]))
            }
            result.append(peak)
        }

        let maxPeak = result.max() ?? 1
        if maxPeak > 0 {
            result = result.map { $0 / maxPeak }
        }

        return result
    }
}
