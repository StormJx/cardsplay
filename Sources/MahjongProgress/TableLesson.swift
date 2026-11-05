import MahjongRules

/// The first game: one fixed wall that walks through a chow, a pung, and the 8-fan minimum.
public enum TableLesson {
  public static func opening() -> GameState {
    var used: [TileKind: Int] = [:]
    func take(_ kind: TileKind) -> Tile {
      let copy = used[kind, default: 0]
      precondition(copy < 4, "lesson reused \(kind)")
      used[kind] = copy + 1
      return Tile(kind: kind, copy: copy)
    }

    let human: [TileKind] = [
      .character2, .character2,
      .character3, .character3,
      .character4,
      .character5, .character5, .character5,
      .character7, .character8,
      .east, .east,
      .west,
    ]
    var players = Array(repeating: PlayerState(), count: 4)
    players[0].concealed = human.map(take)
    players[1].concealed = [take(.east), take(.north)]
    players[2].concealed = [take(.south), take(.green)]
    players[3].concealed = [take(.character1), take(.white)]

    let wallPlan: [TileKind] = [
      .bamboo1, .bamboo2, .bamboo3,
      .character6,
      .bamboo4, .bamboo5, .bamboo6, .bamboo7,
      .character6,
    ]
    let wallTiles = wallPlan.map(take)
    for seat in 1..<4 {
      while players[seat].concealed.count < 13 {
        guard let kind = TileSet.normalKinds.first(where: { used[$0, default: 0] < 4 }) else {
          preconditionFailure("lesson ran out of tiles")
        }
        players[seat].concealed.append(take(kind))
      }
    }
    return GameState(
      wall: Wall(tiles: wallTiles),
      players: players,
      phase: .awaitingDiscard(seat: 3)
    )
  }

  public static func scriptedDiscard(seat: Int, hand: [TileKind], discardsSoFar: Int) -> TileKind? {
    let plan: [TileKind]
    switch seat {
    case 0: plan = [.west, .character5, .character6]
    case 1: plan = [.north, .east]
    case 2: plan = [.south, .green]
    case 3: plan = [.character1, .white]
    default: return nil
    }
    guard !plan.isEmpty else { return nil }
    let kind = discardsSoFar < plan.count ? plan[discardsSoFar] : plan[plan.count - 1]
    if hand.contains(kind) { return kind }
    return hand.first
  }

  public static func prompt(state: GameState) -> String {
    switch state.phase {
    case let .awaitingResponses(discarder, tile):
      if !state.legalChows(seat: 0, discard: tile.kind, discarder: discarder).isEmpty {
        return "这张可以吃。点「吃」。可跳过。"
      }
      if state.canPung(seat: 0, discard: tile.kind) {
        return "这张可以碰。点「碰」。"
      }
      return "第一局固定牌。可跳过。"
    case .awaitingDiscard(let seat) where seat == 0:
      if let context = WinContextBuilder.selfDraw(
        state: state, seat: 0, roundWind: .east, seatWind: .east),
        let score = MCRScorer.score(context)
      {
        if score.isLegalWin {
          return "够 8 番了。点「和」。"
        }
        return "这手只有 \(score.nonFlowerPoints) 番，不够 8 番，不能和。打出五万。"
      }
      if state.players[0].concealed.contains(where: { $0.kind == .west }) {
        return "吃好了。打出西。"
      }
      if !state.players[0].concealed.contains(where: { $0.kind == .east }),
        state.players[0].concealed.contains(where: { $0.kind == .character6 })
      {
        return "碰好了。打出六万。"
      }
      return "按提示打出牌。可跳过。"
    default:
      return "上家打出一万后可以吃。可跳过。"
    }
  }
}
