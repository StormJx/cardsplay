import MahjongRules

public struct PracticeWait: Hashable, Sendable {
  public let tile: TileKind
  public let remaining: Int
  public let nonFlowerPoints: Int
  public let fanNames: [String]
}

public struct PracticeDanger: Hashable, Sendable {
  public let level: String
  public let reason: String
}

public struct PracticeBrief: Equatable, Sendable {
  public let waitLine: String
  public let fanLine: String
  public let dangerLine: String
}

/// Practice hints from the player's tiles and the public table. Opponent concealed tiles are not an input.
public enum PracticeCoach {
  public static func brief(
    concealed: [TileKind],
    melds: [Meld],
    discarding: Bool,
    selected: TileKind?,
    discards: [[TileKind]],
    exposedMelds: [[Meld]],
    scores: [Int],
    seat: Int,
    seatWind: Wind,
    roundWind: Wind,
    unseen: (TileKind) -> Int
  ) -> PracticeBrief {
    let complete = (4 - melds.count) * 3 + 2
    let discard: TileKind?
    let waits: [PracticeWait]
    if discarding, concealed.count == complete {
      let choice = chosenDiscard(
        selected: selected, concealed: concealed, melds: melds, seatWind: seatWind,
        roundWind: roundWind, unseen: unseen)
      discard = choice.discard
      waits = choice.waits
    } else if !discarding, concealed.count == complete - 1 {
      discard = nil
      waits = waitingTiles(
        concealed: concealed, removing: nil, melds: melds, seatWind: seatWind,
        roundWind: roundWind, unseen: unseen)
    } else {
      discard = nil
      waits = []
    }

    let held = (discard.map { removed($0, from: concealed) } ?? concealed) + melds.flatMap(\.tiles)
    let dangerTile = discarding ? (selected ?? discard) : nil
    return PracticeBrief(
      waitLine: waitLine(discard: discard, waits: waits, discarding: discarding),
      fanLine: fanLine(waits: waits, held: held),
      dangerLine: dangerLine(
        tile: dangerTile, discards: discards, exposedMelds: exposedMelds, scores: scores,
        seat: seat, unseen: unseen)
    )
  }

  public static func waitingTiles(
    concealed: [TileKind],
    removing discard: TileKind?,
    melds: [Meld],
    seatWind: Wind,
    roundWind: Wind,
    unseen: (TileKind) -> Int
  ) -> [PracticeWait] {
    let base = discard.map { removed($0, from: concealed) } ?? concealed
    var found: [TileKind: PracticeWait] = [:]
    for kind in TileSet.normalKinds {
      let hand = base + [kind]
      let context = WinContext(
        concealedTiles: hand,
        melds: melds,
        winningTile: kind,
        method: .discard,
        seatWind: seatWind,
        roundWind: roundWind
      )
      guard let score = MCRScorer.score(context) else { continue }
      let names = score.awards.filter { $0.fan != .flower }.map(\.fan.name)
      let wait = PracticeWait(
        tile: kind,
        remaining: unseen(kind),
        nonFlowerPoints: score.nonFlowerPoints,
        fanNames: names
      )
      if let previous = found[kind], previous.nonFlowerPoints >= wait.nonFlowerPoints {
        continue
      }
      found[kind] = wait
    }
    return found.values.sorted { $0.tile.rawValue < $1.tile.rawValue }
  }

  /// Danger of throwing `tile`, using only discards, exposed melds, scores, and how many copies are already visible.
  public static func danger(
    tile: TileKind,
    seat: Int,
    discards: [[TileKind]],
    exposedMelds: [[Meld]],
    scores: [Int],
    visibleCount: Int
  ) -> PracticeDanger {
    if visibleCount >= 3 {
      return PracticeDanger(level: "低", reason: "这张已见\(visibleCount)张")
    }
    var bestScore = 0
    var bestReason = "对手没有副露"
    for opponent in 0..<4 where opponent != seat && opponent < exposedMelds.count {
      let meldCount = exposedMelds[opponent].count
      let scoreGap = opponent < scores.count && seat < scores.count
        ? max(0, scores[opponent] - scores[seat]) / 16 : 0
      let threat = meldCount * 3 + scoreGap
      guard threat > 0 else { continue }
      if opponent < discards.count, discards[opponent].contains(tile) { continue }

      var tileDanger: Int
      var shape: String
      var suji = false
      if let rank = tile.rank {
        if (4...6).contains(rank) {
          tileDanger = 8
          shape = "中张"
        } else if (2...8).contains(rank) {
          tileDanger = 6
          shape = "边张附近"
        } else {
          tileDanger = 3
          shape = "幺九"
        }
        let sujiTiles = [rank - 3, rank + 3].compactMap { TileKind(suit: tile.suit!, rank: $0) }
        if opponent < discards.count, sujiTiles.contains(where: { discards[opponent].contains($0) }) {
          tileDanger -= 2
          suji = true
        }
      } else {
        tileDanger = 5
        shape = "字牌"
      }
      let score = max(0, tileDanger + threat - visibleCount * 2)
      guard score > bestScore else { continue }
      bestScore = score
      var reason = "\(shape)，对手已有\(meldCount)副露"
      if suji { reason += "，有筋" }
      bestReason = reason
    }
    if bestScore == 0, bestReason == "对手没有副露" {
      let threatened = (0..<4).contains { opponent in
        opponent != seat && opponent < exposedMelds.count && !exposedMelds[opponent].isEmpty
      }
      if threatened { bestReason = "有副露的对手打过这张" }
    }
    let level = bestScore <= 0 ? "低" : (bestScore < 10 ? "中" : "高")
    return PracticeDanger(level: level, reason: bestReason)
  }

