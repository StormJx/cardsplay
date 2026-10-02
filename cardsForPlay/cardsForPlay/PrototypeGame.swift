import Foundation
import MahjongAI
import MahjongRules

struct RoundResult: Codable {
  let winner: Int?
  let discarder: Int?
  let score: ScoreResult?
  let deltas: [Int]

  var isDraw: Bool { winner == nil }
}
private struct PrototypeSnapshot: Codable {
  let game: GameState
  let cumulativeScores: [Int]
  let result: RoundResult?
  let aiDelay: Double
  let difficulty: AIDifficulty
}
enum HumanAction: Hashable, Identifiable {
  case win
  case chow([TileKind])
  case pung
  case exposedKong
  case concealedKong(TileKind)
  case addedKong(index: Int, kind: TileKind)
  case skip

  var id: String {
    switch self {
    case .win: return "win"
    case let .chow(run): return "chow-\(run.map(\.rawValue))"
    case .pung: return "pung"
    case .exposedKong: return "exposed-kong"
    case let .concealedKong(kind): return "concealed-kong-\(kind.rawValue)"
    case let .addedKong(index, _): return "added-kong-\(index)"
    case .skip: return "skip"
    }
  }

  var title: String {
    switch self {
    case .win: return "和"
    case let .chow(run): return "吃 \(run.map(\.displayName).joined())"
    case .pung: return "碰"
    case .exposedKong: return "杠"
    case let .concealedKong(kind): return "暗杠 \(kind.displayName)"
    case let .addedKong(_, kind): return "补杠 \(kind.displayName)"
    case .skip: return "跳过"
    }
  }
}
@MainActor
final class PrototypeGame: ObservableObject {
  static let playerNames = ["你（东）", "阿岚（南）", "静川（西）", "墨衡（北）"]

  @Published private(set) var game = GameState(seed: 0)
  @Published private(set) var cumulativeScores = [0, 0, 0, 0]
  @Published private(set) var result: RoundResult?
  @Published private(set) var actions: [HumanAction] = []
  @Published var selectedTile: Tile?
  @Published var isPaused = false
  @Published var showSettings = false
  @Published var aiDelay = 0.22
  @Published var selectedDifficulty = AIDifficulty.normal
  @Published var showGameSetup = true
  @Published private(set) var message = "正在开局…"
  @Published private(set) var aiDecisionLogs: [Int: AIDecisionLog] = [:]

  private var driveTask: Task<Void, Never>?

  init() {
    if ProcessInfo.processInfo.arguments.contains("-reset-prototype") {
      try? FileManager.default.removeItem(at: Self.snapshotURL)
    }
    if let snapshot = Self.loadSnapshot() {
      game = snapshot.game
      cumulativeScores = snapshot.cumulativeScores
      result = snapshot.result
      aiDelay = snapshot.aiDelay
      selectedDifficulty = snapshot.difficulty
      showGameSetup = false
      message = snapshot.result == nil ? "已恢复上次牌局" : "已恢复结算"
    } else {
      game = GameState(seed: Self.freshSeed())
    }
    if !showGameSetup { scheduleDrive() }
  }

  deinit {
    driveTask?.cancel()
  }

  func newGame() {
    driveTask?.cancel()
    result = nil
    actions = []
    selectedTile = nil
    isPaused = false
    showGameSetup = true
    message = "请选择电脑难度"
  }

  func startGame(difficulty: AIDifficulty) {
    driveTask?.cancel()
    selectedDifficulty = difficulty
    game = GameState(seed: Self.freshSeed())
    result = nil
    actions = []
    selectedTile = nil
    isPaused = false
    showGameSetup = false
    aiDecisionLogs = [:]
    message = "\(difficulty.displayName)难度开局，你是东家"
    persist()
    scheduleDrive()
  }

  var opponentProfiles: [OpponentProfile] {
    OpponentProfile.standardOpponents(difficulty: selectedDifficulty)
  }

  func opponentProfile(seat: Int) -> OpponentProfile {
    opponentProfiles.first { $0.seat == seat }!
  }

