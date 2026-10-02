import MahjongRules

/// The complete input visible to an AI. It deliberately has no wall order, seed, or opponent hands.

public enum AIDifficulty: String, CaseIterable, Codable, Sendable {
  case beginner
  case normal
  case expert

  public var displayName: String {
    switch self {
    case .beginner: return "新手"
    case .normal: return "普通"
    case .expert: return "高手"
    }
  }
}
public enum PersonalityArchetype: String, CaseIterable, Codable, Sendable {
  case aggressive
  case conservative
  case bigHand

  public var displayName: String {
    switch self {
    case .aggressive: return "激进"
    case .conservative: return "保守"
    case .bigHand: return "爱做大牌"
    }
  }
}
public struct AIPersonality: Hashable, Codable, Sendable {
  public let archetype: PersonalityArchetype
  public let aggression: Int
  public let defense: Int
  public let bigHandPreference: Int

  public init(
    archetype: PersonalityArchetype,
    aggression: Int,
    defense: Int,
    bigHandPreference: Int
  ) {
    self.archetype = archetype
    self.aggression = aggression
    self.defense = defense
    self.bigHandPreference = bigHandPreference
  }

  public static let aggressive = AIPersonality(
    archetype: .aggressive, aggression: 90, defense: 20, bigHandPreference: 25)
  public static let conservative = AIPersonality(
    archetype: .conservative, aggression: 25, defense: 95, bigHandPreference: 35)
  public static let bigHand = AIPersonality(
    archetype: .bigHand, aggression: 45, defense: 45, bigHandPreference: 95)
}
public struct OpponentProfile: Hashable, Codable, Sendable {
  public let seat: Int
  public let name: String
  public let avatarSystemName: String
  public let personality: AIPersonality
  public let difficulty: AIDifficulty

  public init(
    seat: Int,
    name: String,
    avatarSystemName: String,
    personality: AIPersonality,
    difficulty: AIDifficulty
  ) {
    self.seat = seat
    self.name = name
    self.avatarSystemName = avatarSystemName
    self.personality = personality
    self.difficulty = difficulty
  }

  public static func standardOpponents(difficulty: AIDifficulty) -> [OpponentProfile] {
    [
      OpponentProfile(
        seat: 1, name: "阿岚", avatarSystemName: "hare.fill",
        personality: .aggressive, difficulty: difficulty),
      OpponentProfile(
        seat: 2, name: "静川", avatarSystemName: "shield.lefthalf.filled",
        personality: .conservative, difficulty: difficulty),
      OpponentProfile(
        seat: 3, name: "墨衡", avatarSystemName: "crown.fill",
        personality: .bigHand, difficulty: difficulty),
    ]
  }
}
public struct AIInformationSet: Codable, Sendable {
  public let seat: Int
  public let ownTiles: [TileKind]
  public let ownMelds: [Meld]
  public let discards: [[TileKind]]
  public let publicMelds: [[Meld]]
  public let exposedFlowers: [[TileKind]]
  public let wallRemaining: Int
  public let scores: [Int]
  public let roundWind: Wind
  public let actionNumber: Int

  public init(
    seat: Int,
    ownTiles: [TileKind],
    ownMelds: [Meld],
    discards: [[TileKind]],
    publicMelds: [[Meld]],
    exposedFlowers: [[TileKind]],
    wallRemaining: Int,
    scores: [Int],
    roundWind: Wind,
    actionNumber: Int
  ) {
    precondition((0..<4).contains(seat))
    precondition(discards.count == 4 && publicMelds.count == 4 && exposedFlowers.count == 4)
    precondition(scores.count == 4)
    self.seat = seat
    self.ownTiles = ownTiles
    self.ownMelds = ownMelds
    self.discards = discards
    self.publicMelds = publicMelds
    self.exposedFlowers = exposedFlowers
    self.wallRemaining = wallRemaining
    self.scores = scores
    self.roundWind = roundWind
    self.actionNumber = actionNumber
  }

  public var visibleTileCounts: [TileKind: Int] {
    var counts: [TileKind: Int] = [:]
    for tile in ownTiles { counts[tile, default: 0] += 1 }
    for tile in discards.flatMap({ $0 }) { counts[tile, default: 0] += 1 }
    for tile in publicMelds.flatMap({ $0 }).flatMap(\.tiles) { counts[tile, default: 0] += 1 }
    for tile in exposedFlowers.flatMap({ $0 }) { counts[tile, default: 0] += 1 }
    return counts
  }
}
public enum AIClaimChoice: Hashable, Codable, Sendable {
  case chow([TileKind])
  case pung
  case exposedKong
}
public struct AICandidateScore: Hashable, Codable, Sendable {
  public let tile: TileKind
  public let total: Int
  public let efficiency: Int
  public let danger: Int
  public let fanPlan: Int
  public let randomAdjustment: Int

  public init(
    tile: TileKind,
    total: Int,
    efficiency: Int,
    danger: Int,
    fanPlan: Int,
    randomAdjustment: Int
  ) {
    self.tile = tile
    self.total = total
    self.efficiency = efficiency
    self.danger = danger
    self.fanPlan = fanPlan
    self.randomAdjustment = randomAdjustment
  }
}
public struct AIDecisionLog: Hashable, Codable, Sendable {
  public let difficulty: AIDifficulty
  public let personality: PersonalityArchetype
  public let candidates: [AICandidateScore]
  public let chosenTile: TileKind
  public let explanation: String

  public init(
    difficulty: AIDifficulty,
    personality: PersonalityArchetype,
    candidates: [AICandidateScore],
    chosenTile: TileKind,
    explanation: String
  ) {
    self.difficulty = difficulty
    self.personality = personality
    self.candidates = candidates
    self.chosenTile = chosenTile
    self.explanation = explanation
  }
}
