import Foundation
import AVFoundation

final class ChimePlayer {
    static let shared = ChimePlayer()

    private let queue = DispatchQueue(label: "app.scope.chimeplayer")
    private var player: AVAudioPlayer?

    private init() {}

    func preload() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.player != nil { return }
            guard let url = Bundle.main.url(forResource: "launch_chime", withExtension: "wav") else { return }
            do {
                let loaded = try AVAudioPlayer(contentsOf: url)
                loaded.volume = 0.12
                loaded.prepareToPlay()
                self.player = loaded
            } catch {
                // Ignore preload errors; playback will be best-effort.
            }
        }
    }

    func play() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.player == nil {
                self.preload()
                self.player?.play()
                return
            }
            self.player?.currentTime = 0
            self.player?.play()
        }
    }
}
