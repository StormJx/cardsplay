import Foundation
import MahjongAI
import MahjongProgress
import MahjongRules

struct RoundResult: Codable {
  let winner: Int?
  let discarder: Int?
  let score: ScoreResult?
  let deltas: [Int]

  var isDraw: Bool { winner == nil }
}

enum AppRoute: Equatable {
  case home
  case more
  case settings
  case table
  case career
  case stats
  case achievements
  case guides
  case replays
  case replay(UUID)
  case help
  case appearance
  case dice
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
  @Published var discardConfirm = false
  @Published private(set) var pendingDiscard: Tile?
  @Published var isPaused = false
  @Published var showSettings = false
  @Published var aiDelay = 0.22
  @Published var selectedDifficulty = AIDifficulty.normal
  @Published var showGameSetup = false
  @Published private(set) var message = "选择要玩的内容"
  @Published private(set) var aiDecisionLogs: [Int: AIDecisionLog] = [:]
  @Published private(set) var library = ProgressLibrary()
  @Published var route: AppRoute = .home
  @Published var highlightedFan: Int?
  @Published private(set) var careerNote: String?
  @Published private(set) var lastRecordID: UUID?
  @Published private(set) var repeatDealer = false

  private var driveTask: Task<Void, Never>?
  private var handSeed: UInt64 = 0
  private var steps: [ReplayStep] = []
  private var canReplay = true
  private var sessionActive = false
  private var pendingMode = PlayMode.quick
  private var lastMethod: WinMethod?
  private var roundHandIndex = 0
  private var roundInitialDealer = 0
  private var roundDealer: Int?
  private var forkDealer: Int?
  private var forkWind: Wind?
  private var fortune = FortuneTrack()
  var mode = PlayMode.quick
  var careerLevelID: String?
  var practiceHints = false
  var lessonActive = false
  @Published var tableNotice: String?

  init() {
    if ProcessInfo.processInfo.arguments.contains("-reset-prototype") {
      try? FileManager.default.removeItem(at: Self.storageDirectory)
    }
    library = ProgressArchive.load(from: Self.storageDirectory)
    if library.session == nil, let legacy = Self.loadLegacy() {
      library.session = Self.migrated(legacy)
      try? ProgressArchive.save(library, to: Self.storageDirectory)
      try? FileManager.default.removeItem(at: Self.legacySnapshotURL)
    }
    if let session = library.session {
      restore(session)
      if tracksWinds && (result == nil || !isLastScheduledHand) {
        message = usesFullWinds ? "可以继续这十六盘" : "可以继续这一圈"
      } else {
        message = session.winner == nil && !session.drawn ? "可以继续上次牌局" : "上次牌局已经结束"
      }
    } else {
      game = GameState(seed: 0)
    }
    repeatDealer = library.repeatDealer ?? false
    fortune = library.fortune ?? FortuneTrack()
    route = .home
  }

  deinit {
    driveTask?.cancel()
  }

  var setupTitle: String {
    switch pendingMode {
    case .practice: return "练习一盘"
    case .career: return "生涯关卡"
    case .full: return "完整对局"
    case .round: return "东风圈"
    case .quick: return "选择电脑难度"
    }
  }

  var setupButtonTitle: String {
    switch pendingMode {
    case .practice: return "开始练习"
    case .round: return "开始一圈"
    case .full: return "开始十六盘"
    default: return "开始一盘"
    }
  }

  var setupNote: String? {
    switch pendingMode {
    case .round:
      if repeatDealer {
        return "连续四盘，圈风保持东。庄家和牌或流局时连庄，别家和牌则换下家。没有额外加赛，也没有庄家加分。"
      }
      return "连续四盘，圈风保持东。第一盘庄家由本圈种子决定，之后每盘交给下家；流局也轮转，没有庄家加分。"
    case .full:
      if repeatDealer {
        return "东南西北四圈，共 16 盘。庄家和牌或流局时连庄，别家和牌则换下家，每四盘换圈风。没有额外加赛，也没有庄家加分。"
      }
      return "东南西北四圈，共 16 盘。每盘结束后庄家交给下家，每四盘换圈风。流局也轮转，没有连庄加赛。"
    default:
      return nil
    }
  }

  var tracksWinds: Bool { rotatesDealer }
  var isEastRound: Bool { mode == .round || careerTable?.isEastRound == true }

  private var careerTable: CareerTable? {
    guard mode == .career, let careerLevelID, let level = CareerCatalog.level(id: careerLevelID) else {
      return nil
    }
    return level.table
  }

  private var rotatesDealer: Bool {
    switch mode {
    case .round, .full:
      return true
    case .career:
      return careerTable?.rotates == true
    default:
      return false
    }
  }

  private var usesFullWinds: Bool {
    if mode == .full { return true }
    if case .fullMatch = careerTable { return true }
    return false
  }

  var roundCanContinue: Bool {
    tracksWinds && result != nil && !isLastScheduledHand
  }

  var roundComplete: Bool {
    tracksWinds && result != nil && isLastScheduledHand
  }

  private var isLastScheduledHand: Bool {
    if usesFullWinds { return FullMatch.isFinalHand(roundHandIndex) }
    if mode == .round || careerTable?.isEastRound == true {
      return EastRound.isFinalHand(roundHandIndex)
    }
    return true
  }

  var currentRoundWind: Wind {
    if let forkWind { return forkWind }
    if usesFullWinds { return FullMatch.roundWind(handIndex: roundHandIndex) }
    return .east
  }