  func togglePause() {
    isPaused.toggle()
    message = isPaused ? "已暂停并保存" : "继续牌局"
    persist()
    if !isPaused { scheduleDrive() }
  }

  func saveForBackground() {
    persist()
  }

  func select(_ tile: Tile) {
    guard case .awaitingDiscard(seat: 0) = game.phase else { return }
    selectedTile = selectedTile == tile ? nil : tile
  }

  func discardSelected() {
    guard case .awaitingDiscard(seat: 0) = game.phase, let selectedTile else { return }
    do {
      try apply(.discard(seat: 0, tile: selectedTile))
      self.selectedTile = nil
      actions = []
      message = "你打出 \(selectedTile.kind.displayName)"
      scheduleDrive()
    } catch {
      message = "不能打出这张牌：\(error)"
    }
  }

  func perform(_ action: HumanAction) {
    guard !isPaused, result == nil else { return }
    do {
      switch action {
      case .win:
        try performHumanWin()
      case let .concealedKong(kind):
        try apply(.concealedKong(seat: 0, kind: kind))
        message = "你声明暗杠 \(kind.displayName)"
        actions = []
        scheduleDrive()
      case let .addedKong(index, kind):
        guard let tile = game.players[0].concealed.first(where: { $0.kind == kind }) else {
          return
        }
        try apply(.addedKong(seat: 0, meldIndex: index, tile: tile))
        message = "你声明补杠 \(kind.displayName)"
        actions = []
        scheduleDrive()
      case .chow, .pung, .exposedKong, .skip:
        try resolveHumanResponse(action)
      }
    } catch {
      message = "操作未完成：\(error)"
    }
  }

  private func scheduleDrive() {
    driveTask?.cancel()
    driveTask = Task { [weak self] in
      await self?.driveLoop()
    }
  }

  private func driveLoop() async {
    while !Task.isCancelled, !isPaused, result == nil {
      switch game.phase {
      case let .awaitingDraw(seat):
        if seat != 0 { await waitForAI() }
        do {
          try apply(.draw(seat: seat))
          if case .endedDraw = game.phase {
            finishDraw()
          } else {
            message = seat == 0 ? "你摸了一张牌" : "\(Self.playerNames[seat])摸牌"
          }
        } catch {
          message = "摸牌失败：\(error)"
          return
        }

      case let .awaitingDiscard(seat):
        if seat == 0 {
          prepareHumanTurn()
          return
        }
        await waitForAI()
        if finishSelfDrawIfLegal(seat: seat) { return }
        do {
          if let kind = game.concealedKongKinds(seat: seat).first {
            try apply(.concealedKong(seat: seat, kind: kind))
            message = "\(Self.playerNames[seat])暗杠 \(kind.displayName)"
            continue
          }
          if let index = game.addedKongIndices(seat: seat).first {
            let kind = game.players[seat].melds[index].kind
            let tile = game.players[seat].concealed.first { $0.kind == kind }!
            try apply(.addedKong(seat: seat, meldIndex: index, tile: tile))
            message = "\(Self.playerNames[seat])补杠 \(kind.displayName)"
            continue
          }
          let tile = aiDiscard(seat: seat)
          try apply(.discard(seat: seat, tile: tile))
          let explanation = aiDecisionLogs[seat]?.explanation ?? "选择合法出牌"
          message = "\(Self.playerNames[seat])打出 \(tile.kind.displayName) · \(explanation)"
        } catch {
          message = "电脑操作失败：\(error)"
          return
        }

      case let .awaitingResponses(discarder, tile):
        let humanActions = responseActions(discarder: discarder, tile: tile)
        if discarder != 0, !humanActions.isEmpty {
          actions = humanActions + [.skip]
          message = "请选择是否响应 \(tile.kind.displayName)"
          return
        }
        do {
          try resolveClaims(
            aiClaims(discarder: discarder, tile: tile, method: .discard),
            discarder: discarder,
            tile: tile,
            method: .discard
          )
        } catch {
          message = "响应失败：\(error)"
          return
        }

      case let .awaitingRobKong(declarer, _, tile):
        if declarer != 0, legalScore(seat: 0, tile: tile.kind, method: .robbingKong) != nil {
          actions = [.win, .skip]
          message = "可以抢杠和 \(tile.kind.displayName)"
          return
        }
        let claims = aiWinClaims(discarder: declarer, tile: tile, method: .robbingKong)
        do {
          try resolveClaims(
            claims, discarder: declarer, tile: tile, method: .robbingKong)
        } catch {
          message = "抢杠响应失败：\(error)"
          return
        }

      case .endedDraw:
        finishDraw()
        return
      case .endedWin:
        if result == nil { message = "牌局已结束" }
        return
      }
    }
  }

