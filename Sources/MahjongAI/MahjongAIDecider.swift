import MahjongRules

public enum MahjongAIDecider {
  public static func chooseDiscard(
    information: AIInformationSet,
    profile: OpponentProfile,
    decisionSeed: UInt64
  ) -> AIDecisionLog {
    precondition(!information.ownTiles.isEmpty)
    let candidates = Set(information.ownTiles).map { tile -> AICandidateScore in
      var remaining = information.ownTiles
      remaining.remove(at: remaining.firstIndex(of: tile)!)

      let efficiency = HandEfficiency.score(remaining)
      let danger = DangerEstimator.score(tile: tile, information: information)
      let fanPlan = FanPlanner.discardBonus(
        tile: tile, remaining: remaining, personality: profile.personality)
      let random = randomAdjustment(
        tile: tile, seed: decisionSeed, difficulty: profile.difficulty)

      let total: Int
      switch profile.difficulty {
      case .beginner:
        total = efficiency + random * 4 + fanPlan / 4 - danger / 5
      case .normal:
        let defenseWeight = information.publicMelds.contains { $0.count >= 2 } ? 2 : 1
        total = efficiency * 4 + fanPlan - danger * defenseWeight
      case .expert:
        let defenseWeight = max(2, profile.personality.defense / 12)
        let attackWeight = max(2, profile.personality.aggression / 30)
        total = efficiency * attackWeight + fanPlan * 2 - danger * defenseWeight
      }
      return AICandidateScore(
        tile: tile,
        total: total,
        efficiency: efficiency,
        danger: danger,
        fanPlan: fanPlan,
        randomAdjustment: random
      )
    }
    .sorted {
      if $0.total != $1.total { return $0.total > $1.total }
      return $0.tile.rawValue > $1.tile.rawValue
    }

    let chosen = candidates[0]
    let explanation: String
    switch profile.difficulty {
    case .beginner:
      explanation = "随机与基础牌效并用，保留成组牌"
    case .normal:
      explanation = "优先牌效，并参考公开副露做基础防守"
    case .expert:
      explanation =
        chosen.danger == 0
        ? "选择公开牌河证明较安全的牌"
        : "综合牌效、危险度、局况与\(profile.personality.archetype.displayName)番路"
    }
    return AIDecisionLog(
      difficulty: profile.difficulty,
      personality: profile.personality.archetype,
      candidates: candidates,
      chosenTile: chosen.tile,
      explanation: explanation
    )
  }

  /// Whether to declare a concealed kong (`removing` 4) or an added kong (`removing` 1).
  /// Pair tiles and tiles that make up the tenpai wait are left in the hand.
  /// Only `information` is consulted, so opponent concealed tiles cannot affect the result.
  public static func shouldDeclareKong(
    kind: TileKind,
    removing: Int,
    information: AIInformationSet
  ) -> Bool {
    KongPolicy.allows(
      kind: kind,
      removing: removing,
      tiles: information.ownTiles,
      meldCount: information.ownMelds.count
    )
  }

  public static func shouldClaim(
    _ claim: AIClaimChoice,
    discardedTile: TileKind,
    information: AIInformationSet,
    profile: OpponentProfile,
    decisionSeed: UInt64
  ) -> Bool {
    if case .exposedKong = claim { return true }

    let dominantSuit = FanPlanner.dominantSuit(information.ownTiles)
    let followsBigHandPlan =
      discardedTile.isHonor || discardedTile.suit == dominantSuit
    let aggressive = profile.personality.aggression >= 70

    switch profile.difficulty {
    case .beginner:
      let roll = stableNoise(seed: decisionSeed, salt: discardedTile.rawValue) % 100
      return Int(roll) < (aggressive ? 76 : 48)
    case .normal:
      switch claim {
      case .pung:
        return discardedTile.isHonor || aggressive
          || information.ownTiles.filter { $0 == discardedTile }.count >= 2
      case let .chow(run):
        return aggressive
          || run.contains { tile in
            information.ownTiles.filter { $0 == tile }.count >= 2
          }
      case .exposedKong:
        return true
      }
    case .expert:
      if profile.personality.archetype == .bigHand && !followsBigHandPlan {
        return false
      }
      if profile.personality.archetype == .conservative,
        DangerEstimator.score(tile: discardedTile, information: information) >= 9
      {
        return false
      }
      return aggressive || followsBigHandPlan || claim == .pung
    }
  }

  private static func randomAdjustment(
    tile: TileKind,
    seed: UInt64,
    difficulty: AIDifficulty
  ) -> Int {
    guard difficulty == .beginner else { return 0 }
    return Int(stableNoise(seed: seed, salt: tile.rawValue) % 25) - 12
  }

