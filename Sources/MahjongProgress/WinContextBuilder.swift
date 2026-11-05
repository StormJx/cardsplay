import MahjongRules

/// Builds win contexts from a live `GameState`. Scoring stays in `MahjongRules`.
public enum WinContextBuilder {
  public static func selfDraw(
    state: GameState,
    seat: Int,
    roundWind: Wind = .east,
    seatWind: Wind? = nil
  ) -> WinContext? {
    let winningTile: TileKind
    if case let .drew(drawnSeat, tile) = state.events.last, drawnSeat == seat {
      winningTile = tile.kind
    } else if !hasDrawn(state, seat: seat),
      state.players[seat].concealed.count >= 14,
      let tile = state.players[seat].concealed.last
    {
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
      seatWind: seatWind ?? Wind(rawValue: seat)!,
      roundWind: roundWind,
      flowerCount: player.flowers.count,
      isLastWallTile: state.wall.isEmpty,
      visibleTileCounts: seenCounts(
        state: state, seat: seat, winningTile: winningTile, winningTileIsInHand: true)
    )
  }

  public static func claim(
    state: GameState,
    seat: Int,
    tile: TileKind,
    method: WinMethod,
    roundWind: Wind = .east,
    seatWind: Wind? = nil
  ) -> WinContext {
    let player = state.players[seat]
    return WinContext(
      concealedTiles: player.concealed.map(\.kind) + [tile],
      melds: player.melds,
      winningTile: tile,
      method: method,
      seatWind: seatWind ?? Wind(rawValue: seat)!,
      roundWind: roundWind,
      flowerCount: player.flowers.count,
      isLastDiscard: state.wall.isEmpty,
      visibleTileCounts: seenCounts(
        state: state, seat: seat, winningTile: tile, winningTileIsInHand: false)
    )
  }

  public static func legalScore(
    state: GameState,
    seat: Int,
    tile: TileKind,
    method: WinMethod,
    roundWind: Wind = .east,
    seatWind: Wind? = nil
  ) -> ScoreResult? {
    let context = claim(
      state: state, seat: seat, tile: tile, method: method, roundWind: roundWind,
      seatWind: seatWind)
    guard let score = MCRScorer.score(context), score.isLegalWin else { return nil }
    return score
  }

  public static func selfDrawScore(
    state: GameState,
    seat: Int,
    roundWind: Wind = .east,
    seatWind: Wind? = nil
  ) -> ScoreResult? {
    guard let context = selfDraw(state: state, seat: seat, roundWind: roundWind, seatWind: seatWind),
      let score = MCRScorer.score(context),
      score.isLegalWin
    else { return nil }
    return score
  }

  private static func hasDrawn(_ state: GameState, seat: Int) -> Bool {
    state.events.contains { event in
      if case let .drew(drawnSeat, _) = event { return drawnSeat == seat }
      return false
    }
  }

  /// Copies already seen, not counting the winning tile itself.
  /// Opponent concealed kongs stay hidden. The winner's own hand and melds count.
  private static func seenCounts(
    state: GameState,
    seat: Int,
    winningTile: TileKind,
    winningTileIsInHand: Bool
  ) -> [TileKind: Int] {
    var counts: [TileKind: Int] = [:]
    func add(_ kind: TileKind) {
      counts[kind, default: 0] += 1
    }
    for tile in state.players[seat].concealed { add(tile.kind) }
    for meld in state.players[seat].melds {
      for tile in meld.tiles { add(tile) }
    }
    for tile in state.players[seat].flowers { add(tile.kind) }
    if winningTileIsInHand {
      counts[winningTile, default: 0] -= 1
      if counts[winningTile] == 0 { counts.removeValue(forKey: winningTile) }
    }
    for other in 0..<4 where other != seat {
      for meld in state.players[other].melds where meld.type != .concealedKong {
        for tile in meld.tiles { add(tile) }
      }
      for tile in state.players[other].flowers { add(tile.kind) }
    }
    for tile in PublicInfo.rivers(events: state.events).flatMap({ $0 }) { add(tile) }
    if !winningTileIsInHand,
      case .awaitingResponses(_, let tile) = state.phase,
      tile.kind == winningTile
    {
      counts[winningTile, default: 0] -= 1
      if counts[winningTile] == 0 { counts.removeValue(forKey: winningTile) }
    }
    return counts.filter { $0.value > 0 }
  }

  /// A flower drawn while replacing a kong uses up the replacement. The next tile is not 杠上开花.
  private static func selfDrawMethod(state: GameState, seat: Int) -> WinMethod {
    var sawFlower = false
    for event in state.events.dropLast().reversed() {
      switch event {
      case .exposedFlower:
        sawFlower = true
        continue
      case let .declaredKong(kongSeat, _, _) where kongSeat == seat:
        return sawFlower ? .selfDraw : .kongReplacement
      case let .claimed(claimSeat, type, _) where claimSeat == seat && type == .exposedKong:
        return sawFlower ? .selfDraw : .kongReplacement
      default:
        return .selfDraw
      }
    }
    return .selfDraw
  }
}
