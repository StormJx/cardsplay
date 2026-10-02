public enum MCRScorer {
  public static func score(_ context: WinContext) -> ScoreResult? {
    WinningAnalyzer.structures(for: context)
      .map { score(context, structure: $0) }
      .max { lhs, rhs in
        if lhs.totalPoints != rhs.totalPoints { return lhs.totalPoints < rhs.totalPoints }
        let l = lhs.awards.map(\.fan.rawValue)
        let r = rhs.awards.map(\.fan.rawValue)
        return l.lexicographicallyPrecedes(r)
      }
  }

  public static func scores(_ context: WinContext) -> [ScoreResult] {
    WinningAnalyzer.structures(for: context).map { score(context, structure: $0) }
  }

  private static func score(_ context: WinContext, structure: WinningStructure) -> ScoreResult {
    let detector = Detector(context: context, structure: structure)
    var candidates = detector.detect()

    let nonFlowerCandidates = candidates.filter { $0.fan != .flower }
    if nonFlowerCandidates.isEmpty {
      candidates.append(.init(fan: .chickenHand))
    }

    let ordered = candidates.sorted {
      if $0.fan.points != $1.fan.points { return $0.fan.points > $1.fan.points }
      return $0.fan.rawValue < $1.fan.rawValue
    }
    var accepted: [FanAward] = []
    var excluded: [ExcludedFan] = []
    var blocked: Set<Fan> = []
    for award in ordered {
      if let source = accepted.first(where: { source in
        transitiveExclusions(of: source.fan).contains(award.fan)
      }) {
        excluded.append(.init(fan: award.fan, excludedBy: source.fan))
        blocked.insert(award.fan)
      } else if !blocked.contains(award.fan) {
        accepted.append(award)
      }
    }

    accepted.sort { $0.fan.rawValue < $1.fan.rawValue }
    let nonFlower = accepted.filter { $0.fan != .flower }.reduce(0) { $0 + $1.points }
    let flowers = accepted.first(where: { $0.fan == .flower })?.points ?? 0
    return ScoreResult(
      structure: structure,
      awards: accepted,
      excluded: excluded.sorted { $0.fan.rawValue < $1.fan.rawValue },
      nonFlowerPoints: nonFlower,
      flowerPoints: flowers,
      totalPoints: nonFlower + flowers,
      isLegalWin: nonFlower >= 8,
      ruleVersion: MCRRuleBook.version
    )
  }

  private static func transitiveExclusions(of fan: Fan) -> Set<Fan> {
    var result = MCRRuleBook.exclusions[fan] ?? []
    var queue = Array(result)
    while let next = queue.popLast() {
      for nested in MCRRuleBook.exclusions[next] ?? [] where !result.contains(nested) {
        result.insert(nested)
        queue.append(nested)
      }
    }
    return result
  }
}
private struct Detector {
  let context: WinContext
  let structure: WinningStructure

  private var allTiles: [TileKind] { context.allTiles }
  private var groups: [Group] { structure.groups }
  private var chows: [Group] { groups.filter(\.isChow) }
  private var pungs: [Group] { groups.filter(\.isPungLike) }
  private var kongs: [Group] { groups.filter(\.isKong) }
  private var pair: TileKind? { structure.pair }