  var dealerSeat: Int {
    if let forkDealer { return forkDealer }
    if rotatesDealer {
      if let roundDealer { return roundDealer }
      return FullMatch.dealer(handIndex: roundHandIndex, initialDealer: roundInitialDealer)
    }
    if case .single(let dealer) = careerTable { return dealer }
    return 0
  }

  func seatWind(_ seat: Int) -> Wind {
    EastRound.seatWind(seat: seat, dealer: dealerSeat)
  }

  func windTag(_ seat: Int) -> String {
    let wind = ["东", "南", "西", "北"][seatWind(seat).rawValue]
    return seat == dealerSeat && tracksWinds ? "\(wind)庄" : wind
  }

  func playerLabel(_ seat: Int) -> String {
    guard tracksWinds || dealerSeat != 0 || forkDealer != nil else { return Self.playerNames[seat] }
    let base = ["你", "阿岚", "静川", "墨衡"][seat]
    return "\(base)（\(windTag(seat))）"
  }

  var yourWindLabel: String {
    tracksWinds || dealerSeat != 0 || forkDealer != nil ? "你：\(windTag(0))" : "你：东"
  }

  var matchRankLine: String {
    let ranks = FullMatch.ranks(cumulativeScores)
    return (0..<4).map { "\(playerLabel($0))第\(ranks[$0])" }.joined(separator: " ")
  }

  var cumulativeLine: String {
    (0..<4).map { seat in
      let score = cumulativeScores[seat]
      return "\(playerLabel(seat)) \(score >= 0 ? "+" : "")\(score)"
    }.joined(separator: "　")
  }

  var primaryResultButton: String {
    if roundCanContinue { return "下一盘" }
    if offersNextLevel { return "下一关" }
    if careerLevelID != nil { return "重试本关" }
    if mode == .full { return "再来十六盘" }
    if mode == .round { return "再来一圈" }
    return "再来一局"
  }

  var offersNextLevel: Bool {
    guard result != nil, !roundCanContinue, let careerLevelID else { return false }
    let passed = (library.career.bestStars[careerLevelID] ?? 0) >= 1
    return passed && CareerCatalog.nextPlayable(after: careerLevelID) != nil
  }

  var careerCornerLines: [String] {
    guard mode == .career, !showGameSetup, let careerLevelID,
      let level = CareerCatalog.level(id: careerLevelID)
    else { return [] }
    return [level.star1, level.star2, level.star3].enumerated().map { offset, condition in
      "第\(offset + 1)星 \(condition.title)"
    }
  }

  var settlementStarLines: [CareerStarLine] {
    guard let level = settledCareerLevel, let outcome = settledCareerOutcome() else { return [] }
    return CareerGrader.starLines(for: level, outcome: outcome)
  }

  var settlementMissing: String? {
    guard let level = settledCareerLevel, let outcome = settledCareerOutcome() else { return nil }
    return CareerGrader.missingSummary(for: level, outcome: outcome)
  }

  var tableLabel: String {
    if let careerLevelID, let level = CareerCatalog.level(id: careerLevelID) {
      switch level.table {
      case .single:
        return "\(level.chapter)-\(level.index) \(level.title)"
      case .eastRound:
        return "\(level.title) · 东风圈 \(roundHandIndex + 1)/4"
      case .fullMatch:
        let wind = ["东", "南", "西", "北"][currentRoundWind.rawValue]
        return "\(level.title) · \(wind)风圈 \(FullMatch.handInRound(handIndex: roundHandIndex))/4 · \(roundHandIndex + 1)/16"
      }
    }
    if mode == .round { return "东风圈 \(roundHandIndex + 1)/4" }
    if mode == .full {
      let wind = ["东", "南", "西", "北"][currentRoundWind.rawValue]
      return "\(wind)风圈 \(FullMatch.handInRound(handIndex: roundHandIndex))/4 · \(roundHandIndex + 1)/16"
    }
    return mode.displayName
  }

  private var practiceBriefCache: (key: String, brief: PracticeBrief)?

  var showsTableHints: Bool {
    mode.showsWaitsAndFan && result == nil && !showGameSetup
  }

  var practiceBrief: PracticeBrief? {
    guard showsTableHints else { return nil }
    let selected = selectedTile?.kind.rawValue ?? -1
    let drawn = freshDraw?.rawValue ?? -1
    let key = "\(game.events.count)#\(game.phase)#\(selected)#\(drawn)#\(game.players[0].concealed.map(\.kind.rawValue))#\(practiceSwitches)#\(mode.rawValue)"
    if let practiceBriefCache, practiceBriefCache.key == key { return practiceBriefCache.brief }
    let player = game.players[0]
    let brief = PracticeCoach.brief(
      concealed: player.concealed.map(\.kind),
      melds: player.melds,
      discarding: game.phase == .awaitingDiscard(seat: 0),
      selected: selectedTile?.kind,
      discards: PublicInfo.rivers(events: game.events),
      exposedMelds: game.players.map { $0.melds.filter(\.isExposed) },
      scores: cumulativeScores,
      seat: 0,
      seatWind: seatWind(0),
      roundWind: currentRoundWind,
      unseen: { PublicInfo.unseenCount(state: self.game, kind: $0) },
      switches: practiceSwitches,
      drawn: freshDraw,
      scope: mode == .practice ? .full : .waitsAndFan
    )
    practiceBriefCache = (key, brief)
    return brief
  }