  private static func stableNoise(seed: UInt64, salt: Int) -> UInt64 {
    var value = seed ^ (UInt64(salt + 1) &* 0x9E37_79B9_7F4A_7C15)
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
private enum HandEfficiency {
  static func score(_ tiles: [TileKind]) -> Int {
    var counts = Array(repeating: 0, count: 34)
    for tile in tiles where tile.rawValue < 34 { counts[tile.rawValue] += 1 }
    let melds = maximumMelds(&counts, start: 0)
    let pairs = counts.reduce(0) { $0 + ($1 >= 2 ? 1 : 0) }
    let connections = connectionCount(counts)
    let isolated = isolatedCount(counts)
    return melds * 32 + min(2, pairs) * 9 + connections * 4 - isolated * 3
  }

  private static func maximumMelds(_ counts: inout [Int], start: Int) -> Int {
    guard let index = (start..<34).first(where: { counts[$0] > 0 }) else { return 0 }
    var best = 0

    counts[index] -= 1
    best = maximumMelds(&counts, start: index)
    counts[index] += 1

    if counts[index] >= 3 {
      counts[index] -= 3
      best = max(best, 1 + maximumMelds(&counts, start: index))
      counts[index] += 3
    }
    if index < 27, index % 9 <= 6, counts[index + 1] > 0, counts[index + 2] > 0 {
      counts[index] -= 1
      counts[index + 1] -= 1
      counts[index + 2] -= 1
      best = max(best, 1 + maximumMelds(&counts, start: index))
      counts[index] += 1
      counts[index + 1] += 1
      counts[index + 2] += 1
    }
    return best
  }

  private static func connectionCount(_ counts: [Int]) -> Int {
    var total = 0
    for suit in 0..<3 {
      let base = suit * 9
      for rank in 0..<9 where counts[base + rank] > 0 {
        if rank < 8, counts[base + rank + 1] > 0 { total += 1 }
        if rank < 7, counts[base + rank + 2] > 0 { total += 1 }
      }
    }
    return total
  }

  private static func isolatedCount(_ counts: [Int]) -> Int {
    var isolated = 0
    for index in 0..<34 where counts[index] == 1 {
      if index >= 27 {
        isolated += 1
        continue
      }
      let rank = index % 9
      let neighbors = [
        rank > 1 ? counts[index - 2] : 0,
        rank > 0 ? counts[index - 1] : 0,
        rank < 8 ? counts[index + 1] : 0,
        rank < 7 ? counts[index + 2] : 0,
      ]
      if neighbors.allSatisfy({ $0 == 0 }) { isolated += 1 }
    }
    return isolated
  }
}
private enum DangerEstimator {
  static func score(tile: TileKind, information: AIInformationSet) -> Int {
    let visible = information.visibleTileCounts[tile, default: 0]
    if visible >= 3 { return 0 }

    var maximum = 0
    for opponent in 0..<4 where opponent != information.seat {
      let threat =
        information.publicMelds[opponent].count * 3
        + max(0, information.scores[opponent] - information.scores[information.seat]) / 16
      guard threat > 0 else { continue }
      if information.discards[opponent].contains(tile) { continue }

      var tileDanger: Int
      if let rank = tile.rank {
        tileDanger = (4...6).contains(rank) ? 8 : ((2...8).contains(rank) ? 6 : 3)
        let suji = [rank - 3, rank + 3].compactMap {
          TileKind(suit: tile.suit!, rank: $0)
        }
        if suji.contains(where: { information.discards[opponent].contains($0) }) {
          tileDanger -= 2
        }
      } else {
        tileDanger = 5
      }
      maximum = max(maximum, tileDanger + threat)
    }
    return max(0, maximum - visible * 2)
  }
}
private enum FanPlanner {
  static func dominantSuit(_ tiles: [TileKind]) -> Suit? {
    let counts = Dictionary(grouping: tiles.compactMap(\.suit), by: { $0 }).mapValues(\.count)
    return counts.max {
      if $0.value != $1.value { return $0.value < $1.value }
      return $0.key.rawValue > $1.key.rawValue
    }?.key
  }

  static func discardBonus(
    tile: TileKind,
    remaining: [TileKind],
    personality: AIPersonality
  ) -> Int {
    var bonus = 0
    if personality.bigHandPreference >= 70, let dominant = dominantSuit(remaining) {
      if tile.suit != nil, tile.suit != dominant {
        bonus += personality.bigHandPreference / 3
      } else if tile.suit == dominant {
        bonus -= personality.bigHandPreference / 5
      }
    }

    let remainingCopies = remaining.filter { $0 == tile }.count
    if remainingCopies >= 2 { bonus -= 12 }
    if tile.dragon != nil { bonus -= personality.bigHandPreference / 8 }
    return bonus
  }
}
