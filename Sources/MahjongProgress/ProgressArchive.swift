import CryptoKit
import Foundation
import MahjongAI
import MahjongRules

public struct SavedSession: Codable, Sendable {
  public var seed: UInt64
  public var game: GameState
  public var steps: [ReplayStep]
  public var canReplay: Bool
  public var cumulativeScores: [Int]
  public var score: ScoreResult?
  public var winner: Int?
  public var discarder: Int?
  public var winMethod: WinMethod?
  public var deltas: [Int]
  public var drawn: Bool
  public var paused: Bool
  public var aiDelay: Double
  public var difficulty: AIDifficulty
  public var mode: PlayMode
  public var careerLevelID: String?
  public var practiceHints: Bool
  public var lastRecordID: UUID?
  public var roundHandIndex: Int?
  public var roundInitialDealer: Int?

  public init(
    seed: UInt64,
    game: GameState,
    steps: [ReplayStep],
    canReplay: Bool,
    cumulativeScores: [Int],
    score: ScoreResult?,
    winner: Int?,
    discarder: Int?,
    winMethod: WinMethod?,
    deltas: [Int],
    drawn: Bool,
    paused: Bool,
    aiDelay: Double,
    difficulty: AIDifficulty,
    mode: PlayMode,
    careerLevelID: String?,
    practiceHints: Bool,
    lastRecordID: UUID?,
    roundHandIndex: Int? = nil,
    roundInitialDealer: Int? = nil
  ) {
    self.seed = seed
    self.game = game
    self.steps = steps
    self.canReplay = canReplay
    self.cumulativeScores = cumulativeScores
    self.score = score
    self.winner = winner
    self.discarder = discarder
    self.winMethod = winMethod
    self.deltas = deltas
    self.drawn = drawn
    self.paused = paused
    self.aiDelay = aiDelay
    self.difficulty = difficulty
    self.mode = mode
    self.careerLevelID = careerLevelID
    self.practiceHints = practiceHints
    self.lastRecordID = lastRecordID
    self.roundHandIndex = roundHandIndex
    self.roundInitialDealer = roundInitialDealer
  }
}

public struct ProgressLibrary: Codable, Sendable {
  public static let schemaVersion = 1
  public static let transcriptLimit = 40

  public var session: SavedSession?
  public var records: [HandRecord]
  public var career: CareerProgress
  public var audio: AudioSettings

  public init(
    session: SavedSession? = nil,
    records: [HandRecord] = [],
    career: CareerProgress = CareerProgress(),
    audio: AudioSettings = AudioSettings()
  ) {
    self.session = session
    self.records = records
    self.career = career
    self.audio = audio
  }

  public mutating func append(_ record: HandRecord) {
    records.append(record)
    if records.count > Self.transcriptLimit {
      records.removeFirst(records.count - Self.transcriptLimit)
    }
  }
}

public enum ProgressArchive {
  public static func save(_ library: ProgressLibrary, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let payload = try JSONEncoder().encode(library)
    let envelope = Envelope(
      schema: ProgressLibrary.schemaVersion,
      checksum: checksum(payload),
      payload: payload
    )
    let data = try JSONEncoder().encode(envelope)
    let current = directory.appendingPathComponent("progress.json")
    let previous = directory.appendingPathComponent("progress.previous.json")
    let temporary = directory.appendingPathComponent("progress.json.tmp")
    if FileManager.default.fileExists(atPath: current.path) {
      try? FileManager.default.removeItem(at: previous)
      try FileManager.default.copyItem(at: current, to: previous)
    }
    try data.write(to: temporary, options: .atomic)
    if FileManager.default.fileExists(atPath: current.path) {
      _ = try FileManager.default.replaceItemAt(current, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: current)
    }
  }

  public static func load(from directory: URL) -> ProgressLibrary {
    let current = directory.appendingPathComponent("progress.json")
    if let library = read(current) { return library }
    let previous = directory.appendingPathComponent("progress.previous.json")
    if let library = read(previous) { return library }
    return ProgressLibrary()
  }

  private static func read(_ url: URL) -> ProgressLibrary? {
    guard let data = try? Data(contentsOf: url),
      let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
      envelope.schema == ProgressLibrary.schemaVersion,
      checksum(envelope.payload) == envelope.checksum
    else { return nil }
    return try? JSONDecoder().decode(ProgressLibrary.self, from: envelope.payload)
  }

  private static func checksum(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct Envelope: Codable {
  let schema: Int
  let checksum: String
  let payload: Data
}
