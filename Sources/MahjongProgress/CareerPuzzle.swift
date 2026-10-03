import MahjongRules

/// Fixed openings for special-hand career levels. The next draw completes the target.
public enum CareerDeals {
  public static func opening(_ puzzle: CareerPuzzle) -> GameState {
    let winning = tiles(for: puzzle)
    let held = Array(winning.dropLast())
    let draw = winning.last!
    return build(held: held, draw: draw)
  }

  public static func tiles(for puzzle: CareerPuzzle) -> [TileKind] {
    switch puzzle {
    case .sevenPairs:
      return pairs([
        .dot1, .dot9, .bamboo2, .bamboo8, .character3, .character7, .east,
      ])
    case .honorsKnitted:
      return [
        .character1, .character4, .character7,
        .dot2, .dot5, .dot8,
        .bamboo3, .bamboo6, .bamboo9,
        .east, .south, .west, .north, .red,
      ]
    case .knittedStraight:
      return [
        .character1, .character4, .character7,
        .dot2, .dot5, .dot8,
        .bamboo3, .bamboo6, .bamboo9,
        .character2, .character2, .character2,
        .white, .white,
      ]
    }
  }

  private static func pairs(_ kinds: [TileKind]) -> [TileKind] {
    kinds.flatMap { [$0, $0] }
  }

  private static func build(held: [TileKind], draw: TileKind) -> GameState {
    var used: [TileKind: Int] = [:]
    func take(_ kind: TileKind) -> Tile {
      let copy = used[kind, default: 0]
      precondition(copy < 4, "puzzle reused a tile")
      used[kind] = copy + 1
      return Tile(kind: kind, copy: copy)
    }
    var players = Array(repeating: PlayerState(), count: 4)
    players[0].concealed = held.map(take)
    var wallTiles = [take(draw)]
    for kind in TileSet.normalKinds where wallTiles.count < 12 {
      if used[kind, default: 0] < 4 {
        wallTiles.append(take(kind))
      }
    }
    return GameState(
      wall: Wall(tiles: wallTiles),
      players: players,
      phase: .awaitingDraw(seat: 0)
    )
  }
}