  var lastRecordCanReplay: Bool {
    guard let lastRecordID else { return false }
    return library.records.first { $0.id == lastRecordID }?.canReplay == true
  }

  func beginSetup(mode: PlayMode) {
    driveTask?.cancel()
    pendingMode = mode
    showGameSetup = true
    route = .table
    message = "请选择电脑难度"
  }

  func beginCareer(_ level: CareerLevel) {
    guard level.playable else { return }
    pendingMode = .career
    careerLevelID = level.id
    practiceHints = false
    selectedDifficulty = level.difficulty
    if let puzzle = level.puzzle {
      startPuzzle(puzzle, difficulty: level.difficulty)
      return
    }
    startGame(difficulty: level.difficulty)
  }

  func continueGame() {
    guard let session = library.session else { return }
    restore(session)
    showGameSetup = false
    route = .table
    message = result == nil ? "已恢复上次牌局" : "已恢复结算"
    if result == nil, !isPaused { scheduleDrive() }
  }

  func returnHome() {
    driveTask?.cancel()
    isPaused = false
    if showGameSetup {
      showGameSetup = false
      if let session = library.session {
        restore(session)
      }
    } else {
      persist()
    }
    route = .home
  }

  func openReplay(_ id: UUID) {
    highlightedFan = nil
    route = .replay(id)
  }

  func deleteRecord(_ id: UUID) {
    library.records.removeAll { $0.id == id }
    if lastRecordID == id { lastRecordID = nil }
    persist()
  }

  func updateAudio(_ audio: AudioSettings) {
    library.audio = audio
    TableSound.shared.sync(audio, calm: musicIsCalm)
    persist()
  }

  func updateAudioVolume(_ keyPath: WritableKeyPath<AudioSettings, Double>, _ value: Double) {
    var audio = library.audio
    audio[keyPath: keyPath] = value
    updateAudio(audio)
  }

  func newGame() {
    if mode == .career, let careerLevelID, let level = CareerCatalog.level(id: careerLevelID) {
      beginCareer(level)
      return
    }
    driveTask?.cancel()
    showGameSetup = true
    if mode == .practice {
      pendingMode = .practice
    } else if mode != .round, mode != .full {
      pendingMode = .quick
    }
    message = "请选择电脑难度"
  }

  func advanceResult() {
    if roundCanContinue {
      startNextHand()
      return
    }
    if offersNextLevel, let careerLevelID,
      let next = CareerCatalog.nextPlayable(after: careerLevelID)
    {
      beginCareer(next)
      return
    }
    newGame()
  }

  func retryCareerLevel() {
    newGame()
  }

  func startNextHand() {
    guard tracksWinds, !isLastScheduledHand else { return }
    let continuation: EastRound.Continuation
    if let winner = result?.winner, result?.isDraw != true {
      continuation = .win(winner)
    } else {
      continuation = .draw
    }
    roundDealer = EastRound.nextDealer(
      current: dealerSeat, continuation: continuation, repeats: repeatDealer)
    driveTask?.cancel()
    roundHandIndex += 1
    handSeed = Self.freshSeed()
    game = GameState(seed: handSeed, dealer: dealerSeat)
    steps = []
    canReplay = true
    result = nil
    lastMethod = nil
    actions = []
    clearHandSelection()
    isPaused = false
    showGameSetup = false
    aiDecisionLogs = [:]
    careerNote = nil
    message = openingMessage
    applyOpeningFortune()
    persist()
    scheduleDrive()
  }

  func startGame(difficulty: AIDifficulty) {
    driveTask?.cancel()
    clearFork()
    lessonActive = false
    puzzleMissedFlag = false
    tableNotice = nil
    selectedDifficulty = difficulty
    mode = pendingMode
    if mode != .career { careerLevelID = nil }
    practiceHints = mode == .practice
    handSeed = Self.freshSeed()
    roundHandIndex = 0
    if rotatesDealer {
      if let careerTable {
        roundInitialDealer = careerTable.initialDealer
      } else {
        roundInitialDealer = Int(handSeed % 4)
      }
      roundDealer = roundInitialDealer
    } else {
      roundInitialDealer = 0
      roundDealer = nil
    }
    game = GameState(seed: handSeed, dealer: dealerSeat)
    steps = []
    canReplay = true
    result = nil
    lastMethod = nil
    careerNote = nil
    lastRecordID = nil
    actions = []
    clearHandSelection()
    isPaused = false
    showGameSetup = false
    sessionActive = true
    aiDecisionLogs = [:]
    cumulativeScores = [0, 0, 0, 0]
    message = rotatesDealer
      ? openingMessage
      : (dealerSeat == 0
        ? "\(difficulty.displayName)难度开局，你是东家"
        : "\(difficulty.displayName)难度开局，你是\(windTag(0))")
    if mode == .practice {
      finishFortuneGame()
    } else {
      beginFortuneGame()
    }
    TableSound.shared.sync(library.audio, calm: musicIsCalm)
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
    guard !isPaused, result == nil, !discardConfirm else { return }
    guard case .awaitingDiscard(seat: 0) = game.phase else { return }
    guard game.players[0].concealed.contains(tile) else { return }
    if selectedTile == tile {
      if actions.contains(.win) {
        pendingDiscard = tile
        discardConfirm = true
      } else {
        discard(tile)
      }
    } else {
      selectedTile = tile
    }
  }

