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
  private var musicReady = false
  private var calmMusic = false

  private init() {
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
  }

  func sync(_ settings: AudioSettings, calm: Bool = false) {
    if calm != calmMusic {
      calmMusic = calm
      music?.stop()
      music = nil
      musicReady = false
    }
    guard settings.musicOn else {
      music?.stop()
      return
    }
    if !musicReady {
      music = try? AVAudioPlayer(data: Self.toneData(calm: calm))
      music?.numberOfLoops = -1
      music?.prepareToPlay()
      musicReady = music != nil
    }
    music?.volume = Float(min(1, max(0, settings.music))) * 0.45
    if music?.isPlaying != true { music?.play() }
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

  private static func toneData(calm: Bool) -> Data {
    let sampleRate = 8_000
    let notes = calm ? [196.0, 220.0, 247.0, 196.0] : [262.0, 294.0, 330.0, 392.0, 330.0]
    let count = sampleRate * 4
    var pcm = Data(capacity: count * 2)
    for index in 0..<count {
      let time = Double(index) / Double(sampleRate)
      let step = calm ? 1.0 : 0.7
      let note = notes[Int(time / step) % notes.count]
      let envelope = 0.55 + 0.45 * sin(2 * Double.pi * time / step)
      let sample = sin(2 * Double.pi * note * time) * 0.16 * envelope
      var value = Int16(max(-1, min(1, sample)) * 12_000)
      withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
    }
    return wav(pcm, sampleRate: sampleRate)
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