  private func prepareHumanTurn() {
    actions = []
    if selfDrawScore(seat: 0) != nil { actions.append(.win) }
    actions += game.concealedKongKinds(seat: 0).map(HumanAction.concealedKong)
    actions += game.addedKongIndices(seat: 0).map { index in
      .addedKong(index: index, kind: game.players[0].melds[index].kind)
    }
    message = actions.isEmpty ? "请选择一张牌打出" : "可以和/杠，或直接选择牌打出"
  }

  private func performHumanWin() throws {
    switch game.phase {
    case .awaitingDiscard(seat: 0):
      guard let score = selfDrawScore(seat: 0) else { return }
      _ = game.adjudicateWinDeclaration(seat: 0, context: selfDrawContext(seat: 0)!)
      finishWin(winner: 0, discarder: nil, score: score)

    case let .awaitingResponses(discarder, tile):
      guard legalScore(seat: 0, tile: tile.kind, method: .discard) != nil else { return }
      try resolveClaims(
        [Claim(seat: 0, type: .win)]
          + aiWinClaims(discarder: discarder, tile: tile, method: .discard),
        discarder: discarder,
        tile: tile,
        method: .discard
      )

    case let .awaitingRobKong(declarer, _, tile):
      guard legalScore(seat: 0, tile: tile.kind, method: .robbingKong) != nil else { return }
      try resolveClaims(
        [Claim(seat: 0, type: .win)]
          + aiWinClaims(discarder: declarer, tile: tile, method: .robbingKong),
        discarder: declarer,
        tile: tile,
        method: .robbingKong
      )
    default:
      return
    }
  }

  private func resolveHumanResponse(_ action: HumanAction) throws {
    switch game.phase {
    case let .awaitingResponses(discarder, tile):
      var claims = aiClaims(discarder: discarder, tile: tile, method: .discard)
      switch action {
      case let .chow(run):
        claims.append(Claim(seat: 0, type: .chow, chowTiles: run))
      case .pung:
        claims.append(Claim(seat: 0, type: .pung))
      case .exposedKong:
        claims.append(Claim(seat: 0, type: .exposedKong))
      case .skip:
        break
      default:
        return
      }
      actions = []
      try resolveClaims(
        claims, discarder: discarder, tile: tile, method: .discard)
      scheduleDrive()

    case let .awaitingRobKong(declarer, _, tile):
      guard action == .skip else { return }
      actions = []
      try resolveClaims(
        aiWinClaims(discarder: declarer, tile: tile, method: .robbingKong),
        discarder: declarer,
        tile: tile,
        method: .robbingKong
      )
      scheduleDrive()
    default:
      return
    }
  }

  private func responseActions(discarder: Int, tile: Tile) -> [HumanAction] {
    guard discarder != 0 else { return [] }
    var available: [HumanAction] = []
    if legalScore(seat: 0, tile: tile.kind, method: .discard) != nil {
      available.append(.win)
    }
    if game.canExposedKong(seat: 0, discard: tile.kind) {
      available.append(.exposedKong)
    }
    if game.canPung(seat: 0, discard: tile.kind) {
      available.append(.pung)
    }
    available += game.legalChows(seat: 0, discard: tile.kind, discarder: discarder)
      .map(HumanAction.chow)
    return available
  }