  func discardSelected() {
    guard let selectedTile else { return }
    if actions.contains(.win), case .awaitingDiscard(seat: 0) = game.phase {
      pendingDiscard = selectedTile
      discardConfirm = true
      return
    }
    discard(selectedTile)
  }

  func confirmPendingDiscard() {
    guard let tile = pendingDiscard else { return }
    pendingDiscard = nil
    discardConfirm = false
    discard(tile)
  }

  func takeWinInstead() {
    pendingDiscard = nil
    discardConfirm = false
    perform(.win)
  }

  func cancelPendingDiscard() {
    pendingDiscard = nil
    discardConfirm = false
  }

  private func discard(_ tile: Tile) {
    guard case .awaitingDiscard(seat: 0) = game.phase else { return }
    do {
      try apply(.discard(seat: 0, tile: tile))
      clearHandSelection()
      actions = []
      if endPuzzleIfDiscarded() { return }
      message = lessonActive ? TableLesson.prompt(state: game) : "你打出 \(tile.kind.displayName)"
      scheduleDrive()
    } catch {
      message = "不能打出这张牌：\(error)"
    }
  }

  private func endPuzzleIfDiscarded() -> Bool {
    guard let puzzle = activePuzzle, CareerDeals.endsOnDiscard(puzzle) else { return false }
    puzzleMissedFlag = true
    let deltas = [0, 0, 0, 0]
    lastMethod = nil
    result = RoundResult(winner: nil, discarder: nil, score: nil, deltas: deltas)
    actions = []
    message = "这手未达成"
    archiveFinished(
      winner: nil, discarder: nil, score: nil, method: nil, deltas: deltas, drawn: true)
    persist()
    return true
  }

  private var activePuzzle: CareerPuzzle? {
    guard mode == .career, let careerLevelID else { return nil }
    return CareerCatalog.level(id: careerLevelID)?.puzzle
  }

  var puzzleMissed: Bool {
    puzzleMissedFlag && result?.isDraw == true
  }

  private var puzzleMissedFlag = false

  private func clearHandSelection() {
    selectedTile = nil
    pendingDiscard = nil
    discardConfirm = false
  }

