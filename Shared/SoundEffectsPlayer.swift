import AVFoundation
import Foundation

@MainActor
final class SoundEffectsPlayer {
    static let shared = SoundEffectsPlayer()

    private var beepPlayer: AVAudioPlayer?

    // Count-in voices: a soft tick for off-beats, a brighter tick for click
    // accents, and a noise-based snare for snare accents. Preloaded so each
    // beat fires with no allocation latency.
    private var softTickPlayer: AVAudioPlayer?
    private var accentClickPlayer: AVAudioPlayer?
    private var snarePlayer: AVAudioPlayer?

    private init() {
        prepareBeep()
        prepareCountInVoices()
    }

    private func prepareBeep() {
        // Synthesize a beautiful A5 (880Hz) chime with a 15% second harmonic (1760Hz)
        if let wavData = Self.generateBeepWav(frequency: 880.0, duration: 0.15, attack: 0.01, decay: 0.12) {
            beepPlayer = try? AVAudioPlayer(data: wavData)
            beepPlayer?.prepareToPlay()
        }
    }

    private func prepareCountInVoices() {
        // Soft off-beat tick: short, mid-high, low volume.
        if let data = Self.generateBeepWav(frequency: 1200.0, duration: 0.05, attack: 0.004, decay: 0.045) {
            softTickPlayer = try? AVAudioPlayer(data: data)
            softTickPlayer?.volume = 0.5
            softTickPlayer?.prepareToPlay()
        }
        // Accent click: brighter and louder so counts 1 (and 5) pop.
        if let data = Self.generateBeepWav(frequency: 2000.0, duration: 0.05, attack: 0.003, decay: 0.045) {
            accentClickPlayer = try? AVAudioPlayer(data: data)
            accentClickPlayer?.volume = 1.0
            accentClickPlayer?.prepareToPlay()
        }
        // Snare: a fast-decaying filtered-noise burst with a little tonal body.
        if let data = Self.generateSnareWav(duration: 0.09) {
            snarePlayer = try? AVAudioPlayer(data: data)
            snarePlayer?.volume = 1.0
            snarePlayer?.prepareToPlay()
        }
    }

    /// Plays one count-in tick. Off-beats are always the soft tick; accented
    /// beats use the chosen timbre (`click` or `snare`).
    func playCountInTick(accent: Bool, sound: CountInSound) {
        let player: AVAudioPlayer?
        switch (accent, sound) {
        case (false, _):       player = softTickPlayer
        case (true, .click):   player = accentClickPlayer
        case (true, .snare):   player = snarePlayer
        }
        guard let player else { return }
        if player.isPlaying { player.stop() }
        player.currentTime = 0
        player.play()
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

    /// Generates an in-memory mono 16-bit PCM WAV snare: a noise burst plus a
    /// short tonal body, with a fast exponential decay. Deterministic-ish via a
    /// small LCG so the timbre is stable across calls.
    static func generateSnareWav(duration: Double) -> Data? {
        let sampleRate = 44100
        let totalSamples = Int(Double(sampleRate) * duration)
        guard totalSamples > 0 else { return nil }

        var pcm = [Int16]()
        pcm.reserveCapacity(totalSamples)

        var rng: UInt64 = 0x9E3779B97F4A7C15
        func nextNoise() -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let bits = Double(rng >> 11) / Double(1 << 53)
            return bits * 2.0 - 1.0
        }

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let decay = exp(-t / (duration * 0.35))
            let noise = nextNoise()
            // A little 180Hz body gives the snare some weight under the noise.
            let body = sin(2.0 * .pi * 180.0 * t) * 0.4
            let combined = (noise * 0.85 + body) * decay
            let clamped = max(-1.0, min(1.0, combined))
            pcm.append(Int16(clamped * 22000.0))
        }

        let numChannels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * numChannels * (bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let subChunk2Size = pcm.count * numChannels * (bitsPerSample / 8)
        let chunkSize = 36 + subChunk2Size

        var data = Data()
        data.append("RIFF".data(using: .utf8)!)
        data.append(withUnsafeBytes(of: Int32(chunkSize)) { Data($0) })
        data.append("WAVE".data(using: .utf8)!)
        data.append("fmt ".data(using: .utf8)!)
        data.append(withUnsafeBytes(of: Int32(16)) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(1)) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(numChannels)) { Data($0) })
        data.append(withUnsafeBytes(of: Int32(sampleRate)) { Data($0) })
        data.append(withUnsafeBytes(of: Int32(byteRate)) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(blockAlign)) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(bitsPerSample)) { Data($0) })
        data.append("data".data(using: .utf8)!)
        data.append(withUnsafeBytes(of: Int32(subChunk2Size)) { Data($0) })
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
