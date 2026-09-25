import AVFoundation

@MainActor final class Soundscape {
    static let shared = Soundscape()
    private var music: AVAudioPlayer?
    private var effect: AVAudioPlayer?
    private var effectsEnabled = true
    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        if let url = Bundle.main.url(forResource: "music", withExtension: "wav") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.volume = 0.24
            music?.prepareToPlay()
        }
    }
    func configure(save: PlayerSave) {
        effectsEnabled = save.effectsEnabled
        if save.musicEnabled { music?.play() } else { music?.pause() }
    }
    func cue(_ name: String) {
        guard effectsEnabled, let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        effect = try? AVAudioPlayer(contentsOf: url)
        effect?.volume = 0.55
        effect?.play()
    }
}