  func detect() -> [FanAward] {
    var found: [Fan: FanAward] = [:]
    func add(_ fan: Fan, count: Int = 1, _ evidence: [String] = []) {
      guard count > 0 else { return }
      found[fan] = .init(fan: fan, count: count, evidence: evidence)
    }

    let windPungs = pungs.compactMap { $0.firstTile.wind == nil ? nil : $0.firstTile }
    let dragonPungs = pungs.compactMap { $0.firstTile.dragon == nil ? nil : $0.firstTile }
    let concealedPungs = pungs.filter(\.isConcealedPungLike).count
    let concealedKongs = kongs.filter(\.isConcealedPungLike).count
    let exposedKongs = kongs.count - concealedKongs
    let allRanks = allTiles.compactMap(\.rank)
    let suits = Set(allTiles.compactMap(\.suit))
    let hasHonors = allTiles.contains(where: \.isHonor)

    // 88 fan.
    if windPungs.count == 4 { add(.bigFourWinds) }
    if dragonPungs.count == 3 { add(.bigThreeDragons) }
    let green: Set<TileKind> = [
      TileKind(suit: .bamboo, rank: 2)!, TileKind(suit: .bamboo, rank: 3)!,
      TileKind(suit: .bamboo, rank: 4)!, TileKind(suit: .bamboo, rank: 6)!,
      TileKind(suit: .bamboo, rank: 8)!, TileKind(dragon: .green),
    ]
    if Set(allTiles).isSubset(of: green) { add(.allGreen) }
    if isNineGates { add(.nineGates) }
    if kongs.count == 4 { add(.fourKongs) }
    if isSevenShiftedPairs { add(.sevenShiftedPairs) }
    if structure.shape == .thirteenOrphans { add(.thirteenOrphans) }

    // 64 fan.
    if allTiles.allSatisfy(\.isTerminal) { add(.allTerminals) }
    if windPungs.count == 3, pair?.wind != nil { add(.littleFourWinds) }
    if dragonPungs.count == 2, pair?.dragon != nil { add(.littleThreeDragons) }
    if allTiles.allSatisfy(\.isHonor) { add(.allHonors) }
    if concealedPungs == 4 { add(.fourConcealedPungs) }
    if isPureTerminalChows { add(.pureTerminalChows) }

    // 48 and 32 fan.
    add(.quadrupleChow, count: identicalChowMaximum(4))
    if shiftedPungRun(length: 4, mixed: false) { add(.fourPureShiftedPungs) }
    if pureShiftedChows(length: 4) { add(.fourPureShiftedChows) }
    if kongs.count == 3 { add(.threeKongs) }
    if allTiles.allSatisfy(\.isTerminalOrHonor), hasHonors, allTiles.contains(where: \.isTerminal) {
      add(.allTerminalsAndHonors)
    }

    // 24 fan.
    if structure.shape == .sevenPairs { add(.sevenPairs) }
    if structure.shape == .greaterHonorsKnitted { add(.greaterHonorsKnitted) }
    if !pungs.isEmpty, chows.isEmpty,
      allTiles.allSatisfy({ $0.rank.map { [2, 4, 6, 8].contains($0) } == true })
    {
      add(.allEvenPungs)
    }
    if suits.count == 1, !hasHonors { add(.fullFlush) }
    add(.pureTripleChow, count: identicalChowMaximum(3))
    if shiftedPungRun(length: 3, mixed: false) { add(.pureShiftedPungs) }
    if allRanks.count == allTiles.count, allRanks.allSatisfy({ (7...9).contains($0) }) {
      add(.upperTiles)
    }
    if allRanks.count == allTiles.count, allRanks.allSatisfy({ (4...6).contains($0) }) {
      add(.middleTiles)
    }
    if allRanks.count == allTiles.count, allRanks.allSatisfy({ (1...3).contains($0) }) {
      add(.lowerTiles)
    }

    // 16 fan.
    if hasChows(starts: [1, 4, 7], sameSuit: true) { add(.pureStraight) }
    if isThreeSuitedTerminalChows { add(.threeSuitedTerminalChows) }
    if pureShiftedChows(length: 3) { add(.pureShiftedChows) }
    if everyComponentContainsFive { add(.allFives) }
    if triplePungCount > 0 { add(.triplePung, count: triplePungCount) }
    if concealedPungs == 3 { add(.threeConcealedPungs) }

    // 12 fan.
    if structure.shape == .lesserHonorsKnitted { add(.lesserHonorsKnitted) }
    if structure.shape == .knittedStraight { add(.knittedStraight) }
    if !allRanks.isEmpty, allRanks.allSatisfy({ $0 > 5 }) { add(.upperFour) }
    if !allRanks.isEmpty, allRanks.allSatisfy({ $0 < 5 }) { add(.lowerFour) }
    if windPungs.count == 3 { add(.bigThreeWinds) }

    // 8 fan.
    if hasChows(starts: [1, 4, 7], sameSuit: false) { add(.mixedStraight) }
    let reversible: Set<TileKind> = [
      .dot1, .dot2, .dot3, .dot4, .dot5, .dot8, .dot9,
      .bamboo2, .bamboo4, .bamboo5, .bamboo6, .bamboo8, .bamboo9, .white,
    ]
    if Set(allTiles).isSubset(of: reversible) { add(.reversibleTiles) }
    if mixedTripleChowCount > 0 { add(.mixedTripleChow, count: mixedTripleChowCount) }
    if shiftedPungRun(length: 3, mixed: true) { add(.mixedShiftedPungs) }
    if context.isLastWallTile, context.isSelfDrawn { add(.lastTileDraw) }
    if context.isLastDiscard, !context.isSelfDrawn { add(.lastTileClaim) }
    if context.method == .kongReplacement { add(.outWithReplacement) }
    if context.method == .robbingKong { add(.robbingKong) }
    if concealedKongs == 2 { add(.twoConcealedKongs) }

    // 6 fan.
    if structure.shape == .standard, chows.isEmpty { add(.allPungs) }
    if suits.count == 1, hasHonors { add(.halfFlush) }
    if mixedShiftedChows { add(.mixedShiftedChows) }
    if suits.count == 3,
      allTiles.contains(where: { $0.wind != nil }),
      allTiles.contains(where: { $0.dragon != nil })
    {
      add(.allTypes)
    }
    if groups.count == 4, groups.allSatisfy(\.isExposed), !context.isSelfDrawn,
      pair == context.winningTile
    {
      add(.meldedHand)
    }
    if dragonPungs.count == 2 { add(.twoDragonPungs) }

    // 4 fan.
    if structure.shape == .standard, componentsAllContainTerminalOrHonor { add(.outsideHand) }
    if !context.hasExposedMeld, context.isSelfDrawn { add(.fullyConcealedHand) }
    if exposedKongs == 2 { add(.twoMeldedKongs) }
    if context.visibleTileCounts[context.winningTile, default: 0] >= 3 { add(.lastTile) }

    // 2 fan.
    if !dragonPungs.isEmpty { add(.dragonPung, count: dragonPungs.count) }
    let prevalent = TileKind(wind: context.roundWind)
    if windPungs.contains(prevalent) { add(.prevalentWind) }
    let seat = TileKind(wind: context.seatWind)
    if windPungs.contains(seat) { add(.seatWind) }
    if !context.hasExposedMeld, !context.isSelfDrawn { add(.concealedHand) }
    if structure.shape == .standard, groups.count == 4, groups.allSatisfy(\.isChow),
      pair?.isSuited == true
    {
      add(.allChows)
    }
    let hogs = allTiles.counts.filter { kind, count in
      count == 4 && !groups.contains(where: { $0.isKong && $0.firstTile == kind })
    }.count
    add(.tileHog, count: hogs)
    add(.doublePung, count: doublePungCount)
    if concealedPungs == 2 { add(.twoConcealedPungs) }
    add(.concealedKong, count: concealedKongs)
    if allTiles.allSatisfy(\.isSimple) { add(.allSimples) }

    // 1 fan.
    add(.pureDoubleChow, count: pureDoubleChowCount)
    add(.mixedDoubleChow, count: mixedDoubleChowCount)
    add(.shortStraight, count: shortStraightCount)
    add(.twoTerminalChows, count: terminalChowPairCount)
    add(.pungOfTerminalsOrHonors, count: terminalHonorPungCount)
    add(.meldedKong, count: exposedKongs)
    if suits.count == 2 { add(.oneVoidedSuit) }
    if !hasHonors { add(.noHonors) }
    switch waitType {
    case .edge: add(.edgeWait)
    case .closed: add(.closedWait)
    case .single: add(.singleWait)
    case nil: break
    }
    if context.isSelfDrawn { add(.selfDraw) }
    if context.flowerCount > 0 { add(.flower, count: context.flowerCount) }
    return Array(found.values)
  }

