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
  case fanPath
  case belowEight
}

public struct RuleReading: Equatable, Sendable {
  public let title: String
  public let version: String
  public let nonFlowerPoints: Int
  public let detail: String
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

/// A point in a saved hand where the player can discard a different tile and keep playing.
/// The original steps are not rewritten.
public struct ReplayBranch: Sendable {
  public let state: GameState
  public let prefixSteps: [ReplayStep]
  public let played: Tile?

  public var alternatives: [Tile] {
    state.players[0].concealed.filter { $0 != played }
  }
}

public enum ReplayError: Error, Equatable {
  case missingWinContext
  case rule(RuleViolation)
}

public enum HandReplay {
  public static func frames(
    seed: UInt64, steps: [ReplayStep], dealer: Int = 0, roundWind: Wind = .east
  ) throws -> [ReplayFrame] {
    var state = GameState(seed: seed, dealer: dealer)
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
        guard let context = WinContextBuilder.selfDraw(
          state: state, seat: seat, roundWind: roundWind,
          seatWind: EastRound.seatWind(seat: seat, dealer: dealer)
        ) else {
          throw ReplayError.missingWinContext
        }
        _ = state.adjudicateWinDeclaration(seat: seat, context: context)
      }
      frames.append(ReplayFrame(index: frames.count, state: state, step: step))
    }
    return frames
  }

  public static func state(seed: UInt64, steps: [ReplayStep], dealer: Int = 0) throws -> GameState {
    try frames(seed: seed, steps: steps, dealer: dealer).last!.state
  }

  public static func notes(frames: [ReplayFrame], dealer: Int = 0) -> [ReplayNote] {
    guard frames.count > 1 else { return [] }
    var notes: [ReplayNote] = []
    for index in 1..<frames.count {
      let previous = frames[index - 1].state
      let frame = frames[index]
      guard let step = frame.step else { continue }
      if let note = skippedWin(previous: previous, step: step, index: index, dealer: dealer) {
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
        if claims.contains(where: { $0.seat == 0 && $0.type != .win }) {
          notes.append(contentsOf: fanNotes(previous: previous, next: frame.state, index: index, dealer: dealer))
        }
      }
      if case .command(.discard(seat: 0, _)) = step {
        notes.append(contentsOf: fanNotes(previous: previous, next: frame.state, index: index, dealer: dealer))
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

  public static let checkpointMarks: Set<ReplayMark> = [.dealtIn, .skippedWin, .missedKong]

  /// Frames where autoplay should pause: a dealt-in discard, a passed win, or a missed concealed kong.
  public static func checkpointIndexes(notes: [ReplayNote]) -> [Int] {
    Array(Set(notes.compactMap { checkpointMarks.contains($0.mark) ? $0.frameIndex : nil })).sorted()
  }

  /// One autoplay tick. Playback stops on the last frame and, when requested, on a checkpoint.
  public static func advance(
    index: Int, frameCount: Int, stopAtChecks: Bool, checkpoints: [Int]
  ) -> (index: Int, playing: Bool) {
    let last = frameCount - 1
    guard frameCount > 0, index < last else { return (max(0, index), false) }
    let next = index + 1
    let stop = next == last || (stopAtChecks && checkpoints.contains(next))
    return (next, !stop)
  }

  public static func readings(record: HandRecord) -> (recorded: RuleReading, current: RuleReading) {
    let recorded = RuleReading(
      title: "按原规则重放",
      version: record.ruleVersion,
      nonFlowerPoints: record.nonFlowerPoints,
      detail: "按牌谱保存的规则 \(record.ruleVersion) 重放动作，记录的非花番是 \(record.nonFlowerPoints)。"
    )
    let same = record.ruleVersion == MCRRuleBook.version
    let current = RuleReading(
      title: "按当前规则重分析",
      version: MCRRuleBook.version,
      nonFlowerPoints: record.nonFlowerPoints,
      detail: same
        ? "当前规则仍是 \(MCRRuleBook.version)，和牌谱一致。向听、有效牌和预估番只用当时看得到的牌重算。"
        : "牌谱规则是 \(record.ruleVersion)，当前规则是 \(MCRRuleBook.version)。向听、有效牌和预估番按当前规则重算，不用最终牌序倒推。"
    )
    return (recorded, current)
  }

  public static func studyLine(state: GameState, scores: [Int], roundWind: Wind = .east) -> String {
    guard case .awaitingDiscard(seat: 0) = state.phase else { return "" }
    let concealed = state.players[0].concealed.map(\.kind)
    let melds = state.players[0].melds
    let studies = PracticeCoach.discardStudies(
      concealed: concealed,
      melds: melds,
      seatWind: EastRound.seatWind(seat: 0, dealer: 0),
      roundWind: roundWind,
      unseen: { PublicInfo.unseenCount(state: state, kind: $0) }
    )
    guard !studies.isEmpty else { return "" }
    let listed = studies.prefix(4).map { study in
      let base =
        "\(PracticeCoach.tileLabel(study.tile)) 向听\(study.shanten) 有效\(study.usefulTiles)"
      return study.shanten == 0 ? base + " 约\(study.estimatedFan)番" : base
    }.joined(separator: " · ")
    return listed + " · " + PracticeCoach.situationLine(scores: scores, seat: 0)
  }

  /// The current step, when it is your discard, or the step just after you discarded.
  public static func branch(frames: [ReplayFrame], index: Int) -> ReplayBranch? {
    guard frames.indices.contains(index) else { return nil }
    if case .awaitingDiscard(seat: 0) = frames[index].state.phase {
      return ReplayBranch(
        state: frames[index].state,
        prefixSteps: prefixSteps(frames: frames, through: index),
        played: nextOwnDiscard(frames: frames, after: index)
      )
    }
    if index > 0,
      case .command(.discard(let seat, let tile)) = frames[index].step,
      seat == 0,
      case .awaitingDiscard(seat: 0) = frames[index - 1].state.phase
    {
      return ReplayBranch(
        state: frames[index - 1].state,
        prefixSteps: prefixSteps(frames: frames, through: index - 1),
        played: tile
      )
    }
    return nil
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

  private static func prefixSteps(frames: [ReplayFrame], through index: Int) -> [ReplayStep] {
    guard index > 0 else { return [] }
    return frames[1...index].compactMap(\.step)
  }

  private static func nextOwnDiscard(frames: [ReplayFrame], after index: Int) -> Tile? {
    let next = index + 1
    guard frames.indices.contains(next),
      case .command(.discard(let seat, let tile)) = frames[next].step,
      seat == 0
    else { return nil }
    return tile
  }

  private static func fanNotes(
    previous: GameState, next: GameState, index: Int, dealer: Int
  ) -> [ReplayNote] {
    let beforeMelds = previous.players[0].melds
    let afterMelds = next.players[0].melds
    var notes: [ReplayNote] = []
    let blocked = PracticeCoach.newlyBlocked(before: beforeMelds, after: afterMelds)
    if !blocked.isEmpty {
      notes.append(
        ReplayNote(
          frameIndex: index, mark: .fanPath,
          text: "鸣牌改了番路，这些番已经打不到：\(blocked.joined(separator: "、"))。"))
    }
    let wind = EastRound.seatWind(seat: 0, dealer: dealer)
    let beforeFan = PracticeCoach.bestListedFan(
      concealed: previous.players[0].concealed.map(\.kind), melds: beforeMelds,
      seatWind: wind, roundWind: EastRound.roundWind)
    let afterFan = PracticeCoach.bestListedFan(
      concealed: next.players[0].concealed.map(\.kind), melds: afterMelds,
      seatWind: wind, roundWind: EastRound.roundWind)
    if PracticeCoach.droppedBelowEight(before: beforeFan, after: afterFan) {
      notes.append(
        ReplayNote(
          frameIndex: index, mark: .belowEight,
          text: "这一步之前非花番还能到 \(beforeFan)，现在不够 8 番。"))
    }
    return notes
  }

  private static func skippedWin(
    previous: GameState, step: ReplayStep, index: Int, dealer: Int
  ) -> ReplayNote? {
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
    guard WinContextBuilder.legalScore(
      state: previous, seat: 0, tile: tile.kind, method: method,
      roundWind: EastRound.roundWind, seatWind: EastRound.seatWind(seat: 0, dealer: dealer)
    ) != nil
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
