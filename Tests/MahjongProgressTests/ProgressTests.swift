import Foundation
import MahjongRules
import Testing

@testable import MahjongProgress

@Suite("成长与存档")
struct ProgressTests {
  @Test func encyclopediaMatchesTheRuleBook() {
    #expect(FanGuideBook.all.count == 81)
    #expect(FanGuideBook.all.count == Fan.allCases.count)
    for guide in FanGuideBook.all {
      #expect(guide.points == guide.fan.points)
      #expect(!guide.summary.isEmpty)
      #expect(!guide.example.isEmpty)
      let excluded = MCRRuleBook.definitions[guide.fan]?.excludedFans ?? []
      #expect(Set(guide.excluded) == excluded)
    }
    #expect(FanGuideBook.guide(.bigThreeDragons).summary.contains("中"))
    #expect(FanGuideBook.guide(.flower).summary.contains("8 番"))
    #expect(FanGuideBook.guide(.flower).points == 1)
  }

  @Test func statsSeparatePracticeAndRecomputeFromRecords() {
    let quick = sample(mode: .quick, winner: 0, discarder: nil, method: .selfDraw, fan: 10, delta: 54)
    let practice = sample(
      mode: .practice, winner: 0, discarder: nil, method: .selfDraw, fan: 88, delta: 200)
    let loss = sample(mode: .quick, winner: 1, discarder: 0, method: .discard, fan: 8, delta: -18)
    let combined = RecordBook.stats([quick, practice, loss], mode: nil)
    let quickOnly = RecordBook.stats([quick, practice, loss], mode: .quick)
    #expect(combined.hands == 3)
    #expect(combined.wins == 2)
    #expect(combined.maxFan == 88)
    #expect(quickOnly.hands == 2)
    #expect(quickOnly.wins == 1)
    #expect(quickOnly.selfDraws == 1)
    #expect(quickOnly.dealIns == 1)
    #expect(quickOnly.fanSum == 10)
    #expect(quickOnly.firsts == 1)
    #expect(loss.humanRank() == 4)
  }

  @Test func achievementsUnlockFromRecordsAndCareer() {
    let win = sample(mode: .quick, winner: 0, discarder: nil, method: .selfDraw, fan: 24, delta: 96)
    let locked = AchievementBook.evaluate(records: [win], career: CareerProgress())
    #expect(locked.first { $0.id == "first-self-draw" }?.unlocked == true)
    #expect(locked.first { $0.id == "hand-24" }?.unlocked == true)
    #expect(locked.first { $0.id == "hand-88" }?.unlocked == false)
    #expect(locked.first { $0.id == "all-bosses" }?.unlocked == false)
    var career = CareerProgress()
    for level in CareerCatalog.levels where level.chapter == 1 {
      career.bestStars[level.id] = 1
    }
    let cleared = AchievementBook.evaluate(records: [], career: career)
    #expect(cleared.first { $0.id == "chapter-1-clear" }?.unlocked == true)
    #expect(cleared.first { $0.id == "chapter-1-perfect" }?.unlocked == false)
  }

