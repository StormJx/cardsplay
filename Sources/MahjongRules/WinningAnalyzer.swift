public enum WinningAnalyzer {
  public static func structures(for context: WinContext) -> [WinningStructure] {
    guard !context.winningTile.isFlower,
      context.concealedTiles.contains(context.winningTile),
      TileSet.validateCounts(context.allTiles),
      context.melds.count <= 4
    else { return [] }

    var results = standardStructures(for: context)
    if context.melds.isEmpty {
      let tiles = context.concealedTiles.sorted()
      if isSevenPairs(tiles) {
        results.append(.init(shape: .sevenPairs, specialTiles: tiles))
      }
      if isThirteenOrphans(tiles) {
        results.append(.init(shape: .thirteenOrphans, specialTiles: tiles))
      }
      results.append(contentsOf: unrelatedStructures(tiles))
    }
    results.append(contentsOf: knittedStraightStructures(for: context))
    return Array(Set(results)).sorted(by: stableOrder)
  }

  public static func hasWinningStructure(_ context: WinContext) -> Bool {
    !structures(for: context).isEmpty
  }

  private static func standardStructures(for context: WinContext) -> [WinningStructure] {
    let requiredGroups = 4 - context.melds.count
    guard context.concealedTiles.count == requiredGroups * 3 + 2 else { return [] }
    var counts = Array(repeating: 0, count: 34)
    for tile in context.concealedTiles {
      guard tile.rawValue < 34 else { return [] }
      counts[tile.rawValue] += 1
    }

    let fixedGroups = context.melds.map(group(from:))
    var output: [WinningStructure] = []
    for pairIndex in 0..<34 where counts[pairIndex] >= 2 {
      var remaining = counts
      remaining[pairIndex] -= 2
      var concealedGroups: [Group] = []
      enumerateGroups(
        counts: &remaining,
        needed: requiredGroups,
        context: context,
        groups: &concealedGroups
      ) { completedGroups in
        output.append(
          .init(
            shape: .standard,
            groups: fixedGroups + completedGroups,
            pair: TileKind(rawValue: pairIndex)
          ))
      }
    }
    return output
  }

  private static func enumerateGroups(
    counts: inout [Int],
    needed: Int,
    context: WinContext,
    groups: inout [Group],
    completion: ([Group]) -> Void
  ) {
    guard let index = counts.firstIndex(where: { $0 > 0 }) else {
      if groups.count == needed { completion(groups) }
      return
    }
    guard groups.count < needed else { return }
    let tile = TileKind(rawValue: index)!

    if counts[index] >= 3 {
      counts[index] -= 3
      let concealed = context.isSelfDrawn || tile != context.winningTile
      groups.append(.pung(tile: tile, concealed: concealed))
      enumerateGroups(
        counts: &counts, needed: needed, context: context, groups: &groups, completion: completion)
      groups.removeLast()
      counts[index] += 3
    }

    if let rank = tile.rank, rank <= 7,
      counts[index + 1] > 0, counts[index + 2] > 0
    {
      counts[index] -= 1
      counts[index + 1] -= 1
      counts[index + 2] -= 1
      groups.append(.chow(suit: tile.suit!, start: rank, exposed: false))
      enumerateGroups(
        counts: &counts, needed: needed, context: context, groups: &groups, completion: completion)
      groups.removeLast()
      counts[index] += 1
      counts[index + 1] += 1
      counts[index + 2] += 1
    }
  }

  private static func group(from meld: Meld) -> Group {
    switch meld.type {
    case .chow:
      return .chow(suit: meld.kind.suit!, start: meld.kind.rank!, exposed: true)
    case .pung:
      return .pung(tile: meld.kind, concealed: false)
    case .exposedKong, .addedKong:
      return .kong(tile: meld.kind, concealed: false)
    case .concealedKong:
      return .kong(tile: meld.kind, concealed: true)
    }
  }

  private static func isSevenPairs(_ tiles: [TileKind]) -> Bool {
    tiles.count == 14 && tiles.counts.values.allSatisfy { $0 == 2 || $0 == 4 }
  }

  private static func isThirteenOrphans(_ tiles: [TileKind]) -> Bool {
    guard tiles.count == 14 else { return false }
    let counts = tiles.counts
    return Set(counts.keys) == Set(TileSet.orphanKinds)
      && counts.values.filter { $0 == 2 }.count == 1
      && counts.values.allSatisfy { $0 == 1 || $0 == 2 }
  }

  private static func unrelatedStructures(_ tiles: [TileKind]) -> [WinningStructure] {
    guard tiles.count == 14, Set(tiles).count == 14 else { return [] }
    let honorCount = tiles.filter(\.isHonor).count
    guard honorCount >= 5 else { return [] }
    for mapping in knittedMappings() {
      let allowed = Set(mapping + TileKind.allCases.filter(\.isHonor))
      if Set(tiles).isSubset(of: allowed) {
        let shape: HandShape = honorCount == 7 ? .greaterHonorsKnitted : .lesserHonorsKnitted
        return [.init(shape: shape, specialTiles: tiles)]
      }
    }
    return []
  }

  private static func knittedStraightStructures(for context: WinContext) -> [WinningStructure] {
    guard context.melds.count <= 1 else { return [] }
    let fixed = context.melds.map(group(from:))
    var output: [WinningStructure] = []
    for knitted in knittedMappings() {
      var remaining = context.concealedTiles.counts
      var found = true
      for tile in knitted {
        guard remaining[tile, default: 0] > 0 else {
          found = false
          break
        }
        remaining[tile]! -= 1
      }
      guard found else { continue }
      let rest = remaining.flatMap { tile, count in Array(repeating: tile, count: count) }
      if fixed.count == 1 {
        if rest.count == 2, rest[0] == rest[1] {
          output.append(
            .init(shape: .knittedStraight, groups: fixed, pair: rest[0], specialTiles: knitted))
        }
      } else {
        guard rest.count == 5 else { continue }
        for pair in Set(rest) where rest.filter({ $0 == pair }).count >= 2 {
          var leftover = rest
          leftover.remove(at: leftover.firstIndex(of: pair)!)
          leftover.remove(at: leftover.firstIndex(of: pair)!)
          if let group = singleGroup(from: leftover, context: context) {
            output.append(
              .init(shape: .knittedStraight, groups: [group], pair: pair, specialTiles: knitted))
          }
        }
      }
    }
    return output
  }

  private static func singleGroup(from tiles: [TileKind], context: WinContext) -> Group? {
    let sorted = tiles.sorted()
    guard sorted.count == 3 else { return nil }
    if Set(sorted).count == 1 {
      return .pung(
        tile: sorted[0], concealed: context.isSelfDrawn || sorted[0] != context.winningTile)
    }
    if sorted.allSatisfy(\.isSuited), Set(sorted.compactMap(\.suit)).count == 1,
      sorted[0].rank! + 1 == sorted[1].rank!,
      sorted[1].rank! + 1 == sorted[2].rank!
    {
      return .chow(suit: sorted[0].suit!, start: sorted[0].rank!, exposed: false)
    }
    return nil
  }

  private static func knittedMappings() -> [[TileKind]] {
    let rankSets = [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
    return permutations([Suit.characters, .dots, .bamboo]).map { suits in
      zip(suits, rankSets).flatMap { suit, ranks in
        ranks.map { TileKind(suit: suit, rank: $0)! }
      }
    }
  }

  private static func permutations<T>(_ values: [T]) -> [[T]] {
    guard values.count > 1 else { return [values] }
    return values.indices.flatMap { index -> [[T]] in
      var rest = values
      let first = rest.remove(at: index)
      return permutations(rest).map { [first] + $0 }
    }
  }

  private static func stableOrder(_ lhs: WinningStructure, _ rhs: WinningStructure) -> Bool {
    let l = "\(lhs.shape.rawValue)|\(lhs.pair?.rawValue ?? -1)|\(lhs.groups)"
    let r = "\(rhs.shape.rawValue)|\(rhs.pair?.rawValue ?? -1)|\(rhs.groups)"
    return l < r
  }
}
