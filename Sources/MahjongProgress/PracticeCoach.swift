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

public struct PracticeSwitches: Codable, Equatable, Sendable {
  public var waits: Bool
  public var recommendation: Bool
  public var remaining: Bool
  public var fans: Bool
  public var danger: Bool

  public init(
    waits: Bool = true,
    recommendation: Bool = true,
    remaining: Bool = true,
    fans: Bool = true,
    danger: Bool = true
  ) {
    self.waits = waits
    self.recommendation = recommendation
    self.remaining = remaining
    self.fans = fans
    self.danger = danger
  }
}

public struct DiscardStudy: Equatable, Sendable {
  public let tile: TileKind
  public let shanten: Int
  public let usefulTiles: Int
  public let estimatedFan: Int
}

public enum PracticeHintScope: Equatable, Sendable {
  case full
  case waitsAndFan
}

public struct PracticeBrief: Equatable, Sendable {
  public let waitLine: String
  public let fanLine: String
  public let dangerLine: String
  public let shantenLine: String
  public let blockedLine: String
  public let conflictLine: String
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
    unseen: (TileKind) -> Int,
    switches: PracticeSwitches = PracticeSwitches(),
    drawn: TileKind? = nil,
    scope: PracticeHintScope = .full
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
    let studies = discarding ? discardStudies(
      concealed: concealed, melds: melds, seatWind: seatWind, roundWind: roundWind, unseen: unseen
    ) : []
    let tenpai = isTenpai(
      discarding: discarding, discard: discard, waits: waits, concealed: concealed, meldCount: melds.count)
    let blocked = blockedFanNames(melds: melds)
    let conflicts = conflictingFanNames(tiles: concealed + melds.flatMap(\.tiles), melds: melds)
    let idle = idleShanten(
      concealed: concealed, meldCount: melds.count, waits: waits, tenpai: tenpai, unseen: unseen)
    let shortFan = discarding ? shortHandFan(
      concealed: concealed, melds: melds, drawn: drawn, seatWind: seatWind, roundWind: roundWind
    ) : nil
    let brief = PracticeBrief(
      waitLine: switches.waits
        ? (tenpai
          ? waitLine(discard: discard, waits: waits, discarding: discarding, showRemaining: switches.remaining)
          : "")
        : "听 已关闭",
      fanLine: switches.fans
        ? fanLine(waits: waits, held: held, tenpai: tenpai, shortHand: shortFan)
        : "番 已关闭",
      dangerLine: switches.danger
        ? (tenpai
          ? dangerLine(
            tile: dangerTile, discards: discards, exposedMelds: exposedMelds, scores: scores,
            seat: seat, unseen: unseen)
          : "")
        : "危险 已关闭",
      shantenLine: switches.recommendation ? shantenLine(studies, idle: idle) : "",
      blockedLine: switches.fans && tenpai && !blocked.isEmpty
        ? "副露后打不到 " + blocked.joined(separator: "、") : "",
      conflictLine: switches.fans && tenpai && !conflicts.isEmpty
        ? "和当前牌冲突 " + conflicts.joined(separator: "、") : ""
    )
    guard scope == .waitsAndFan else { return brief }
    return PracticeBrief(
      waitLine: brief.waitLine,
      fanLine: brief.fanLine,
      dangerLine: "",
      shantenLine: "",
      blockedLine: "",
      conflictLine: ""
    )
  }

  /// Fan of the hand just drawn, when the shape is complete and non-flower points are under 8.
  private static func shortHandFan(
    concealed: [TileKind],
    melds: [Meld],
    drawn: TileKind?,
    seatWind: Wind,
    roundWind: Wind
  ) -> Int? {
    let complete = (4 - melds.count) * 3 + 2
    guard concealed.count == complete, let drawn, concealed.contains(drawn) else { return nil }
    let context = WinContext(
      concealedTiles: concealed,
      melds: melds,
      winningTile: drawn,
      method: .selfDraw,
      seatWind: seatWind,
      roundWind: roundWind
    )
    guard let score = MCRScorer.score(context), score.nonFlowerPoints < 8 else { return nil }
    return score.nonFlowerPoints
  }

  private static func isTenpai(
    discarding: Bool,
    discard: TileKind?,
    waits: [PracticeWait],
    concealed: [TileKind],
    meldCount: Int
  ) -> Bool {
    if discarding, let discard {
      return shanten(of: removed(discard, from: concealed), meldCount: meldCount) == 0
    }
    if !discarding {
      return shanten(of: concealed, meldCount: meldCount) == 0 && !waits.isEmpty
    }
    return false
  }

  private static func idleShanten(
    concealed: [TileKind],
    meldCount: Int,
    waits: [PracticeWait],
    tenpai: Bool,
    unseen: (TileKind) -> Int
  ) -> String {
    let value = shanten(of: concealed, meldCount: meldCount)
    let useful = tenpai
      ? waits.reduce(0) { $0 + max(0, $1.remaining) }
      : usefulTiles(base: concealed, melds: meldCount, unseen: unseen)
    return "\(value)向听 有效\(useful)"
  }

  public static func discardStudies(
    concealed: [TileKind],
    melds: [Meld],
    seatWind: Wind,
    roundWind: Wind,
    unseen: (TileKind) -> Int
  ) -> [DiscardStudy] {
    let complete = (4 - melds.count) * 3 + 2
    guard concealed.count == complete else { return [] }
    return Set(concealed).sorted { $0.rawValue < $1.rawValue }.map { kind in
      let kept = removed(kind, from: concealed)
      let waits = waitingTiles(
        concealed: concealed, removing: kind, melds: melds, seatWind: seatWind,
        roundWind: roundWind, unseen: unseen)
      let useful = usefulTiles(base: kept, melds: melds.count, unseen: unseen)
      return DiscardStudy(
        tile: kind,
        shanten: shanten(of: kept, meldCount: melds.count),
        usefulTiles: waits.isEmpty ? useful : waits.reduce(0) { $0 + max(0, $1.remaining) },
        estimatedFan: waits.map(\.nonFlowerPoints).max() ?? 0
      )
    }
  }

  public static func shanten(of tiles: [TileKind], meldCount: Int) -> Int {
    var counts = Array(repeating: 0, count: 34)
    for tile in tiles where tile.rawValue < 34 { counts[tile.rawValue] += 1 }
    let need = max(0, 4 - meldCount)
    let pairCount = counts.reduce(0) { $0 + $1 / 2 }
    var memo: [String: Int] = [:]
    let standard = arrange(
      &counts, index: 0, melds: 0, partials: 0, pair: false, need: need, memo: &memo)
    let pairs = meldCount == 0 ? 6 - min(7, pairCount) : 8
    return min(standard, pairs)
  }

  public static func blockedFanNames(melds: [Meld]) -> [String] {
    var names: [String] = []
    if melds.contains(where: \.isExposed) {
      names += ["七对", "十三幺", "全不靠", "七星不靠", "门前清", "不求人"]
    }
    if melds.count > 1 { names.append("组合龙") }
    return names
  }

  public static func newlyBlocked(before: [Meld], after: [Meld]) -> [String] {
    let old = Set(blockedFanNames(melds: before))
    return blockedFanNames(melds: after).filter { !old.contains($0) }
  }

  public static func droppedBelowEight(before: Int, after: Int) -> Bool {
    before >= 8 && after < 8
  }

  public static func conflictingFanNames(tiles: [TileKind], melds: [Meld]) -> [String] {
    let all = tiles + melds.flatMap(\.tiles)
    var names: [String] = []
    if Set(all.compactMap(\.suit)).count > 1 { names.append("清一色") }
    if all.contains(where: \.isHonor) { names.append("无字") }
    if all.contains(where: \.isTerminalOrHonor) { names.append("断幺") }
    if melds.contains(where: \.isExposed) { names.append("门前清") }
    let counts = Dictionary(grouping: all, by: { $0 }).mapValues(\.count)
    if counts.values.filter({ $0 >= 3 }).count >= 2 { names.append("平和") }
    if counts.values.filter({ $0 >= 2 }).count >= 5 { names.append("碰碰和") }
    return names
  }

  public static func bestListedFan(
    concealed: [TileKind],
    melds: [Meld],
    seatWind: Wind,
    roundWind: Wind
  ) -> Int {
    let complete = (4 - melds.count) * 3 + 2
    let unseen: (TileKind) -> Int = { _ in 1 }
    if concealed.count == complete - 1 {
      return waitingTiles(
        concealed: concealed, removing: nil, melds: melds, seatWind: seatWind,
        roundWind: roundWind, unseen: unseen
      ).map(\.nonFlowerPoints).max() ?? 0
    }
    guard concealed.count == complete else { return 0 }
    return Set(concealed).map { kind in
      waitingTiles(
        concealed: concealed, removing: kind, melds: melds, seatWind: seatWind,
        roundWind: roundWind, unseen: unseen
      ).map(\.nonFlowerPoints).max() ?? 0
    }.max() ?? 0
  }

  public static func situationLine(scores: [Int], seat: Int) -> String {
    guard scores.count == 4, seat < 4 else { return "局况 分数还没记" }
    let mine = scores[seat]
    let ahead = scores.filter { $0 > mine }.count
    if ahead == 0, scores.allSatisfy({ $0 == mine }) { return "局况 四家同分" }
    if ahead == 0 { return "局况 你领先" }
    return "局况 你落后\(ahead)家"
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

  private static func waitLine(
    discard: TileKind?, waits: [PracticeWait], discarding: Bool, showRemaining: Bool
  ) -> String {
    let listed = waits.map {
      showRemaining ? "\(name($0.tile))剩\($0.remaining)" : name($0.tile)
    }.joined(separator: " · ")
    if let discard {
      return waits.isEmpty ? "打出\(name(discard))后未听" : "打出\(name(discard))后听 \(listed)"
    }
    if discarding { return "未听牌" }
    return waits.isEmpty ? "未听牌" : "听 \(listed)"
  }

  private static func shantenLine(_ studies: [DiscardStudy], idle: String) -> String {
    guard !studies.isEmpty else { return idle }
    let listed = studies.prefix(6).map { study in
      let base = "\(name(study.tile)) \(study.shanten)向听 有效\(study.usefulTiles)"
      guard study.shanten == 0 else { return base }
      return base + " 约\(study.estimatedFan)番"
    }.joined(separator: " · ")
    return "向听 " + listed
  }

  private static func usefulTiles(base: [TileKind], melds: Int, unseen: (TileKind) -> Int) -> Int {
    let current = shanten(of: base, meldCount: melds)
    var total = 0
    for kind in TileSet.normalKinds {
      if shanten(of: base + [kind], meldCount: melds) < current {
        total += max(0, unseen(kind))
      }
    }
    return total
  }

  private static func arrange(
    _ counts: inout [Int],
    index: Int,
    melds: Int,
    partials: Int,
    pair: Bool,
    need: Int,
    memo: inout [String: Int]
  ) -> Int {
    var index = index
    while index < 34, counts[index] == 0 { index += 1 }
    let key = "\(index)#\(melds)#\(partials)#\(pair ? 1 : 0)#\(counts.map(String.init).joined(separator: ","))"
    if let cached = memo[key] { return cached }
    if index == 34 {
      let room = max(0, need - melds)
      let parts = min(partials, room)
      let value = room * 2 - parts - (pair ? 1 : 0)
      memo[key] = value
      return value
    }
    var best = 8
    let tileCount = counts[index]
    if tileCount >= 3 {
      counts[index] -= 3
      best = min(best, arrange(&counts, index: index, melds: melds + 1, partials: partials, pair: pair, need: need, memo: &memo))
      counts[index] += 3
    }
    if index < 27, index % 9 <= 6, counts[index + 1] > 0, counts[index + 2] > 0 {
      counts[index] -= 1
      counts[index + 1] -= 1
      counts[index + 2] -= 1
      best = min(best, arrange(&counts, index: index, melds: melds + 1, partials: partials, pair: pair, need: need, memo: &memo))
      counts[index] += 1
      counts[index + 1] += 1
      counts[index + 2] += 1
    }
    if tileCount >= 2, !pair {
      counts[index] -= 2
      best = min(best, arrange(&counts, index: index, melds: melds, partials: partials, pair: true, need: need, memo: &memo))
      counts[index] += 2
    }
    if tileCount >= 2, partials < need {
      counts[index] -= 2
      best = min(best, arrange(&counts, index: index, melds: melds, partials: partials + 1, pair: pair, need: need, memo: &memo))
      counts[index] += 2
    }
    if index < 27, index % 9 <= 7, counts[index + 1] > 0, partials < need {
      counts[index] -= 1
      counts[index + 1] -= 1
      best = min(best, arrange(&counts, index: index, melds: melds, partials: partials + 1, pair: pair, need: need, memo: &memo))
      counts[index] += 1
      counts[index + 1] += 1
    }
    if index < 27, index % 9 <= 6, counts[index + 2] > 0, partials < need {
      counts[index] -= 1
      counts[index + 2] -= 1
      best = min(best, arrange(&counts, index: index, melds: melds, partials: partials + 1, pair: pair, need: need, memo: &memo))
      counts[index] += 1
      counts[index + 2] += 1
    }
    let saved = counts[index]
    counts[index] = 0
    best = min(best, arrange(&counts, index: index + 1, melds: melds, partials: partials, pair: pair, need: need, memo: &memo))
    counts[index] = saved
    memo[key] = best
    return best
  }

  private static func fanLine(
    waits: [PracticeWait], held: [TileKind], tenpai: Bool, shortHand: Int?
  ) -> String {
    if let shortHand {
      return "只有\(shortHand)番，不够 8 番"
    }
    let close = closeFanNotes(tiles: held)
    guard tenpai, let best = waits.max(by: { $0.nonFlowerPoints < $1.nonFlowerPoints }) else {
      return ""
    }
    let names = best.fanNames.prefix(3).joined(separator: "、")
    let scored = names.isEmpty ? "番 还没有成型的番" : "番 已有\(names)"
    if best.nonFlowerPoints >= 8 {
      return "\(scored)，共\(best.nonFlowerPoints)番"
    }
    let gap = "只有\(best.nonFlowerPoints)番，还差\(max(1, 8 - best.nonFlowerPoints))番"
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

  public static func tileLabel(_ tile: TileKind) -> String { name(tile) }

  private static func name(_ tile: TileKind) -> String {
    if let suit = tile.suit, let rank = tile.rank {
      return "\(rank)\(["万", "筒", "条"][suit.rawValue])"
    }
    if let wind = tile.wind { return ["东", "南", "西", "北"][wind.rawValue] }
    if let dragon = tile.dragon { return ["中", "发", "白"][dragon.rawValue] }
    return "花"
  }
}