  private func aiClaims(discarder: Int, tile: Tile, method: WinMethod) -> [Claim] {
    let wins = aiWinClaims(discarder: discarder, tile: tile, method: method)
    if !wins.isEmpty { return wins }

    var claims: [Claim] = []
    for seat in 1..<4 where seat != discarder {
      let information = aiInformation(seat: seat)
      let profile = opponentProfile(seat: seat)
      let seed = aiDecisionSeed(seat: seat)
      if game.canExposedKong(seat: seat, discard: tile.kind),
        MahjongAIDecider.shouldClaim(
          .exposedKong,
          discardedTile: tile.kind,
          information: information,
          profile: profile,
          decisionSeed: seed)
      {
        claims.append(Claim(seat: seat, type: .exposedKong))
      } else if game.canPung(seat: seat, discard: tile.kind),
        MahjongAIDecider.shouldClaim(
          .pung,
          discardedTile: tile.kind,
          information: information,
          profile: profile,
          decisionSeed: seed)
      {
        claims.append(Claim(seat: seat, type: .pung))
      }
      if let run = game.legalChows(
        seat: seat, discard: tile.kind, discarder: discarder
      ).first,
        MahjongAIDecider.shouldClaim(
          .chow(run),
          discardedTile: tile.kind,
          information: information,
          profile: profile,
          decisionSeed: seed)
      {
        claims.append(Claim(seat: seat, type: .chow, chowTiles: run))
      }
    }
    return claims
  }

  private func aiWinClaims(discarder: Int, tile: Tile, method: WinMethod) -> [Claim] {
    (1..<4).compactMap { seat in
      guard seat != discarder,
        !game.players[seat].isWinSuspended,
        legalScore(seat: seat, tile: tile.kind, method: method) != nil
      else { return nil }
      return Claim(seat: seat, type: .win)
    }
  }

  private func resolveClaims(
    _ claims: [Claim],
    discarder: Int,
    tile: Tile,
    method: WinMethod
  ) throws {
    try apply(.resolveClaims(claims))
    if case let .endedWin(winner) = game.phase,
      let score = legalScore(seat: winner, tile: tile.kind, method: method)
    {
      finishWin(winner: winner, discarder: discarder, score: score)
    }
  }

  private func finishSelfDrawIfLegal(seat: Int) -> Bool {
    guard let context = selfDrawContext(seat: seat),
      let score = MCRScorer.score(context),
      score.isLegalWin
    else { return false }
    _ = game.adjudicateWinDeclaration(seat: seat, context: context)
    finishWin(winner: seat, discarder: nil, score: score)
    return true
  }

  private func selfDrawScore(seat: Int) -> ScoreResult? {
    guard let context = selfDrawContext(seat: seat),
      let score = MCRScorer.score(context),
      score.isLegalWin
    else { return nil }
    return score
  }

  private func selfDrawContext(seat: Int) -> WinContext? {
    let winningTile: TileKind
    if case let .drew(drawnSeat, tile) = game.events.last, drawnSeat == seat {
      winningTile = tile.kind
    } else if game.events.isEmpty, seat == 0, let tile = game.players[0].concealed.last {
      winningTile = tile.kind
    } else {
      return nil
    }
    let player = game.players[seat]
    return WinContext(
      concealedTiles: player.concealed.map(\.kind),
      melds: player.melds,
      winningTile: winningTile,
      method: selfDrawMethod(seat: seat),
      seatWind: Wind(rawValue: seat)!,
      roundWind: .east,
      flowerCount: player.flowers.count,
      isLastWallTile: game.wall.isEmpty
    )
  }

  private func selfDrawMethod(seat: Int) -> WinMethod {
    for event in game.events.dropLast().reversed() {
      switch event {
      case .exposedFlower:
        continue
      case let .declaredKong(kongSeat, _, _) where kongSeat == seat:
        return .kongReplacement
      case let .claimed(claimSeat, type, _)
      where
        claimSeat == seat && type == .exposedKong:
        return .kongReplacement
      default:
        return .selfDraw
      }
    }
    return .selfDraw
  }

