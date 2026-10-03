import Foundation
import MahjongAI
import MahjongRules

public enum PlayMode: String, Codable, CaseIterable, Sendable {
  case quick
  case round
  case full
  case career
  case practice

  public var displayName: String {
    switch self {
    case .quick: return "快速"
    case .round: return "一圈"
    case .full: return "完整"
    case .career: return "生涯"
    case .practice: return "练习"
    }
  }
}

public struct AudioSettings: Codable, Equatable, Sendable {
  public var music: Double
  public var effects: Double
  public var voice: Double

  public var haptics: Bool?

  public init(music: Double = 0.25, effects: Double = 0.8, voice: Double = 1, haptics: Bool? = nil) {
    self.music = music
    self.effects = effects
    self.voice = voice
    self.haptics = haptics
  }

  public var hapticsEnabled: Bool { haptics ?? true }

  public var musicOn: Bool { music > 0.01 }
  public var effectsOn: Bool { effects > 0.01 }
  public var voiceOn: Bool { voice > 0.01 }
}

public enum ReplayStep: Codable, Equatable, Sendable {
  case command(GameCommand)
  case declareWin(seat: Int)
}

public struct HandActionCounts: Equatable, Sendable {
  public var chows: Int
  public var pungs: Int
  public var kongs: Int
  public var concealedKongs: Int

  public init(chows: Int = 0, pungs: Int = 0, kongs: Int = 0, concealedKongs: Int = 0) {
    self.chows = chows
    self.pungs = pungs
    self.kongs = kongs
    self.concealedKongs = concealedKongs
  }
}

public enum HandFacts {
  public static func counts(events: [GameEvent], seat: Int = 0) -> HandActionCounts {
    var counts = HandActionCounts()
    for event in events {
      switch event {
      case let .claimed(claimSeat, type, _) where claimSeat == seat:
        switch type {
        case .chow: counts.chows += 1
        case .pung: counts.pungs += 1
        case .exposedKong: counts.kongs += 1
        case .win: break
        }
      case let .declaredKong(kongSeat, _, concealed) where kongSeat == seat:
        counts.kongs += 1
        if concealed { counts.concealedKongs += 1 }
      default:
        break
      }
    }
    return counts
  }
}

public struct HandRecord: Codable, Identifiable, Sendable {
  public let id: UUID
  public let playedAt: Date
  public let mode: PlayMode
  public let seed: UInt64
  public let difficulty: AIDifficulty
  public let steps: [ReplayStep]
  public let canReplay: Bool
  public let winner: Int?
  public let discarder: Int?
  public let winMethod: WinMethod?
  public let fanPoints: Int
  public let nonFlowerPoints: Int
  public let awardFans: [Int]
  public let deltas: [Int]
  public let chowCount: Int
  public let pungCount: Int
  public let kongCount: Int
  public let concealedKongCount: Int
  public let humanExposedMelds: Int
  public let ruleVersion: String
  public let careerLevelID: String?
  public let dealerSeat: Int?
  public let prevailingWind: Int?

  public init(
    id: UUID = UUID(),
    playedAt: Date = Date(),
    mode: PlayMode,
    seed: UInt64,
    difficulty: AIDifficulty,
    steps: [ReplayStep],
    canReplay: Bool,
    winner: Int?,
    discarder: Int?,
    winMethod: WinMethod?,
    fanPoints: Int,
    nonFlowerPoints: Int,
    awardFans: [Int],
    deltas: [Int],
    chowCount: Int,
    pungCount: Int,
    kongCount: Int,
    concealedKongCount: Int,
    humanExposedMelds: Int,
    ruleVersion: String = MCRRuleBook.version,
    careerLevelID: String? = nil,
    dealerSeat: Int? = nil,
    prevailingWind: Int? = nil
  ) {
    self.id = id
    self.playedAt = playedAt
    self.mode = mode
    self.seed = seed
    self.difficulty = difficulty
    self.steps = steps
    self.canReplay = canReplay
    self.winner = winner
    self.discarder = discarder
    self.winMethod = winMethod
    self.fanPoints = fanPoints
    self.nonFlowerPoints = nonFlowerPoints
    self.awardFans = awardFans
    self.deltas = deltas
    self.chowCount = chowCount
    self.pungCount = pungCount
    self.kongCount = kongCount
    self.concealedKongCount = concealedKongCount
    self.humanExposedMelds = humanExposedMelds
    self.ruleVersion = ruleVersion
    self.careerLevelID = careerLevelID
    self.dealerSeat = dealerSeat
    self.prevailingWind = prevailingWind
  }

  public var roundWind: Wind {
    Wind(rawValue: prevailingWind ?? Wind.east.rawValue) ?? .east
  }

  public var humanWon: Bool { winner == 0 }
  public var dealtIn: Bool { discarder == 0 }
  public var selfDrawn: Bool {
    humanWon && (winMethod == .selfDraw || winMethod == .kongReplacement)
  }
  public var isDraw: Bool { winner == nil }
  public var humanDelta: Int { deltas.indices.contains(0) ? deltas[0] : 0 }

  /// 同分并列。座次同分的排序方式仍是待定规则，这里不另造名次。
  public func humanRank() -> Int {
    deltas.filter { $0 > humanDelta }.count + 1
  }
}

public struct ModeStats: Equatable, Sendable {
  public var hands: Int
  public var firsts: Int
  public var rankSum: Int
  public var wins: Int
  public var selfDraws: Int
  public var dealIns: Int
  public var draws: Int
  public var fanSum: Int
  public var maxFan: Int
  public var maxFanName: String
  public var chows: Int
  public var pungs: Int
  public var kongs: Int
  public var concealedWins: Int
  public var fanCounts: [Int: Int]
  public var recentDeltas: [Int]

  public static let empty = ModeStats(
    hands: 0, firsts: 0, rankSum: 0, wins: 0, selfDraws: 0, dealIns: 0, draws: 0,
    fanSum: 0, maxFan: 0, maxFanName: "—", chows: 0, pungs: 0, kongs: 0,
    concealedWins: 0, fanCounts: [:], recentDeltas: [])
}

public enum RecordBook {
  public static func stats(_ records: [HandRecord], mode: PlayMode?) -> ModeStats {
    let selected = records.filter { mode == nil || $0.mode == mode }
      .sorted { $0.playedAt < $1.playedAt }
    var stats = ModeStats.empty
    stats.hands = selected.count
    var fanCounts: [Int: Int] = [:]
    for record in selected {
      let rank = record.humanRank()
      stats.rankSum += rank
      if rank == 1 { stats.firsts += 1 }
      if record.isDraw { stats.draws += 1 }
      if record.dealtIn { stats.dealIns += 1 }
      stats.chows += record.chowCount
      stats.pungs += record.pungCount
      stats.kongs += record.kongCount
      if record.humanWon {
        stats.wins += 1
        stats.fanSum += record.fanPoints
        if record.selfDrawn { stats.selfDraws += 1 }
        if record.humanExposedMelds == 0 { stats.concealedWins += 1 }
        if record.fanPoints >= stats.maxFan {
          stats.maxFan = record.fanPoints
          stats.maxFanName = record.awardFans.compactMap { Fan(rawValue: $0)?.name }
            .joined(separator: " ")
          if stats.maxFanName.isEmpty { stats.maxFanName = "和牌" }
        }
        for fan in Set(record.awardFans) {
          fanCounts[fan, default: 0] += 1
        }
      }
    }
    stats.fanCounts = fanCounts
    stats.recentDeltas = selected.suffix(20).map(\.humanDelta)
    return stats
  }
}