  @Test func replayRepeatsCommandsAndIgnoresHiddenHands() throws {
    let seed: UInt64 = 99
    var live = GameState(seed: seed)
    let tile = live.players[0].concealed[0]
    try live.apply(.discard(seat: 0, tile: tile))
    try live.apply(.resolveClaims([]))
    let steps: [ReplayStep] = [
      .command(.discard(seat: 0, tile: tile)),
      .command(.resolveClaims([])),
    ]
    let replayed = try HandReplay.state(seed: seed, steps: steps)
    #expect(replayed.events == live.events)
    #expect(replayed.phase == live.phase)
    #expect(replayed.wall == live.wall)
    #expect(replayed.players[0].concealed.map(\.kind) == live.players[0].concealed.map(\.kind))

    let advice = HandReplay.advice(state: GameState(seed: 7), difficulty: .normal, scores: [0, 0, 0, 0])
    #expect(!advice.isEmpty)
    #expect(advice.count <= 3)
    var hiddenPlayers = GameState(seed: 7).players
    hiddenPlayers[1].concealed = [Tile(kind: .red, copy: 0)]
    let original = GameState(seed: 7)
    let hidden = GameState(
      wall: original.wall,
      players: hiddenPlayers,
      discards: original.discards,
      phase: original.phase,
      events: original.events
    )
    #expect(
      HandReplay.advice(state: hidden, difficulty: .normal, scores: [0, 0, 0, 0]) == advice)
  }

  @Test func replayMarksAPassedWinAndAMissedKong() throws {
    let south = Tile(kind: .south, copy: 1)
    let concealed = [
      Tile(kind: .red, copy: 0), Tile(kind: .red, copy: 1), Tile(kind: .red, copy: 2),
      Tile(kind: .green, copy: 0), Tile(kind: .green, copy: 1), Tile(kind: .green, copy: 2),
      Tile(kind: .white, copy: 0), Tile(kind: .white, copy: 1), Tile(kind: .white, copy: 2),
      Tile(kind: .east, copy: 0), Tile(kind: .east, copy: 1), Tile(kind: .east, copy: 2),
      Tile(kind: .south, copy: 0),
    ]
    var players = Array(repeating: PlayerState(), count: 4)
    players[0].concealed = concealed
    let waiting = GameState(
      wall: Wall(tiles: [Tile(kind: .east, copy: 3)]),
      players: players,
      discards: [south],
      phase: .awaitingResponses(discarder: 1, tile: south),
      events: [.discarded(seat: 1, tile: south)]
    )
    #expect(
      WinContextBuilder.legalScore(state: waiting, seat: 0, tile: .south, method: .discard) != nil)
    let passed = ReplayFrame(index: 0, state: waiting, step: nil)
    var afterPass = waiting
    try afterPass.apply(.resolveClaims([]))
    let notes = HandReplay.notes(frames: [
      passed,
      ReplayFrame(index: 1, state: afterPass, step: .command(.resolveClaims([]))),
    ])
    #expect(notes.contains { $0.mark == .skippedWin })

    var kongPlayers = Array(repeating: PlayerState(), count: 4)
    kongPlayers[0].concealed = [
      Tile(kind: .white, copy: 0), Tile(kind: .white, copy: 1),
      Tile(kind: .white, copy: 2), Tile(kind: .white, copy: 3),
      Tile(kind: .east, copy: 0),
    ]
    let beforeDiscard = GameState(
      wall: Wall(tiles: [Tile(kind: .dot1, copy: 0)]),
      players: kongPlayers,
      phase: .awaitingDiscard(seat: 0)
    )
    var discarded = beforeDiscard
    try discarded.apply(.discard(seat: 0, tile: Tile(kind: .east, copy: 0)))
    let kongNotes = HandReplay.notes(frames: [
      ReplayFrame(index: 0, state: beforeDiscard, step: nil),
      ReplayFrame(
        index: 1, state: discarded,
        step: .command(.discard(seat: 0, tile: Tile(kind: .east, copy: 0)))),
    ])
    #expect(kongNotes.contains { $0.mark == .missedKong })
  }

  @Test func eastRoundRotatesTheDealerAndKeepsScoresZeroSum() throws {
    let initial = 2
    let dealers = (0..<EastRound.handCount).map {
      EastRound.dealer(handIndex: $0, initialDealer: initial)
    }
    #expect(dealers == [2, 3, 0, 1])
    #expect(Set(dealers).count == 4)
    #expect(EastRound.isFinalHand(2) == false)
    #expect(EastRound.isFinalHand(3))
    #expect(EastRound.roundWind == .east)
    #expect(EastRound.seatWind(seat: 2, dealer: 2) == .east)
    #expect(EastRound.seatWind(seat: 3, dealer: 2) == .south)
    #expect(EastRound.seatWind(seat: 0, dealer: 2) == .west)
    #expect(EastRound.seatWind(seat: 1, dealer: 2) == .north)

    let selfDraw = try Settlement.win(winner: 0, discarder: nil, fan: 10)
    let ron = try Settlement.win(winner: 1, discarder: 0, fan: 10)
    #expect(selfDraw == [54, -18, -18, -18])
    #expect(ron == [-18, 34, -8, -8])
    let afterTwo = EastRound.accumulate(EastRound.accumulate([0, 0, 0, 0], selfDraw), ron)
    #expect(afterTwo == [36, 16, -26, -26])
    #expect(afterTwo.reduce(0, +) == 0)

    var live = GameState(seed: 5, dealer: 1)
    let tile = live.players[1].concealed[0]
    try live.apply(.discard(seat: 1, tile: tile))
    let replayed = try HandReplay.state(
      seed: 5, steps: [.command(.discard(seat: 1, tile: tile))], dealer: 1)
    #expect(replayed.phase == live.phase)
    #expect(replayed.players[1].concealed.map(\.kind) == live.players[1].concealed.map(\.kind))
  }

  @Test func careerCatalogKeepsChapterOnePlayable() {
    #expect(CareerCatalog.chapters.count == 5)
    #expect(CareerCatalog.levels.count == 50)
    let playable = CareerCatalog.levels.filter(\.playable)
    #expect(playable.count == 10)
    #expect(playable.allSatisfy { $0.chapter == 1 && $0.difficulty == .beginner })
    #expect(playable.contains { $0.isBoss && $0.title.contains("阿岚") })
    #expect(CareerCatalog.levels.filter { $0.chapter > 1 }.allSatisfy { !$0.playable })
    let level = CareerCatalog.level(id: "1-01")!
    let won = HandOutcome(
      humanWon: true, selfDrawn: true, dealtIn: false, drawn: false, nonFlowerPoints: 16,
      awards: [.selfDraw], exposedMelds: 0, kongs: 0, concealedKongs: 0)
    #expect(CareerGrader.stars(for: level, outcome: won) == 3)
    let lost = HandOutcome(
      humanWon: false, selfDrawn: false, dealtIn: true, drawn: false, nonFlowerPoints: 0,
      awards: [], exposedMelds: 0, kongs: 0, concealedKongs: 0)
    #expect(CareerGrader.stars(for: level, outcome: lost) == 0)
    let defense = CareerCatalog.level(id: "1-04")!
    let escaped = HandOutcome(
      humanWon: false, selfDrawn: false, dealtIn: false, drawn: true, nonFlowerPoints: 0,
      awards: [], exposedMelds: 0, kongs: 0, concealedKongs: 0)
    #expect(CareerGrader.stars(for: defense, outcome: escaped) == 1)
  }

  @Test func corruptSnapshotFallsBackAndTranscriptsAreCapped() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var first = ProgressLibrary()
    first.append(sample(mode: .quick, winner: 0, discarder: nil, method: .discard, fan: 8, delta: 32))
    try ProgressArchive.save(first, to: directory)
    var second = first
    second.append(sample(mode: .career, winner: nil, discarder: nil, method: nil, fan: 0, delta: 0))
    try ProgressArchive.save(second, to: directory)
    let current = directory.appendingPathComponent("progress.json")
    try Data("damaged".utf8).write(to: current)
    let recovered = ProgressArchive.load(from: directory)
    #expect(recovered.records.count == 1)
    #expect(recovered.records[0].mode == .quick)

    var crowded = ProgressLibrary()
    for _ in 0..<45 {
      crowded.append(sample(mode: .quick, winner: 0, discarder: nil, method: .selfDraw, fan: 8, delta: 1))
    }
    #expect(crowded.records.count == ProgressLibrary.transcriptLimit)
  }

  private func sample(
    mode: PlayMode,
    winner: Int?,
    discarder: Int?,
    method: WinMethod?,
    fan: Int,
    delta: Int
  ) -> HandRecord {
    HandRecord(
      mode: mode,
      seed: 1,
      difficulty: .beginner,
      steps: [],
      canReplay: false,
      winner: winner,
      discarder: discarder,
      winMethod: method,
      fanPoints: fan,
      nonFlowerPoints: fan,
      awardFans: winner == 0 ? [Fan.selfDraw.rawValue] : [],
      deltas: [delta, -delta / 3, -delta / 3, -delta + (delta / 3) * 2],
      chowCount: 0,
      pungCount: 0,
      kongCount: 0,
      concealedKongCount: 0,
      humanExposedMelds: 0
    )
  }
}
