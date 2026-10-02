import MahjongAI
import MahjongRules

public struct ReplayAdvice: Hashable, Sendable {
  public let tile: TileKind
  public let efficiency: Int
  public let danger: Int
  public let fanPlan: Int
  public let total: Int

  public var dangerLabel: String {
    if danger <= 0 { return "低" }
    if danger < 10 { return "中" }
    return "高"
  }
}

public enum ReplayMark: String, Codable, Sendable {
  case skippedWin
  case dealtIn
  case missedKong
  case claimed
  case won
  case drawn
}

public struct ReplayNote: Hashable, Sendable {
  public let frameIndex: Int
  public let mark: ReplayMark
  public let text: String
}

public struct ReplayFrame: Sendable {
  public let index: Int
  public let state: GameState
  public let step: ReplayStep?
}

public enum ReplayError: Error, Equatable {
  case missingWinContext
  case rule(RuleViolation)
}

public enum HandReplay {
  public static func frames(seed: UInt64, steps: [ReplayStep]) throws -> [ReplayFrame] {
    var state = GameState(seed: seed)
    var frames = [ReplayFrame(index: 0, state: state, step: nil)]
    for step in steps {
      switch step {
      case let .command(command):
        do {
          try state.apply(command)
        } catch let error as RuleViolation {
          throw ReplayError.rule(error)
        }
      case let .declareWin(seat):
        guard let context = WinContextBuilder.selfDraw(state: state, seat: seat) else {
          throw ReplayError.missingWinContext
        }
        _ = state.adjudicateWinDeclaration(seat: seat, context: context)
      }
      frames.append(ReplayFrame(index: frames.count, state: state, step: step))
    }
    return frames
  }

  public static func state(seed: UInt64, steps: [ReplayStep]) throws -> GameState {
    try frames(seed: seed, steps: steps).last!.state
  }

  public static func notes(frames: [ReplayFrame]) -> [ReplayNote] {
    guard frames.count > 1 else { return [] }
    var notes: [ReplayNote] = []
    for index in 1..<frames.count {
      let previous = frames[index - 1].state
      let frame = frames[index]
      guard let step = frame.step else { continue }
      if let note = skippedWin(previous: previous, step: step, index: index) {
        notes.append(note)
      }
      if let note = missedKong(previous: previous, step: step, index: index) {
        notes.append(note)
      }
      if case .endedWin(let winner) = frame.state.phase, winner != 0,
        case let .awaitingResponses(discarder, _) = previous.phase, discarder == 0
      {
        notes.append(
          ReplayNote(
            frameIndex: index, mark: .dealtIn,
            text: "你打出的这张牌被点和。当时的建议只使用公开信息。"))
      }
      if case let .command(.resolveClaims(claims)) = step,
        claims.contains(where: { $0.type != .win })
      {
        notes.append(ReplayNote(frameIndex: index, mark: .claimed, text: "这里发生了吃、碰或杠。"))
      }
      if case .endedWin = frame.state.phase {
        notes.append(ReplayNote(frameIndex: index, mark: .won, text: "和牌。"))
      }
      if case .endedDraw = frame.state.phase {
        notes.append(ReplayNote(frameIndex: index, mark: .drawn, text: "流局。"))
      }
    }
    return notes
  }

  public static func advice(
    state: GameState,
    difficulty: AIDifficulty,
    scores: [Int]
  ) -> [ReplayAdvice] {
    guard case .awaitingDiscard(seat: 0) = state.phase else { return [] }
    let own = state.players[0].concealed.map(\.kind)
    guard !own.isEmpty else { return [] }
    let padded = scores.count == 4 ? scores : [0, 0, 0, 0]
    let information = AIInformationSet(
      seat: 0,
      ownTiles: own,
      ownMelds: state.players[0].melds,
      discards: PublicInfo.rivers(events: state.events),
      publicMelds: state.players.map { $0.melds.filter(\.isExposed) },
      exposedFlowers: state.players.map { $0.flowers.map(\.kind) },
      wallRemaining: state.wall.remainingCount,
      scores: padded,
      roundWind: .east,
      actionNumber: state.events.count
    )
    let profile = OpponentProfile(
      seat: 0,
      name: "复盘",
      avatarSystemName: "lightbulb",
      personality: .conservative,
      difficulty: difficulty
    )
    let decision = MahjongAIDecider.chooseDiscard(
      information: information,
      profile: profile,
      decisionSeed: UInt64(state.events.count)
    )
    return decision.candidates.prefix(3).map {
      ReplayAdvice(
        tile: $0.tile, efficiency: $0.efficiency, danger: $0.danger, fanPlan: $0.fanPlan,
        total: $0.total)
    }
  }

  public enum Jump: String, Sendable {
    case draw
    case claim
    case win
  }

  public static func jumpIndexes(frames: [ReplayFrame], kind: Jump) -> [Int] {
    frames.compactMap { frame in
      switch kind {
      case .draw:
        guard let step = frame.step else { return nil }
        if case .command(.draw) = step { return frame.index }
        return nil
      case .claim:
        guard frame.index > 0 else { return nil }
        let added = frame.state.events.dropFirst(frames[frame.index - 1].state.events.count)
        return added.contains { event in
          if case .claimed = event { return true }
          return false
        } ? frame.index : nil
      case .win:
        if case .endedWin = frame.state.phase { return frame.index }
        if case .declareWin = frame.step { return frame.index }
        return nil
      }
    }
  }

  private static func skippedWin(previous: GameState, step: ReplayStep, index: Int) -> ReplayNote? {
    let tile: Tile
    let method: WinMethod
    switch previous.phase {
    case let .awaitingResponses(_, discarded):
      tile = discarded
      method = .discard
    case let .awaitingRobKong(_, _, discarded):
      tile = discarded
      method = .robbingKong
    default:
      return nil
    }
    guard WinContextBuilder.legalScore(state: previous, seat: 0, tile: tile.kind, method: method) != nil
    else { return nil }
    guard case let .command(.resolveClaims(claims)) = step else { return nil }
    guard !claims.contains(where: { $0.seat == 0 && $0.type == .win }) else { return nil }
    return ReplayNote(frameIndex: index, mark: .skippedWin, text: "这里放过了一次可以和的牌。")
  }

  private static func missedKong(previous: GameState, step: ReplayStep, index: Int) -> ReplayNote? {
    guard case .awaitingDiscard(seat: 0) = previous.phase,
      !previous.concealedKongKinds(seat: 0).isEmpty,
      case .command(.discard) = step
    else { return nil }
    return ReplayNote(frameIndex: index, mark: .missedKong, text: "出牌前有暗杠可以声明。")
  }
}
