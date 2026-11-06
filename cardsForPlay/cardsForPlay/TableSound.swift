import AVFoundation
import MahjongProgress
import UIKit

@MainActor
final class TableSound {
  static let shared = TableSound()

  private let speech = AVSpeechSynthesizer()
  private var lastSpeech = Date.distantPast
  private var music: AVAudioPlayer?
  private var effect: AVAudioPlayer?
  private var wantsMusic = false
  private var inForeground = true

  private init() {
    configureSession()
  }

  /// One bundled loop for the menu and the table. Sync never restarts it.
  /// `table-bgm.wav` is an original CC0 loop; see `table-bgm.txt`.
  func sync(_ settings: AudioSettings, calm: Bool = false) {
    _ = calm
    wantsMusic = settings.backgroundMusicEnabled
    guard wantsMusic else {
      music?.pause()
      return
    }
    loadTrackIfNeeded()
    applyVolume(settings)
    guard inForeground else { return }
    resumeIfNeeded()
  }

  func setForeground(_ active: Bool) {
    inForeground = active
    if !active {
      music?.pause()
      return
    }
    guard wantsMusic else { return }
    configureSession()
    resumeIfNeeded()
  }

  private func configureSession() {
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
  }

  private func loadTrackIfNeeded() {
    guard music == nil else { return }
    guard let url = Bundle.main.url(forResource: "table-bgm", withExtension: "wav") else { return }
    music = try? AVAudioPlayer(contentsOf: url)
    music?.numberOfLoops = -1
    music?.prepareToPlay()
  }

  private func applyVolume(_ settings: AudioSettings) {
    let slider = Float(min(1, max(0, settings.music)))
    music?.volume = min(0.42, slider * 1.5)
  }

  private func resumeIfNeeded() {
    guard let music, !music.isPlaying else { return }
    music.play()
  }

  func speak(_ text: String, settings: AudioSettings) {
    guard settings.voiceOn else { return }
    let now = Date()
    guard now.timeIntervalSince(lastSpeech) > 0.7 else { return }
    lastSpeech = now
    if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    utterance.rate = 0.46
    utterance.volume = Float(min(1, max(0, settings.voice)))
    speech.speak(utterance)
  }

  func tap(_ settings: AudioSettings) {
    playBlip(frequency: 520, seconds: 0.05, settings: settings)
    guard settings.hapticsEnabled else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  func claim(_ settings: AudioSettings) {
    playBlip(frequency: 680, seconds: 0.08, settings: settings)
  }

  private func playBlip(frequency: Double, seconds: Double, settings: AudioSettings) {
    guard settings.effectsOn else { return }
    effect?.stop()
    effect = try? AVAudioPlayer(data: Self.blipData(frequency: frequency, seconds: seconds))
    effect?.volume = Float(min(1, max(0, settings.effects)))
    effect?.play()
  }

  private static func blipData(frequency: Double, seconds: Double) -> Data {
    let sampleRate = 8_000
    let count = Int(Double(sampleRate) * seconds)
    var pcm = Data(capacity: count * 2)
    for index in 0..<count {
      let time = Double(index) / Double(sampleRate)
      let envelope = 1 - time / seconds
      let sample = sin(2 * Double.pi * frequency * time) * 0.35 * envelope
      var value = Int16(max(-1, min(1, sample)) * 16_000)
      withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
    }
    return wav(pcm, sampleRate: sampleRate)
  }

  private static func wav(_ pcm: Data, sampleRate: Int) -> Data {
    var data = Data()
    func append(_ text: String) { data.append(contentsOf: text.utf8) }
    func append32(_ value: UInt32) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    append("RIFF")
    append32(UInt32(36 + pcm.count))
    append("WAVE")
    append("fmt ")
    append32(16)
    append16(1)
    append16(1)
    append32(UInt32(sampleRate))
    append32(UInt32(sampleRate * 2))
    append16(2)
    append16(16)
    append("data")
    append32(UInt32(pcm.count))
    data.append(pcm)
    return data
  }
}