  private var isNineGates: Bool {
    guard !context.hasExposedMeld, Set(allTiles.compactMap(\.suit)).count == 1,
      allTiles.count == 14, !allTiles.contains(where: \.isHonor)
    else { return false }
    let counts = Dictionary(grouping: allTiles.compactMap(\.rank), by: { $0 }).mapValues(\.count)
    return counts[1, default: 0] >= 3 && counts[9, default: 0] >= 3
      && (2...8).allSatisfy { counts[$0, default: 0] >= 1 }
  }

  private var isSevenShiftedPairs: Bool {
    guard structure.shape == .sevenPairs, let suit = allTiles.first?.suit,
      allTiles.allSatisfy({ $0.suit == suit })
    else { return false }
    let ranks = allTiles.counts.keys.compactMap(\.rank).sorted()
    guard ranks.count == 7 else { return false }
    return zip(ranks, ranks.dropFirst()).allSatisfy { $1 == $0 + 1 }
  }

  private var isPureTerminalChows: Bool {
    guard structure.shape == .standard, chows.count == 4,
      let pair, pair.rank == 5, !allTiles.contains(where: \.isHonor)
    else { return false }
    let starts = chows.compactMap(chowKey)
    return starts.count == 4
      && Set(starts.map(\.suit)).count == 1
      && starts.filter { $0.start == 1 }.count == 2
      && starts.filter { $0.start == 7 }.count == 2
  }

