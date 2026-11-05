import MahjongRules

enum KongPolicy {
  /// Concealed, added, and exposed kongs. A pair (将) or a tile that forms the tenpai wait is not used.
  /// Exposed claims pass a 13-tile hand (`removing` 3). Opponent concealed tiles are not an input.
  static func allows(kind: TileKind, removing: Int, tiles: [TileKind], meldCount: Int) -> Bool {
    let held = tiles.filter { $0 == kind }.count
    guard held >= removing, removing > 0 else { return false }
    let claimingDiscard = removing == 3
    let complete = (4 - meldCount) * 3 + (claimingDiscard ? 1 : 2)
    guard tiles.count == complete else { return false }
    // Konging the only pair leaves no pair. A tenpai tile is checked below.
    guard hasOtherPair(tiles, besides: kind) else { return false }

    let unique = Set(tiles)
    let views = unique.map { discard -> (Int, [TileKind]) in
      let rest = removed(discard, from: tiles, count: 1)
      return (standardShanten(rest, meldCount: meldCount), rest)
    }
    let standardBest = views.map(\.0).min() ?? 8
    let pairBest = unique.map { pairShanten(removed($0, from: tiles, count: 1)) }.min() ?? 8
    if meldCount == 0, held >= 2, pairBest < standardBest || (pairBest == 0 && pairBest <= standardBest) {
      return false
    }

    let bestViews = views.filter { $0.0 == standardBest }.map(\.1)
    var seenPung = false
    var tenpaiTile = false
    for view in bestViews {
      let role = roles(of: kind, in: view, meldCount: meldCount, target: standardBest)
      if role.pung { seenPung = true }
      if role.pair, !hasOtherPair(view, besides: kind) { return false }
      if standardBest == 0 && role.tenpai { tenpaiTile = true }
    }
    if tenpaiTile { return false }
    if !seenPung, bestViews.contains(where: { view in
      roles(of: kind, in: view, meldCount: meldCount, target: standardBest).pair
    }) {
      return false
    }
    return true
  }

  private static func hasOtherPair(_ tiles: [TileKind], besides kind: TileKind) -> Bool {
    tiles.contains { tile in
      tile != kind && tiles.filter { $0 == tile }.count >= 2
    }
  }

  private struct Role {
    var pair = false
    var pung = false
    var tenpai = false
  }

  private static func roles(
    of kind: TileKind, in tiles: [TileKind], meldCount: Int, target: Int
  ) -> Role {
    let held = tiles.filter { $0 == kind }.count
    var role = Role()
    if held >= 2 {
      let locked = standardShanten(
        removed(kind, from: tiles, count: 2), meldCount: meldCount, pairLocked: true)
      role.pair = locked == target
    }
    if held >= 3 {
      role.pung = standardShanten(
        removed(kind, from: tiles, count: 3), meldCount: meldCount + 1) == target
    }
    if target == 0, held >= 1 {
      if held == 1, pureMelds(removed(kind, from: tiles, count: 1), meldCount: meldCount) {
        role.tenpai = true
      } else if !role.pung,
        standardShanten(removed(kind, from: tiles, count: 1), meldCount: meldCount) > target
      {
        role.tenpai = true
      }
    }
    return role
  }

  private static func pairShanten(_ tiles: [TileKind]) -> Int {
    let pairs = tiles.counts.values.reduce(0) { $0 + $1 / 2 }
    return 6 - min(7, pairs)
  }

  private static func pureMelds(_ tiles: [TileKind], meldCount: Int) -> Bool {
    let need = max(0, 4 - meldCount)
    guard tiles.filter({ !$0.isFlower }).count == need * 3 else { return false }
    var counts = Array(repeating: 0, count: 34)
    for tile in tiles where tile.rawValue < 34 { counts[tile.rawValue] += 1 }
    return exactMelds(&counts, index: 0, remaining: need)
  }

  private static func exactMelds(_ counts: inout [Int], index: Int, remaining: Int) -> Bool {
    if remaining == 0 { return counts.allSatisfy { $0 == 0 } }
    guard let next = (index..<34).first(where: { counts[$0] > 0 }) else { return false }
    if counts[next] >= 3 {
      counts[next] -= 3
      if exactMelds(&counts, index: next, remaining: remaining - 1) {
        counts[next] += 3
        return true
      }
      counts[next] += 3
    }
    if next < 27, next % 9 <= 6, counts[next + 1] > 0, counts[next + 2] > 0 {
      counts[next] -= 1
      counts[next + 1] -= 1
      counts[next + 2] -= 1
      if exactMelds(&counts, index: next, remaining: remaining - 1) {
        counts[next] += 1
        counts[next + 1] += 1
        counts[next + 2] += 1
        return true
      }
      counts[next] += 1
      counts[next + 1] += 1
      counts[next + 2] += 1
    }
    return false
  }

  private static func standardShanten(
    _ tiles: [TileKind], meldCount: Int, pairLocked: Bool = false
  ) -> Int {
    var counts = Array(repeating: 0, count: 34)
    for tile in tiles where tile.rawValue < 34 { counts[tile.rawValue] += 1 }
    let need = max(0, 4 - meldCount)
    var memo: [String: Int] = [:]
    return arrange(
      &counts, index: 0, melds: 0, partials: 0, pair: pairLocked, need: need, memo: &memo)
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
      best = min(
        best,
        arrange(&counts, index: index, melds: melds + 1, partials: partials, pair: pair, need: need, memo: &memo))
      counts[index] += 3
    }
    if index < 27, index % 9 <= 6, counts[index + 1] > 0, counts[index + 2] > 0 {
      counts[index] -= 1
      counts[index + 1] -= 1
      counts[index + 2] -= 1
      best = min(
        best,
        arrange(&counts, index: index, melds: melds + 1, partials: partials, pair: pair, need: need, memo: &memo))
      counts[index] += 1
      counts[index + 1] += 1
      counts[index + 2] += 1
    }
    if tileCount >= 2, !pair {
      counts[index] -= 2
      best = min(
        best,
        arrange(&counts, index: index, melds: melds, partials: partials, pair: true, need: need, memo: &memo))
      counts[index] += 2
    }
    if tileCount >= 2, partials < need {
      counts[index] -= 2
      best = min(
        best,
        arrange(
          &counts, index: index, melds: melds, partials: partials + 1, pair: pair, need: need, memo: &memo))
      counts[index] += 2
    }
    if index < 27, index % 9 <= 7, counts[index + 1] > 0, partials < need {
      counts[index] -= 1
      counts[index + 1] -= 1
      best = min(
        best,
        arrange(
          &counts, index: index, melds: melds, partials: partials + 1, pair: pair, need: need, memo: &memo))
      counts[index] += 1
      counts[index + 1] += 1
    }
    if index < 27, index % 9 <= 6, counts[index + 2] > 0, partials < need {
      counts[index] -= 1
      counts[index + 2] -= 1
      best = min(
        best,
        arrange(
          &counts, index: index, melds: melds, partials: partials + 1, pair: pair, need: need, memo: &memo))
      counts[index] += 1
      counts[index + 2] += 1
    }
    let saved = counts[index]
    counts[index] = 0
    best = min(
      best,
      arrange(&counts, index: index + 1, melds: melds, partials: partials, pair: pair, need: need, memo: &memo))
    counts[index] = saved
    memo[key] = best
    return best
  }

  private static func removed(_ tile: TileKind, from tiles: [TileKind], count: Int) -> [TileKind] {
    var copy = tiles
    var left = count
    while left > 0, let index = copy.firstIndex(of: tile) {
      copy.remove(at: index)
      left -= 1
    }
    return copy
  }
}
