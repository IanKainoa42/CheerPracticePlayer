import AVFoundation
import Foundation

protocol AudioPlaybackControlling: AnyObject {
    var currentTime: TimeInterval { get }
    /// Playback rate multiplier. 1.0 = normal speed. Setter applies immediately to current playback.
    var rate: Float { get set }
    func load(url: URL) throws
    func playSegment(startTime: TimeInterval, endTime: TimeInterval)
    func resumeUntil(remainingDuration: TimeInterval)
    func pause()
    func seek(to time: TimeInterval)
}

final class AudioPlaybackEngine: NSObject, AudioPlaybackControlling {
    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var stopTask: DispatchWorkItem?
    private var sessionConfigured = false
    private var _rate: Float = 1.0
    private var segmentEndTime: TimeInterval = 0

    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    var rate: Float {
        get { _rate }
        set {
            let clamped = max(0.25, min(newValue, 3.0))
            _rate = clamped
            player?.rate = clamped

            if let player = player, player.isPlaying {
                let remainingAudio = max(segmentEndTime - player.currentTime, 0)
                rescheduleStop(remainingDuration: remainingAudio)
            }
        }
    }

    func load(url: URL) throws {
        guard loadedURL != url else { return }

        stopTask?.cancel()
        player?.stop()

        let player = try AVAudioPlayer(contentsOf: url)
        player.enableRate = true
        player.rate = _rate
        player.prepareToPlay()
        self.player = player
        loadedURL = url
    }

    func playSegment(startTime: TimeInterval, endTime: TimeInterval) {
        guard let player else { return }

        stopTask?.cancel()
        activateSession()

        let safeStart = max(startTime, 0)
        let safeEnd = max(endTime, safeStart)
        let duration = max(safeEnd - safeStart, 0)
        segmentEndTime = safeEnd

        guard duration > 0.01 else {
            player.pause()
            return
        }

        player.currentTime = safeStart
        player.enableRate = true
        player.rate = _rate
        player.play()

        scheduleAutoStop(after: duration)
    }

    func resumeUntil(remainingDuration: TimeInterval) {
        guard let player else { return }

        stopTask?.cancel()
        activateSession()
        
        segmentEndTime = player.currentTime + remainingDuration

        guard remainingDuration > 0.01 else {
            player.pause()
            return
        }

        player.enableRate = true
        player.rate = _rate
        player.play()
        scheduleAutoStop(after: max(remainingDuration, 0))
    }

    func pause() {
        stopTask?.cancel()
        player?.pause()
    }

    func rescheduleStop(remainingDuration: TimeInterval) {
        stopTask?.cancel()
        scheduleAutoStop(after: max(remainingDuration, 0))
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
    }

    private func scheduleAutoStop(after audioDuration: TimeInterval) {
        guard audioDuration > 0 else { return }
        let realDelay = audioDuration / Double(max(_rate, 0.01))
        let task = DispatchWorkItem { [weak player] in
            player?.pause()
        }
        stopTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + realDelay, execute: task)
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if !sessionConfigured {
                try session.setCategory(.playback, mode: .default, options: [])
                sessionConfigured = true
            }
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal — AVAudioPlayer will still try to play.
        }
    }
}
