import AVFoundation
import Foundation

@MainActor
final class SoundEffectsPlayer {
    static let shared = SoundEffectsPlayer()

    private var beepPlayer: AVAudioPlayer?

    private init() {
        prepareBeep()
    }

    private func prepareBeep() {
        // Synthesize a beautiful A5 (880Hz) chime with a 15% second harmonic (1760Hz)
        if let wavData = Self.generateBeepWav(frequency: 880.0, duration: 0.15, attack: 0.01, decay: 0.12) {
            beepPlayer = try? AVAudioPlayer(data: wavData)
            beepPlayer?.prepareToPlay()
        }
    }

    func playBeep() {
        guard let beepPlayer else { return }
        if beepPlayer.isPlaying {
            beepPlayer.stop()
        }
        beepPlayer.currentTime = 0
        beepPlayer.play()
    }

    func playDoubleBeep() {
        playBeep()
        // Play the second beep after a short delay (180ms) for a distinct dual-tone chime
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.playBeep()
            }
        }
    }

    /// Generates in-memory mono 16-bit PCM WAV audio data for a smooth, warm chime-like tone.
    static func generateBeepWav(
        frequency: Double,
        duration: Double,
        attack: Double,
        decay: Double
    ) -> Data? {
        let sampleRate = 44100
        let totalSamples = Int(Double(sampleRate) * duration)
        let numChannels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * numChannels * (bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)

        let subChunk2Size = totalSamples * numChannels * (bitsPerSample / 8)
        let chunkSize = 36 + subChunk2Size

        var header = Data()

        // RIFF Container
        header.append("RIFF".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: Int32(chunkSize)) { Data($0) })
        header.append("WAVE".data(using: .utf8)!)

        // Sub-chunk 1: Format Details
        header.append("fmt ".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: Int32(16)) { Data($0) })
        header.append(withUnsafeBytes(of: Int16(1)) { Data($0) }) // PCM format = 1
        header.append(withUnsafeBytes(of: Int16(numChannels)) { Data($0) })
        header.append(withUnsafeBytes(of: Int32(sampleRate)) { Data($0) })
        header.append(withUnsafeBytes(of: Int32(byteRate)) { Data($0) })
        header.append(withUnsafeBytes(of: Int16(blockAlign)) { Data($0) })
        header.append(withUnsafeBytes(of: Int16(bitsPerSample)) { Data($0) })

        // Sub-chunk 2: Audio Data
        header.append("data".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: Int32(subChunk2Size)) { Data($0) })

        var samples = [Int16]()
        samples.reserveCapacity(totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)

            // Primary sine wave + subtle 15% second harmonic for acoustic warmth
            let primary = sin(2.0 * .pi * frequency * t)
            let harmonic = sin(2.0 * .pi * (frequency * 2.0) * t)
            let combined = (primary + 0.15 * harmonic) / 1.15

            // Linear attack / exponential decay envelope to eliminate transient pops
            var amplitude = 1.0
            if t < attack {
                amplitude = t / attack
            } else if t > (duration - decay) {
                let decayTime = t - (duration - decay)
                amplitude = max(0, 1.0 - (decayTime / decay))
                amplitude = amplitude * amplitude // quadratic curve for smoother decay
            }

            // Scale to comfortable reference volume (max 32767 for Int16)
            let sampleVal = Int16(combined * amplitude * 18000.0)
            samples.append(sampleVal)
        }

        var wavData = header
        samples.withUnsafeBytes { ptr in
            wavData.append(contentsOf: ptr)
        }

        return wavData
    }
}