  private func identicalChowMaximum(_ required: Int) -> Int {
    let counts = Dictionary(grouping: chows.compactMap(chowKey), by: { $0 }).mapValues(\.count)
    return counts.values.filter { $0 >= required }.count
  }

  private func shiftedPungRun(length: Int, mixed: Bool) -> Bool {
    let keys = pungs.compactMap { group -> (Suit, Int)? in
      guard let suit = group.firstTile.suit, let rank = group.firstTile.rank else { return nil }
      return (suit, rank)
    }
    for selection in combinations(keys, choosing: length) {
      let ranks = selection.map(\.1).sorted()
      guard zip(ranks, ranks.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { continue }
      let suitCount = Set(selection.map(\.0)).count
      if (!mixed && suitCount == 1) || (mixed && suitCount == length) { return true }
    }
    return false
  }

  private func pureShiftedChows(length: Int) -> Bool {
    for selection in combinations(chows.compactMap(chowKey), choosing: length) {
      guard Set(selection.map(\.suit)).count == 1 else { continue }
      let starts = selection.map(\.start).sorted()
      let differences = zip(starts, starts.dropFirst()).map { $1 - $0 }
      if Set(differences).count == 1, let difference = differences.first,
        difference == 1 || difference == 2
      {
        return true
      }
    }
    return false
  }

  private func hasChows(starts: [Int], sameSuit: Bool) -> Bool {
    let keys = chows.compactMap(chowKey)
    for selection in combinations(keys, choosing: starts.count) {
      guard selection.map(\.start).sorted() == starts else { continue }
      let suitCount = Set(selection.map(\.suit)).count
      if (sameSuit && suitCount == 1) || (!sameSuit && suitCount == starts.count) { return true }
    }
    return false
  }

  private var isThreeSuitedTerminalChows: Bool {
    guard chows.count == 4, let pair, pair.rank == 5, pair.isSuited else { return false }
    let chowKeys = chows.compactMap(chowKey)
    let pairSuit = pair.suit!
    let other = Suit.allCases.filter { $0 != pairSuit }
    return other.allSatisfy { suit in
      chowKeys.contains(.init(suit: suit, start: 1))
        && chowKeys.contains(.init(suit: suit, start: 7))
    }
  }

  private var everyComponentContainsFive: Bool {
    guard structure.shape == .standard, pair?.rank == 5 else { return false }
    return groups.allSatisfy { $0.tiles.contains(where: { $0.rank == 5 }) }
  }

  private var triplePungCount: Int {
    let keys = pungs.compactMap { group -> (Suit, Int)? in
      guard let suit = group.firstTile.suit, let rank = group.firstTile.rank else { return nil }
      return (suit, rank)
    }
    return (1...9).filter { rank in Set(keys.filter { $0.1 == rank }.map(\.0)).count == 3 }.count
  }

  private var mixedTripleChowCount: Int {
    let keys = chows.compactMap(chowKey)
    return (1...7).filter { start in
      Set(keys.filter { $0.start == start }.map(\.suit)).count == 3
    }.count
  }

  private var mixedShiftedChows: Bool {
    let keys = chows.compactMap(chowKey)
    for selection in combinations(keys, choosing: 3) {
      guard Set(selection.map(\.suit)).count == 3 else { continue }
      let starts = selection.map(\.start).sorted()
      if starts[1] == starts[0] + 1, starts[2] == starts[1] + 1 { return true }
    }
    return false
  }

  private var componentsAllContainTerminalOrHonor: Bool {
    guard let pair, pair.isTerminalOrHonor else { return false }
    return groups.allSatisfy { $0.tiles.contains(where: \.isTerminalOrHonor) }
  }

  private var doublePungCount: Int {
    let suited = pungs.compactMap { group -> (Suit, Int)? in
      guard let suit = group.firstTile.suit, let rank = group.firstTile.rank else { return nil }
      return (suit, rank)
    }
    return (1...9).reduce(0) { total, rank in
      total + (Set(suited.filter { $0.1 == rank }.map(\.0)).count >= 2 ? 1 : 0)
    }
  }

  private var pureDoubleChowCount: Int {
    Dictionary(grouping: chows.compactMap(chowKey), by: { $0 })
      .values.reduce(0) { $0 + $1.count / 2 }
  }

  private var mixedDoubleChowCount: Int {
    let keys = chows.compactMap(chowKey)
    return (1...7).reduce(0) { total, start in
      total + Set(keys.filter { $0.start == start }.map(\.suit)).count / 2
    }
  }

  private var shortStraightCount: Int {
    let keys = chows.compactMap(chowKey)
    var count = 0
    for suit in Suit.allCases {
      let starts = keys.filter { $0.suit == suit }.map(\.start)
      count += starts.filter { start in starts.contains(start + 3) }.count
    }
    return count
  }

  private var terminalChowPairCount: Int {
    let keys = chows.compactMap(chowKey)
    return Suit.allCases.filter { suit in
      keys.contains(.init(suit: suit, start: 1)) && keys.contains(.init(suit: suit, start: 7))
    }.count
  }

  private var terminalHonorPungCount: Int {
    pungs.filter { $0.firstTile.isTerminalOrHonor }.count
  }

  private enum Wait { case edge, closed, single }
  private var waitType: Wait? {
    if pair == context.winningTile { return .single }
    guard let winningRank = context.winningTile.rank, let winningSuit = context.winningTile.suit
    else { return nil }
    let matching = chows.compactMap(chowKey).filter {
      $0.suit == winningSuit && ($0.start...($0.start + 2)).contains(winningRank)
    }
    guard matching.count == 1, let chow = matching.first else { return nil }
    if winningRank == chow.start + 1 { return .closed }
    if (chow.start == 1 && winningRank == 3) || (chow.start == 7 && winningRank == 7) {
      return .edge
    }
    return nil
  }

  private struct ChowKey: Hashable {
    let suit: Suit
    let start: Int
  }

  private func chowKey(_ group: Group) -> ChowKey? {
    if case let .chow(suit, start, _) = group { return .init(suit: suit, start: start) }
    return nil
  }

  private func combinations<T>(_ values: [T], choosing count: Int) -> [[T]] {
    guard count > 0 else { return [[]] }
    guard values.count >= count else { return [] }
    if values.count == count { return [values] }
    if count == 1 { return values.map { [$0] } }
    var result: [[T]] = []
    for index in 0...(values.count - count) {
      result += combinations(Array(values[(index + 1)...]), choosing: count - 1)
        .map { [values[index]] + $0 }
    }
    return result
  }
}