  func perform(_ action: HumanAction) {
    guard !isPaused, result == nil else { return }
    do {
      switch action {
      case .win:
        try performHumanWin()
      case let .concealedKong(kind):
        try apply(.concealedKong(seat: 0, kind: kind))
        clearHandSelection()
        message = "你声明暗杠 \(kind.displayName)"
        actions = []
        scheduleDrive()
      case let .addedKong(index, kind):
        guard let tile = game.players[0].concealed.first(where: { $0.kind == kind }) else {
          return
        }
        try apply(.addedKong(seat: 0, meldIndex: index, tile: tile))
        clearHandSelection()
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
            message = seat == 0 ? "你摸了一张牌" : "\(playerLabel(seat))摸牌"
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
        if !lessonActive, finishSelfDrawIfLegal(seat: seat) { return }
        do {
          if lessonActive {
            let count = discardCount(seat)
            guard let kind = TableLesson.scriptedDiscard(
              seat: seat,
              hand: game.players[seat].concealed.map(\.kind),
              discardsSoFar: count
            ),
              let tile = game.players[seat].concealed.first(where: { $0.kind == kind })
            else {
              message = "固定牌打不下去"
              return
            }
            try apply(.discard(seat: seat, tile: tile))
            message = "\(playerLabel(seat))打出 \(tile.kind.displayName)"
            continue
          }
          let information = aiInformation(seat: seat)
          if let kind = game.concealedKongKinds(seat: seat).first(where: { kind in
            MahjongAIDecider.shouldDeclareKong(kind: kind, removing: 4, information: information)
          }) {
            try apply(.concealedKong(seat: seat, kind: kind))
            message = "\(playerLabel(seat))暗杠 \(kind.displayName)"
            continue
          }
          if let index = game.addedKongIndices(seat: seat).first(where: { index in
            let kind = game.players[seat].melds[index].kind
            return MahjongAIDecider.shouldDeclareKong(
              kind: kind, removing: 1, information: information)
          }) {
            let kind = game.players[seat].melds[index].kind
            let tile = game.players[seat].concealed.first { $0.kind == kind }!
            try apply(.addedKong(seat: seat, meldIndex: index, tile: tile))
            message = "\(playerLabel(seat))补杠 \(kind.displayName)"
            continue
          }
          let tile = aiDiscard(seat: seat)
          try apply(.discard(seat: seat, tile: tile))
          let explanation = aiDecisionLogs[seat]?.explanation ?? "选择合法出牌"
          message = "\(playerLabel(seat))打出 \(tile.kind.displayName) · \(explanation)"
        } catch {
          message = "电脑操作失败：\(error)"
          return
        }

      case let .awaitingResponses(discarder, tile):
        let humanActions = responseActions(discarder: discarder, tile: tile)
        if discarder != 0, !humanActions.isEmpty {
          actions = humanActions + [.skip]
          message = lessonActive
            ? TableLesson.prompt(state: game)
            : "请选择是否响应 \(tile.kind.displayName)"
          return
        }
        if lessonActive {
          do {
            try resolveClaims([], discarder: discarder, tile: tile, method: .discard)
          } catch {
            message = "响应失败：\(error)"
            return
          }
          continue
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
    if lessonActive {
      message = TableLesson.prompt(state: game)
      return
    }
    if actions.contains(.win) {
      message = "这手可以和。再点已选中的牌会先确认"
    } else if actions.isEmpty {
      message = "点一下选中，再点一次打出"
    } else {
      message = "可以杠，或点一下选中再点一次打出"
    }
  }

  private func performHumanWin() throws {
    switch game.phase {
    case .awaitingDiscard(seat: 0):
      guard let context = selfDrawContext(seat: 0), let score = selfDrawScore(seat: 0) else {
        return
      }
      steps.append(.declareWin(seat: 0))
      _ = game.adjudicateWinDeclaration(seat: 0, context: context)
      finishWin(winner: 0, discarder: nil, score: score, method: context.method)

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
      let passedWin = actions.contains(.win) && action != .win
      actions = []
      clearHandSelection()
      try resolveClaims(
        claims, discarder: discarder, tile: tile, method: .discard)
      if passedWin, result == nil {
        tableNotice = "这张可以和，你放过了。"
      }
      if lessonActive, result == nil {
        message = TableLesson.prompt(state: game)
      }
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
    if lessonActive { return [] }
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
      if let run = MahjongAIDecider.chooseChow(
        options: game.legalChows(seat: seat, discard: tile.kind, discarder: discarder),
        discardedTile: tile.kind,
        information: information,
        profile: profile,
        decisionSeed: seed
      ) {
        claims.append(Claim(seat: seat, type: .chow, chowTiles: run))
      }
    }
    return claims
  }

  private func aiWinClaims(discarder: Int, tile: Tile, method: WinMethod) -> [Claim] {
    if lessonActive { return [] }
    return (1..<4).compactMap { seat in
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
      finishWin(winner: winner, discarder: discarder, score: score, method: method)
    }
  }

  private func finishSelfDrawIfLegal(seat: Int) -> Bool {
    guard let context = selfDrawContext(seat: seat),
      let score = MCRScorer.score(context),
      score.isLegalWin
    else { return false }
    steps.append(.declareWin(seat: seat))
    _ = game.adjudicateWinDeclaration(seat: seat, context: context)
    finishWin(winner: seat, discarder: nil, score: score, method: context.method)
    return true
  }

  private func selfDrawScore(seat: Int) -> ScoreResult? {
    WinContextBuilder.selfDrawScore(
      state: game, seat: seat, roundWind: currentRoundWind, seatWind: seatWind(seat))
  }

  private func selfDrawContext(seat: Int) -> WinContext? {
    WinContextBuilder.selfDraw(
      state: game, seat: seat, roundWind: currentRoundWind, seatWind: seatWind(seat))
  }

  private func legalScore(seat: Int, tile: TileKind, method: WinMethod) -> ScoreResult? {
    WinContextBuilder.legalScore(
      state: game, seat: seat, tile: tile, method: method, roundWind: currentRoundWind,
      seatWind: seatWind(seat))
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
      roundWind: currentRoundWind,
      actionNumber: game.events.count
    )
  }

  private func publicDiscards() -> [[TileKind]] {
    PublicInfo.rivers(events: game.events)
  }

  private func aiDecisionSeed(seat: Int) -> UInt64 {
    UInt64(game.events.count &* 31 &+ seat &* 7 &+ selectedDifficultyIndex)
  }

  private var selectedDifficultyIndex: Int {
    AIDifficulty.allCases.firstIndex(of: selectedDifficulty) ?? 0
  }

  private func finishWin(winner: Int, discarder: Int?, score: ScoreResult, method: WinMethod) {
    let deltas =
      (try? Settlement.win(
        winner: winner, discarder: discarder, fan: score.totalPoints
      )) ?? [0, 0, 0, 0]
    cumulativeScores = EastRound.accumulate(cumulativeScores, deltas)
    lastMethod = method
    result = RoundResult(winner: winner, discarder: discarder, score: score, deltas: deltas)
    actions = []
    message = "\(playerLabel(winner))和牌"
    var spoken = "和"
    if winner == 0, library.announceFans == true,
      let fan = score.awards.first(where: { $0.fan != .flower })?.fan.name
    {
      spoken = "和，\(fan)"
    }
    TableSound.shared.speak(spoken, settings: library.audio)
    if lessonActive {
      lessonActive = false
      library.sawGuide = true
    }
    closeFortuneIfMatchOver()
    archiveFinished(
      winner: winner, discarder: discarder, score: score, method: method, deltas: deltas,
      drawn: false)
    persist()
  }

  private func finishDraw() {
    let deltas = [0, 0, 0, 0]
    lastMethod = nil
    result = RoundResult(winner: nil, discarder: nil, score: nil, deltas: deltas)
    actions = []
    message = "牌墙摸完，本局流局"
    closeFortuneIfMatchOver()
    archiveFinished(
      winner: nil, discarder: nil, score: nil, method: nil, deltas: deltas, drawn: true)
    persist()
  }

  private func archiveFinished(
    winner: Int?,
    discarder: Int?,
    score: ScoreResult?,
    method: WinMethod?,
    deltas: [Int],
    drawn: Bool
  ) {
    let counts = HandFacts.counts(events: game.events)
    let exposed = game.players[0].melds.filter(\.isExposed).count
    var replayable = canReplay
    if replayable {
      replayable = (try? HandReplay.state(seed: handSeed, steps: steps, dealer: dealerSeat)) != nil
    }
    canReplay = replayable
    let record = HandRecord(
      mode: mode,
      seed: handSeed,
      difficulty: selectedDifficulty,
      steps: steps,
      canReplay: replayable,
      winner: winner,
      discarder: discarder,
      winMethod: method,
      fanPoints: score?.totalPoints ?? 0,
      nonFlowerPoints: score?.nonFlowerPoints ?? 0,
      awardFans: score?.awards.map(\.fan.rawValue) ?? [],
      deltas: deltas,
      chowCount: counts.chows,
      pungCount: counts.pungs,
      kongCount: counts.kongs,
      concealedKongCount: counts.concealedKongs,
      humanExposedMelds: exposed,
      careerLevelID: careerLevelID,
      dealerSeat: dealerSeat,
      prevailingWind: currentRoundWind.rawValue
    )
    library.append(record)
    lastRecordID = record.id
    if mode == .career, let careerLevelID, let level = CareerCatalog.level(id: careerLevelID),
      let outcome = settledCareerOutcome()
    {
      let earned = CareerGrader.stars(for: level, outcome: outcome)
      careerNote = CareerGrader.missingSummary(for: level, outcome: outcome)
      library.career.bestStars[careerLevelID] = max(
        library.career.bestStars[careerLevelID] ?? 0, earned)
    } else {
      careerNote = nil
    }
  }

  private func apply(_ command: GameCommand) throws {
    try game.apply(command)
    if case .draw(let seat) = command, seat == 0 {
      offerDrawFortune()
    } else if case .concealedKong(let seat, _) = command, seat == 0 {
      offerDrawFortune()
    }
    steps.append(.command(command))
    if case .discard = command {
      TableSound.shared.tap(library.audio)
    }
    if case .resolveClaims = command {
      TableSound.shared.claim(library.audio)
    }
    speakLatestAction()
    persist()
  }

  private func speakLatestAction() {
    guard let event = game.events.last else { return }
    switch event {
    case let .claimed(_, type, _):
      switch type {
      case .chow: TableSound.shared.speak("吃", settings: library.audio)
      case .pung: TableSound.shared.speak("碰", settings: library.audio)
      case .exposedKong: TableSound.shared.speak("杠", settings: library.audio)
      case .win: break
      }
    case .declaredKong:
      TableSound.shared.speak("杠", settings: library.audio)
    default:
      break
    }
  }

  private var openingMessage: String {
    let starter = "\(playerLabel(dealerSeat))先出牌"
    if usesFullWinds {
      let wind = ["东", "南", "西", "北"][currentRoundWind.rawValue]
      return "\(wind)风圈第 \(FullMatch.handInRound(handIndex: roundHandIndex)) 盘，共 16 盘，\(starter)"
    }
    if mode == .round || careerTable?.isEastRound == true {
      return "东风圈第 \(roundHandIndex + 1) 盘，\(starter)"
    }
    return starter
  }

  var fortuneStatusLine: String? { fortune.remainingLine }
  var diceCount: Int { fortune.diceCount }
  var diceFaces: [Int] { fortune.faces }
  var diceLuckLine: String { fortune.luckLine }
  var diceTotal: Int { fortune.faces.reduce(0, +) }

  func changeDiceCount(by delta: Int) {
    var track = fortune
    let next = track.diceCount + delta
    track.diceCount = min(DailyDice.maximumCount, max(DailyDice.minimumCount, next))
    storeFortune(track)
  }

  func rollDice() {
    var track = fortune
    var rng = SystemRandomNumberGenerator()
    track.roll(faces: DailyDice.faces(count: track.diceCount, random: &rng))
    storeFortune(track)
  }

  private func beginFortuneGame() {
    var track = fortune
    _ = track.beginGame()
    storeFortune(track)
    applyOpeningFortune()
  }

  private func finishFortuneGame() {
    var track = fortune
    track.finishGame()
    storeFortune(track)
  }

  private func closeFortuneIfMatchOver() {
    guard !tracksWinds || isLastScheduledHand else { return }
    finishFortuneGame()
  }

  private func applyOpeningFortune() {
    guard fortune.openingHelp, mode != .practice else { return }
    let hand = game.players[0].concealed
    let upcoming = game.wall.upcomingTiles(limit: DailyDice.openingLookahead)
    guard let choice = FortuneAid.openingPairExchange(
      hand: hand.map(\.kind),
      upcoming: upcoming.map(\.kind)
    ),
      let handTile = hand.first(where: { $0.kind == choice.remove }),
      game.exchangeOpening(seat: 0, handTile: handTile, upcomingOffset: choice.offset)
    else { return }
    canReplay = false
  }

  private func offerDrawFortune() {
    guard fortune.drawHelp, mode != .practice, !lessonActive else { return }
    guard let drawn = game.events.last.flatMap({ event -> Tile? in
      if case .drew(let seat, let tile) = event, seat == 0 { return tile }
      return nil
    }) else { return }
    let upcoming = game.wall.upcomingTiles(limit: DailyDice.drawLookahead)
    guard let offset = FortuneAid.improvingDrawOffset(
      concealed: game.players[0].concealed.map(\.kind),
      meldCount: game.players[0].melds.count,
      drawn: drawn.kind,
      upcoming: upcoming.map(\.kind)
    ), game.replaceLatestDraw(seat: 0, upcomingOffset: offset) else { return }
    canReplay = false
  }

  private func storeFortune(_ track: FortuneTrack) {
    fortune = track
    var saved = library
    saved.fortune = track
    library = saved
    persist()
  }

  func setRepeatDealer(_ enabled: Bool) {
    repeatDealer = enabled
    var saved = library
    saved.repeatDealer = enabled
    library = saved
    persist()
  }

  func continueFromReplay(
    seed: UInt64,
    dealer: Int,
    roundWind: Wind,
    difficulty: AIDifficulty,
    prefix: [ReplayStep],
    state: GameState,
    discard: Tile
  ) {
    guard case .awaitingDiscard(seat: 0) = state.phase,
      state.players[0].concealed.contains(discard)
    else { return }
    driveTask?.cancel()
    clearFork()
    selectedDifficulty = difficulty
    mode = .quick
    pendingMode = .quick
    careerLevelID = nil
    practiceHints = false
    handSeed = seed
    forkDealer = dealer
    forkWind = roundWind
    roundHandIndex = 0
    roundInitialDealer = 0
    roundDealer = nil
    game = state
    steps = prefix
    canReplay = true
    result = nil
    lastMethod = nil
    careerNote = nil
    lastRecordID = nil
    actions = []
    clearHandSelection()
    isPaused = false
    showGameSetup = false
    sessionActive = true
    aiDecisionLogs = [:]
    cumulativeScores = [0, 0, 0, 0]
    route = .table
    message = "从这张改打。原来的牌谱还在。"
    do {
      try apply(.discard(seat: 0, tile: discard))
    } catch {
      message = "这张牌不能从这里打出"
      return
    }
    TableSound.shared.sync(library.audio, calm: musicIsCalm)
    scheduleDrive()
  }

  private func clearFork() {
    forkDealer = nil
    forkWind = nil
  }

  private func startPuzzle(_ puzzle: CareerPuzzle, difficulty: AIDifficulty) {
    driveTask?.cancel()
    clearFork()
    roundDealer = nil
    selectedDifficulty = difficulty
    mode = .career
    practiceHints = false
    lessonActive = false
    puzzleMissedFlag = false
    roundHandIndex = 0
    roundInitialDealer = 0
    handSeed = 0
    game = CareerDeals.opening(puzzle)
    steps = []
    canReplay = false
    result = nil
    lastMethod = nil
    careerNote = nil
    lastRecordID = nil
    actions = []
    clearHandSelection()
    isPaused = false
    showGameSetup = false
    sessionActive = true
    route = .table
    aiDecisionLogs = [:]
    cumulativeScores = [0, 0, 0, 0]
    message = "固定残局。摸进的牌可以和，点「和」。"
    finishFortuneGame()
    TableSound.shared.sync(library.audio, calm: musicIsCalm)
    persist()
    scheduleDrive()
  }

  var practiceSwitches: PracticeSwitches {
    get { library.practice ?? PracticeSwitches() }
    set {
      library.practice = newValue
      practiceBriefCache = nil
      persist()
    }
  }

  var needsGuide: Bool { library.sawGuide != true }

  func completeGuide() {
    library.sawGuide = true
    persist()
  }

  func startTableLesson() {
    driveTask?.cancel()
    clearFork()
    selectedDifficulty = .beginner
    mode = .quick
    pendingMode = .quick
    careerLevelID = nil
    practiceHints = false
    lessonActive = true
    puzzleMissedFlag = false
    tableNotice = nil
    handSeed = 0
    roundHandIndex = 0
    roundInitialDealer = 0
    roundDealer = nil
    game = TableLesson.opening()
    steps = []
    canReplay = false
    result = nil
    lastMethod = nil
    careerNote = nil
    lastRecordID = nil
    actions = []
    clearHandSelection()
    isPaused = false
    showGameSetup = false
    sessionActive = true
    route = .table
    aiDecisionLogs = [:]
    cumulativeScores = [0, 0, 0, 0]
    message = TableLesson.prompt(state: game)
    finishFortuneGame()
    TableSound.shared.sync(library.audio, calm: musicIsCalm)
    persist()
    scheduleDrive()
  }

  func skipTableLesson() {
    lessonActive = false
    library.sawGuide = true
    persist()
    returnHome()
  }

  private var freshDraw: TileKind? {
    guard case .awaitingDiscard(let seat) = game.phase, seat == 0,
      case .drew(let drawSeat, let tile) = game.events.last, drawSeat == 0
    else { return nil }
    return tile.kind
  }

  private func discardCount(_ seat: Int) -> Int {
    game.events.reduce(0) { count, event in
      if case .discarded(let discardedSeat, _) = event, discardedSeat == seat {
        return count + 1
      }
      return count
    }
  }

  var musicIsCalm: Bool {
    (library.equippedMusic ?? CosmeticCatalog.starterMusic) == "music-calm"
  }

  var tableStyle: String { library.equippedTable ?? CosmeticCatalog.starterTable }
  var backStyle: String { library.equippedBack ?? CosmeticCatalog.starterBack }
  var characterStyle: String { library.equippedCharacter ?? CosmeticCatalog.starterCharacter }

  func equip(_ id: String) {
    guard CosmeticCatalog.isUnlocked(id, career: library.career) else { return }
    if id == "voice-fans" {
      library.announceFans = true
      persist()
      return
    }
    guard let item = CosmeticCatalog.items(career: library.career).first(where: { $0.id == id })
    else { return }
    switch item.kind {
    case .table: library.equippedTable = id
    case .back: library.equippedBack = id
    case .character: library.equippedCharacter = id
    case .music:
      library.equippedMusic = id
      TableSound.shared.sync(library.audio, calm: id == "music-calm")
    }
    persist()
  }

  func updateHaptics(_ enabled: Bool) {
    var audio = library.audio
    audio.haptics = enabled
    updateAudio(audio)
  }

  func setBackgroundMusic(_ enabled: Bool) {
    var audio = library.audio
    audio.backgroundMusic = enabled
    updateAudio(audio)
  }

  func setPracticeSwitch(_ key: WritableKeyPath<PracticeSwitches, Bool>, _ value: Bool) {
    var switches = practiceSwitches
    switches[keyPath: key] = value
    practiceSwitches = switches
  }

  private func waitForAI() async {
    let nanoseconds = UInt64(max(0.02, aiDelay) * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanoseconds)
  }

  private func persist() {
    if sessionActive { library.session = makeSession() }
    try? ProgressArchive.save(library, to: Self.storageDirectory)
  }

  private func makeSession() -> SavedSession {
    SavedSession(
      seed: handSeed,
      game: game,
      steps: steps,
      canReplay: canReplay,
      cumulativeScores: cumulativeScores,
      score: result?.score,
      winner: result?.winner,
      discarder: result?.discarder,
      winMethod: lastMethod,
      deltas: result?.deltas ?? cumulativeScores,
      drawn: result?.isDraw ?? false,
      paused: isPaused,
      aiDelay: aiDelay,
      difficulty: selectedDifficulty,
      mode: mode,
      careerLevelID: careerLevelID,
      practiceHints: practiceHints,
      lessonActive: lessonActive,
      puzzleMissed: puzzleMissedFlag,
      lastRecordID: lastRecordID,
      roundHandIndex: tracksWinds ? roundHandIndex : nil,
      roundInitialDealer: tracksWinds ? roundInitialDealer : nil,
      roundDealer: tracksWinds ? roundDealer : nil,
      forkDealer: forkDealer,
      forkWind: forkWind?.rawValue
    )
  }

  private func restore(_ session: SavedSession) {
    handSeed = session.seed
    game = session.game
    steps = session.steps
    canReplay = session.canReplay
    cumulativeScores = session.cumulativeScores
    lastMethod = session.winMethod
    if session.drawn || session.winner != nil {
      result = RoundResult(
        winner: session.winner,
        discarder: session.discarder,
        score: session.score,
        deltas: session.deltas
      )
    } else {
      result = nil
    }
    aiDelay = session.aiDelay
    selectedDifficulty = session.difficulty
    mode = session.mode
    pendingMode = session.mode
    roundHandIndex = session.roundHandIndex ?? 0
    roundInitialDealer = session.roundInitialDealer ?? 0
    roundDealer = session.roundDealer
    forkDealer = session.forkDealer
    forkWind = session.forkWind.flatMap(Wind.init(rawValue:))
    careerLevelID = session.careerLevelID
    practiceHints = session.practiceHints
    lessonActive = session.lessonActive ?? false
    puzzleMissedFlag = session.puzzleMissed ?? false
    lastRecordID = session.lastRecordID
    isPaused = session.paused
    sessionActive = true
    showGameSetup = false
    actions = []
    clearHandSelection()
  }

  private var settledCareerLevel: CareerLevel? {
    guard mode == .career, result != nil, let careerLevelID else { return nil }
    return CareerCatalog.level(id: careerLevelID)
  }

  private func settledCareerOutcome() -> HandOutcome? {
    guard let result else { return nil }
    let counts = HandFacts.counts(events: game.events)
    let exposed = game.players[0].melds.filter(\.isExposed).count
    return HandOutcome(
      humanWon: result.winner == 0,
      selfDrawn: result.winner == 0 && (lastMethod == .selfDraw || lastMethod == .kongReplacement),
      dealtIn: result.discarder == 0,
      drawn: result.isDraw,
      nonFlowerPoints: result.score?.nonFlowerPoints ?? 0,
      awards: result.score?.awards.map(\.fan) ?? [],
      exposedMelds: exposed,
      kongs: counts.kongs,
      concealedKongs: counts.concealedKongs
    )
  }

  private static func loadLegacy() -> PrototypeSnapshot? {
    guard let data = try? Data(contentsOf: legacySnapshotURL) else { return nil }
    return try? JSONDecoder().decode(PrototypeSnapshot.self, from: data)
  }

  private static func migrated(_ snapshot: PrototypeSnapshot) -> SavedSession {
    SavedSession(
      seed: 0,
      game: snapshot.game,
      steps: [],
      canReplay: false,
      cumulativeScores: snapshot.cumulativeScores,
      score: snapshot.result?.score,
      winner: snapshot.result?.winner,
      discarder: snapshot.result?.discarder,
      winMethod: nil,
      deltas: snapshot.result?.deltas ?? [0, 0, 0, 0],
      drawn: snapshot.result?.isDraw ?? false,
      paused: false,
      aiDelay: snapshot.aiDelay,
      difficulty: snapshot.difficulty,
      mode: .quick,
      careerLevelID: nil,
      practiceHints: false,
      lastRecordID: nil
    )
  }

  private static var storageDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("cardsForPlay", isDirectory: true)
  }

  private static var legacySnapshotURL: URL {
    storageDirectory.appendingPathComponent("prototype-session.json")
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