  public static func closeFanNotes(tiles: [TileKind]) -> [String] {
    let counts = Dictionary(grouping: tiles, by: { $0 }).mapValues(\.count)
    var notes: [String] = []
    let pairKinds = counts.values.filter { $0 == 2 }.count
    if (5...6).contains(pairKinds) {
      notes.append("接近七对，还差\(7 - pairKinds)对")
    }

    let honors = tiles.filter(\.isHonor).count
    let suitCounts = Dictionary(grouping: tiles.compactMap(\.suit), by: { $0 }).mapValues(\.count)
    if let main = suitCounts.max(by: { $0.value < $1.value })?.value, main >= 8 {
      let off = tiles.filter(\.isSuited).count - main
      if honors == 0, (1...3).contains(off) {
        notes.append("接近清一色，还差打出\(off)张其他花色")
      } else if honors > 0, (0...2).contains(off), off + honors > 0, off > 0 {
        notes.append("接近混一色，还差打出杂色")
      }
    }

    let pungs = counts.values.filter { $0 >= 3 }.count
    let singles = counts.values.filter { $0 == 1 }.count
    if pungs >= 3, (1...2).contains(singles) {
      notes.append("接近碰碰和，还差把散牌做成刻")
    }

    let presentSuits = suitCounts.filter { $0.value > 0 }
    if presentSuits.count == 3, presentSuits.values.contains(1) {
      notes.append("接近缺一门，还差打出那1张")
    }

    let terminals = tiles.filter(\.isTerminalOrHonor).count
    if tiles.count >= 10, (1...2).contains(terminals) {
      notes.append("接近断幺，还差打出幺九")
    }
    return Array(notes.prefix(3))
  }

  private static func chosenDiscard(
    selected: TileKind?,
    concealed: [TileKind],
    melds: [Meld],
    seatWind: Wind,
    roundWind: Wind,
    unseen: (TileKind) -> Int
  ) -> (discard: TileKind?, waits: [PracticeWait]) {
    if let selected, concealed.contains(selected) {
      return (
        selected,
        waitingTiles(
          concealed: concealed, removing: selected, melds: melds, seatWind: seatWind,
          roundWind: roundWind, unseen: unseen)
      )
    }
    var bestDiscard: TileKind?
    var bestWaits: [PracticeWait] = []
    for kind in Set(concealed).sorted(by: { $0.rawValue < $1.rawValue }) {
      let candidate = waitingTiles(
        concealed: concealed, removing: kind, melds: melds, seatWind: seatWind,
        roundWind: roundWind, unseen: unseen)
      let better =
        candidate.count > bestWaits.count
        || (
          candidate.count == bestWaits.count && candidate.count > 0
            && (bestDiscard == nil || kind.rawValue < bestDiscard!.rawValue)
        )
      if bestDiscard == nil || better {
        bestDiscard = kind
        bestWaits = candidate
      }
    }
    return (bestDiscard, bestWaits)
  }

  private static func removed(_ tile: TileKind, from tiles: [TileKind]) -> [TileKind] {
    var copy = tiles
    if let index = copy.firstIndex(of: tile) { copy.remove(at: index) }
    return copy
  }

  private static func waitLine(discard: TileKind?, waits: [PracticeWait], discarding: Bool) -> String {
    let listed = waits.map { "\(name($0.tile))剩\($0.remaining)" }.joined(separator: " · ")
    if let discard {
      return waits.isEmpty ? "打出\(name(discard))后未听" : "打出\(name(discard))后听 \(listed)"
    }
    if discarding { return "未听牌" }
    return waits.isEmpty ? "未听牌" : "听 \(listed)"
  }

  private static func fanLine(waits: [PracticeWait], held: [TileKind]) -> String {
    let close = closeFanNotes(tiles: held)
    guard let best = waits.max(by: { $0.nonFlowerPoints < $1.nonFlowerPoints }) else {
      return close.isEmpty ? "番 还看不出接近的番" : "番 " + close.joined(separator: " · ")
    }
    let names = best.fanNames.prefix(3).joined(separator: "、")
    let scored = names.isEmpty ? "番 还没有成型的番" : "番 已有\(names)"
    if best.nonFlowerPoints >= 8 {
      return "\(scored)，共\(best.nonFlowerPoints)番"
    }
    let gap = "还差\(max(1, 8 - best.nonFlowerPoints))番"
    let extra = close.prefix(2).joined(separator: " · ")
    return extra.isEmpty ? "\(scored)，\(gap)" : "\(scored)，\(gap) · \(extra)"
  }

  private static func dangerLine(
    tile: TileKind?,
    discards: [[TileKind]],
    exposedMelds: [[Meld]],
    scores: [Int],
    seat: Int,
    unseen: (TileKind) -> Int
  ) -> String {
    guard let tile else { return "危险 轮到你出牌时，点一张牌查看" }
    let visible = max(0, (tile.isFlower ? 1 : 4) - unseen(tile))
    let result = danger(
      tile: tile, seat: seat, discards: discards, exposedMelds: exposedMelds, scores: scores,
      visibleCount: visible)
    return "危险 \(name(tile)) \(result.level) · \(result.reason)"
  }

  private static func name(_ tile: TileKind) -> String {
    if let suit = tile.suit, let rank = tile.rank {
      return "\(rank)\(["万", "筒", "条"][suit.rawValue])"
    }
    if let wind = tile.wind { return ["东", "南", "西", "北"][wind.rawValue] }
    if let dragon = tile.dragon { return ["中", "发", "白"][dragon.rawValue] }
    return "花"
  }
}
