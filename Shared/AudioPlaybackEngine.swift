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
    private var fadeTimer: Timer?
    private var sessionConfigured = false
    private var playbackRate: Float = 1.0
    private var segmentEndTime: TimeInterval = 0

    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    var rate: Float {
        get { playbackRate }
        set {
            let clamped = max(0.25, min(newValue, 3.0))
            playbackRate = clamped
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
        fadeTimer?.invalidate()
        fadeTimer = nil
        player?.stop()

        let player = try AVAudioPlayer(contentsOf: url)
        player.enableRate = true
        player.rate = playbackRate
        player.prepareToPlay()
        self.player = player
        loadedURL = url
    }

    func playSegment(startTime: TimeInterval, endTime: TimeInterval) {
        guard let player else { return }

        stopTask?.cancel()
        fadeTimer?.invalidate()
        fadeTimer = nil
        activateSession()

        let safeStart = max(startTime, 0)
        let safeEnd = max(endTime, safeStart)
        let duration = max(safeEnd - safeStart, 0)
        segmentEndTime = safeEnd

        guard duration > 0.01 else {
            player.pause()
            player.volume = 1.0
            return
        }

        // Fade in pre-roll: start 0.5s early and fade to full volume at startTime
        let fadeDuration: TimeInterval = 0.5
        let playStartTime = max(safeStart - fadeDuration, 0)
        let actualPreRoll = safeStart - playStartTime

        player.currentTime = playStartTime
        player.enableRate = true
        player.rate = playbackRate

        if actualPreRoll > 0.05 {
            player.volume = 0.0
            player.play()
            let realFadeDuration = actualPreRoll / Double(max(playbackRate, 0.01))
            performVolumeFade(from: 0.0, to: 1.0, duration: realFadeDuration)
        } else {
            player.volume = 1.0
            player.play()
        }

        // Total audio distance from playStartTime to safeEnd (endTime)
        let totalAudioDistance = safeEnd - playStartTime
        let realDelayToStop = totalAudioDistance / Double(max(playbackRate, 0.01))
        scheduleAutoStop(after: realDelayToStop)
    }

    func resumeUntil(remainingDuration: TimeInterval) {
        guard let player else { return }

        stopTask?.cancel()
        fadeTimer?.invalidate()
        fadeTimer = nil
        activateSession()

        segmentEndTime = player.currentTime + remainingDuration

        guard remainingDuration > 0.01 else {
            player.pause()
            player.volume = 1.0
            return
        }

        player.enableRate = true
        player.rate = playbackRate

        // Fade in quickly on manual resume to avoid abrupt volume hits
        let resumeFadeDuration: TimeInterval = 0.2
        player.volume = 0.0
        player.play()

        let realFadeDuration = min(resumeFadeDuration, remainingDuration / Double(max(playbackRate, 0.01)))
        performVolumeFade(from: 0.0, to: 1.0, duration: realFadeDuration)

        let realDelay = remainingDuration / Double(max(playbackRate, 0.01))
        scheduleAutoStop(after: realDelay)
    }

    func pause() {
        stopTask?.cancel()
        fadeTimer?.invalidate()
        fadeTimer = nil
        player?.volume = 1.0
        player?.pause()
    }

    func rescheduleStop(remainingDuration: TimeInterval) {
        stopTask?.cancel()
        let realDelay = remainingDuration / Double(max(playbackRate, 0.01))
        scheduleAutoStop(after: max(realDelay, 0))
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
    }

    private func performVolumeFade(
        from startVol: Float,
        to endVol: Float,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        fadeTimer?.invalidate()

        guard let player = player, duration > 0.01 else {
            player?.volume = endVol
            completion?()
            return
        }

        let steps = 20
        let stepInterval = duration / Double(steps)
        let volStep = (endVol - startVol) / Float(steps)

        var currentStep = 0
        player.volume = startVol

        // Register the timer in the .common run loop mode so scrolling/animations do not starve it
        let timer = Timer(timeInterval: stepInterval, repeats: true) { [weak self] timer in
            guard let self = self, let player = self.player else {
                timer.invalidate()
                return
            }

            currentStep += 1
            let newVol = startVol + volStep * Float(currentStep)
            player.volume = max(0.0, min(newVol, 1.0))

            if currentStep >= steps {
                timer.invalidate()
                self.fadeTimer = nil
                player.volume = endVol
                completion?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.fadeTimer = timer
    }

    private func scheduleAutoStop(after realDelay: TimeInterval) {
        guard realDelay > 0 else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self = self, let player = self.player else { return }
            // Smoothly fade out over 1.0 seconds past the endTime
            let fadeOutDuration: TimeInterval = 1.0
            self.performVolumeFade(from: 1.0, to: 0.0, duration: fadeOutDuration) { [weak self] in
                self?.player?.pause()
                self?.player?.volume = 1.0
            }
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
