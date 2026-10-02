import MahjongRules

/// Counts and rivers a player may know. Opponent concealed tiles are never included.
public enum PublicInfo {
  public static func rivers(events: [GameEvent]) -> [[TileKind]] {
    var rivers = Array(repeating: [TileKind](), count: 4)
    var pendingSeat: Int?
    for event in events {
      switch event {
      case let .discarded(seat, tile):
        rivers[seat].append(tile.kind)
        pendingSeat = seat
      case .claimed:
        if let seat = pendingSeat, !rivers[seat].isEmpty { rivers[seat].removeLast() }
        pendingSeat = nil
      case .drew:
        pendingSeat = nil
      default:
        break
      }
    }
    return rivers
  }

  public static func unseenCount(state: GameState, kind: TileKind) -> Int {
    var seen = state.players[0].concealed.filter { $0.kind == kind }.count
    seen += state.players[0].melds.flatMap(\.tiles).filter { $0 == kind }.count
    seen += state.players[0].flowers.filter { $0.kind == kind }.count
    for seat in 1..<4 {
      for meld in state.players[seat].melds where meld.isExposed {
        seen += meld.tiles.filter { $0 == kind }.count
      }
      seen += state.players[seat].flowers.filter { $0.kind == kind }.count
    }
    var pending: TileKind?
    for event in state.events {
      switch event {
      case let .discarded(_, tile):
        if tile.kind == kind { seen += 1 }
        pending = tile.kind
      case .claimed:
        if pending == kind { seen -= 1 }
        pending = nil
      case .drew:
        pending = nil
      default:
        break
      }
    }
    return max(0, (kind.isFlower ? 1 : 4) - seen)
  }
}
