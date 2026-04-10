import AVFoundation
import Foundation

protocol AudioPlaybackControlling: AnyObject {
    func load(url: URL) throws
    func playSegment(startTime: TimeInterval, endTime: TimeInterval)
    func pause()
}

final class AudioPlaybackEngine: NSObject, AudioPlaybackControlling {
    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var stopTask: DispatchWorkItem?

    func load(url: URL) throws {
        guard loadedURL != url else { return }

        stopTask?.cancel()
        player?.stop()

        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        self.player = player
        loadedURL = url
    }

    func playSegment(startTime: TimeInterval, endTime: TimeInterval) {
        guard let player else { return }

        stopTask?.cancel()

        let safeStart = max(startTime, 0)
        let safeEnd = max(endTime, safeStart)
        let duration = max(safeEnd - safeStart, 0)

        player.currentTime = safeStart
        player.play()

        let task = DispatchWorkItem { [weak player] in
            player?.pause()
        }
        stopTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    func pause() {
        stopTask?.cancel()
        player?.pause()
    }
}
