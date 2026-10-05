import MahjongRules

public enum FortuneTier: String, Codable, Equatable, Sendable {
  case plain
  case small
  case great
}

/// Point bands for one to three dice. Plain has no buff.
public enum DailyDice {
  public static let minimumCount = 1
  public static let maximumCount = 3
  public static let gameSpan = 3
  public static let drawLookahead = 4
  public static let openingLookahead = 8

  public static func grade(faces: [Int]) -> FortuneTier {
    let total = faces.reduce(0, +)
    switch faces.count {
    case 1:
      if total == 6 { return .great }
      if total == 5 { return .small }
      return .plain
    case 2:
      if (11...12).contains(total) { return .great }
      if (9...10).contains(total) { return .small }
      return .plain
    case 3:
      if (15...18).contains(total) { return .great }
      if (12...14).contains(total) { return .small }
      return .plain
    default:
      return .plain
    }
  }

  public static func faces(count: Int, random: inout some RandomNumberGenerator) -> [Int] {
    let dice = min(maximumCount, max(minimumCount, count))
    return (0..<dice).map { _ in Int.random(in: 1...6, using: &random) }
  }

  public static func luckLine(tier: FortuneTier, rolled: Bool) -> String {
    guard rolled else { return "掷一到三颗，看看今天运气好不好。" }
    switch tier {
    case .plain:
      return "今天运气平平，没有额外帮助。"
    case .small:
      return "小吉。接下来几局摸牌会顺一点，但不会保证和牌。"
    case .great:
      return "大吉。接下来几局手气更好一点，但不会凭空赢。"
    }
  }
}

/// Queued buff. One quick game, one east round, one 16-hand match, or one career level spends a charge.
public struct FortuneTrack: Codable, Equatable, Sendable {
  public var tier: FortuneTier
  public var queuedGames: Int
  public var activeGame: Bool
  public var diceCount: Int
  public var faces: [Int]

  public init(
    tier: FortuneTier = .plain,
    queuedGames: Int = 0,
    activeGame: Bool = false,
    diceCount: Int = 1,
    faces: [Int] = []
  ) {
    self.tier = tier
    self.queuedGames = queuedGames
    self.activeGame = activeGame
    self.diceCount = min(DailyDice.maximumCount, max(DailyDice.minimumCount, diceCount))
    self.faces = faces
  }

  /// Games still covered, including the one being played.
  public var gamesRemaining: Int {
    queuedGames + (activeGame && tier != .plain ? 1 : 0)
  }

  public var drawHelp: Bool {
    activeGame && (tier == .small || tier == .great)
  }

  public var openingHelp: Bool {
    activeGame && tier == .great
  }

  public var remainingLine: String? {
    guard gamesRemaining > 0 else { return nil }
    return "运势还剩 \(gamesRemaining) 局"
  }

  public var luckLine: String {
    DailyDice.luckLine(tier: tier, rolled: !faces.isEmpty)
  }

  /// A new roll replaces whatever was left.
  public mutating func roll(faces: [Int]) {
    self.faces = faces
    tier = DailyDice.grade(faces: faces)
    activeGame = false
    queuedGames = tier == .plain ? 0 : DailyDice.gameSpan
  }

  /// Starts one counted game. False when no buff is waiting.
  public mutating func beginGame() -> Bool {
    activeGame = false
    guard queuedGames > 0, tier == .small || tier == .great else { return false }
    queuedGames -= 1
    activeGame = true
    return true
  }

  public mutating func finishGame() {
    activeGame = false
  }
}

/// Tile exchanges use only the player's tiles and the wall. Opponent concealed tiles are not an input.
public enum FortuneAid {
  /// Nearest upcoming wall tile that lowers shanten, if one sits in the next few.
  public static func improvingDrawOffset(
    concealed: [TileKind],
    meldCount: Int,
    drawn: TileKind,
    upcoming: [TileKind]
  ) -> Int? {
    guard let removeAt = concealed.firstIndex(of: drawn) else { return nil }
    var without = concealed
    without.remove(at: removeAt)
    let current = PracticeCoach.shanten(of: concealed, meldCount: meldCount)
    for (offset, kind) in upcoming.prefix(DailyDice.drawLookahead).enumerated() {
      if kind.isFlower { continue }
      let swapped = PracticeCoach.shanten(of: without + [kind], meldCount: meldCount)
      if swapped < current { return offset }
    }
    return nil
  }

  /// When the opening hand has no pair, swap one hand tile for a wall tile that makes a pair.
  public static func openingPairExchange(
    hand: [TileKind],
    upcoming: [TileKind]
  ) -> (remove: TileKind, offset: Int)? {
    let counts = hand.counts
    guard !counts.values.contains(where: { $0 >= 2 }) else { return nil }
    let singles = Set(hand)
    for (offset, kind) in upcoming.prefix(DailyDice.openingLookahead).enumerated() {
      if kind.isFlower || !singles.contains(kind) { continue }
      if let remove = hand.first(where: { $0 != kind }) {
        return (remove, offset)
      }
    }
    return nil
  }
}
