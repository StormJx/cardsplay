import MahjongRules

/// Builds win contexts from a live `GameState`. Scoring stays in `MahjongRules`.
public enum WinContextBuilder {
  public static func selfDraw(
    state: GameState,
    seat: Int,
    roundWind: Wind = .east
  ) -> WinContext? {
    let winningTile: TileKind
    if case let .drew(drawnSeat, tile) = state.events.last, drawnSeat == seat {
      winningTile = tile.kind
    } else if state.events.isEmpty, seat == 0, let tile = state.players[0].concealed.last {
      winningTile = tile.kind
    } else {
      return nil
    }
    let player = state.players[seat]
    return WinContext(
      concealedTiles: player.concealed.map(\.kind),
      melds: player.melds,
      winningTile: winningTile,
      method: selfDrawMethod(state: state, seat: seat),
      seatWind: Wind(rawValue: seat)!,
      roundWind: roundWind,
      flowerCount: player.flowers.count,
      isLastWallTile: state.wall.isEmpty
    )
  }

  public static func claim(
    state: GameState,
    seat: Int,
    tile: TileKind,
    method: WinMethod,
    roundWind: Wind = .east
  ) -> WinContext {
    let player = state.players[seat]
    return WinContext(
      concealedTiles: player.concealed.map(\.kind) + [tile],
      melds: player.melds,
      winningTile: tile,
      method: method,
      seatWind: Wind(rawValue: seat)!,
      roundWind: roundWind,
      flowerCount: player.flowers.count,
      isLastDiscard: state.wall.isEmpty
    )
  }

  public static func legalScore(
    state: GameState,
    seat: Int,
    tile: TileKind,
    method: WinMethod,
    roundWind: Wind = .east
  ) -> ScoreResult? {
    let context = claim(
      state: state, seat: seat, tile: tile, method: method, roundWind: roundWind)
    guard let score = MCRScorer.score(context), score.isLegalWin else { return nil }
    return score
  }

  public static func selfDrawScore(
    state: GameState,
    seat: Int,
    roundWind: Wind = .east
  ) -> ScoreResult? {
    guard let context = selfDraw(state: state, seat: seat, roundWind: roundWind),
      let score = MCRScorer.score(context),
      score.isLegalWin
    else { return nil }
    return score
  }

  private static func selfDrawMethod(state: GameState, seat: Int) -> WinMethod {
    for event in state.events.dropLast().reversed() {
      switch event {
      case .exposedFlower:
        continue
      case let .declaredKong(kongSeat, _, _) where kongSeat == seat:
        return .kongReplacement
      case let .claimed(claimSeat, type, _) where claimSeat == seat && type == .exposedKong:
        return .kongReplacement
      default:
        return .selfDraw
      }
    }
    return .selfDraw
  }
}
