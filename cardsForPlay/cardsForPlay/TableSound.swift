import AudioToolbox
import AVFoundation
import MahjongProgress
import UIKit

@MainActor
final class TableSound {
  static let shared = TableSound()

  private let speech = AVSpeechSynthesizer()
  private var lastSpeech = Date.distantPast
  private var music: AVAudioPlayer?
  private var musicReady = false

  private init() {
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
  }

  func sync(_ settings: AudioSettings) {
    guard settings.musicOn else {
      music?.stop()
      return
    }
    if !musicReady {
      music = try? AVAudioPlayer(data: Self.toneData())
      music?.numberOfLoops = -1
      music?.prepareToPlay()
      musicReady = music != nil
    }
    music?.volume = Float(min(1, max(0, settings.music))) * 0.35
    if music?.isPlaying != true { music?.play() }
  }

  func speak(_ text: String, settings: AudioSettings) {
    guard settings.voiceOn else { return }
    let now = Date()
    guard now.timeIntervalSince(lastSpeech) > 0.7 else { return }
    lastSpeech = now
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.volume = Float(min(1, max(0, settings.voice)))
    speech.speak(utterance)
  }

  func tap(_ settings: AudioSettings) {
    guard settings.effectsOn else { return }
    AudioServicesPlaySystemSound(1104)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private static func toneData() -> Data {
    let sampleRate = 8_000
    let count = sampleRate * 2
    var pcm = Data(capacity: count * 2)
    for index in 0..<count {
      let time = Double(index) / Double(sampleRate)
      let pulse = 0.65 + 0.35 * sin(2 * Double.pi * time)
      let sample = (sin(2 * Double.pi * 196 * time) * 0.6 + sin(2 * Double.pi * 247 * time) * 0.4)
        * 0.08 * pulse
      var value = Int16(max(-1, min(1, sample)) * 8_000)
      withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
    }
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