  private func legalScore(seat: Int, tile: TileKind, method: WinMethod) -> ScoreResult? {
    let player = game.players[seat]
    let context = WinContext(
      concealedTiles: player.concealed.map(\.kind) + [tile],
      melds: player.melds,
      winningTile: tile,
      method: method,
      seatWind: Wind(rawValue: seat)!,
      roundWind: .east,
      flowerCount: player.flowers.count,
      isLastDiscard: game.wall.isEmpty
    )
    guard let score = MCRScorer.score(context), score.isLegalWin else { return nil }
    return score
  }

  private func aiDiscard(seat: Int) -> Tile {
    let decision = MahjongAIDecider.chooseDiscard(
      information: aiInformation(seat: seat),
      profile: opponentProfile(seat: seat),
      decisionSeed: aiDecisionSeed(seat: seat)
    )
    aiDecisionLogs[seat] = decision
    return game.players[seat].concealed
      .filter { $0.kind == decision.chosenTile }
      .sorted { $0.copy < $1.copy }
      .first!
  }

  private func aiInformation(seat: Int) -> AIInformationSet {
    AIInformationSet(
      seat: seat,
      ownTiles: game.players[seat].concealed.map(\.kind),
      ownMelds: game.players[seat].melds,
      discards: publicDiscards(),
      publicMelds: game.players.map { player in
        player.melds.filter(\.isExposed)
      },
      exposedFlowers: game.players.map { $0.flowers.map(\.kind) },
      wallRemaining: game.wall.remainingCount,
      scores: cumulativeScores,
      roundWind: .east,
      actionNumber: game.events.count
    )
  }

  private func publicDiscards() -> [[TileKind]] {
    var rivers = Array(repeating: [TileKind](), count: 4)
    var pendingSeat: Int?
    for event in game.events {
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

  private func aiDecisionSeed(seat: Int) -> UInt64 {
    UInt64(game.events.count &* 31 &+ seat &* 7 &+ selectedDifficultyIndex)
  }

  private var selectedDifficultyIndex: Int {
    AIDifficulty.allCases.firstIndex(of: selectedDifficulty) ?? 0
  }

  private func finishWin(winner: Int, discarder: Int?, score: ScoreResult) {
    let deltas =
      (try? Settlement.win(
        winner: winner, discarder: discarder, fan: score.totalPoints
      )) ?? [0, 0, 0, 0]
    cumulativeScores = zip(cumulativeScores, deltas).map(+)
    result = RoundResult(winner: winner, discarder: discarder, score: score, deltas: deltas)
    actions = []
    message = "\(Self.playerNames[winner])和牌"
    persist()
  }

  private func finishDraw() {
    result = RoundResult(winner: nil, discarder: nil, score: nil, deltas: [0, 0, 0, 0])
    actions = []
    message = "牌墙摸完，本局流局"
    persist()
  }

  private func apply(_ command: GameCommand) throws {
    try game.apply(command)
    persist()
  }

  private func waitForAI() async {
    let nanoseconds = UInt64(max(0.02, aiDelay) * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanoseconds)
  }

  private func persist() {
    let snapshot = PrototypeSnapshot(
      game: game,
      cumulativeScores: cumulativeScores,
      result: result,
      aiDelay: aiDelay,
      difficulty: selectedDifficulty
    )
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    let url = Self.snapshotURL
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try? data.write(to: url, options: .atomic)
  }

  private static func loadSnapshot() -> PrototypeSnapshot? {
    guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
    return try? JSONDecoder().decode(PrototypeSnapshot.self, from: data)
  }

  private static var snapshotURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("cardsForPlay", isDirectory: true)
      .appendingPathComponent("prototype-session.json")
  }

  private static func freshSeed() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1_000_000)
  }
}
extension TileKind {
  var displayName: String {
    if let suit, let rank {
      return "\(rank)\(["万", "筒", "条"][suit.rawValue])"
    }
    if let wind { return ["东", "南", "西", "北"][wind.rawValue] }
    if let dragon { return ["中", "发", "白"][dragon.rawValue] }
    return ["春", "夏", "秋", "冬", "梅", "兰", "竹", "菊"][flower!.rawValue]
  }
}
