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
    #expect(HandReplay.checkpointIndexes(notes: notes) == [1])
    #expect(HandReplay.checkpointIndexes(notes: kongNotes) == [1])

    let mixed = notes + kongNotes + [
      ReplayNote(frameIndex: 4, mark: .dealtIn, text: "点炮"),
      ReplayNote(frameIndex: 4, mark: .won, text: "和牌"),
      ReplayNote(frameIndex: 6, mark: .claimed, text: "鸣牌"),
    ]
    #expect(HandReplay.checkpointIndexes(notes: mixed) == [1, 4])
    #expect(HandReplay.advance(index: 0, frameCount: 8, stopAtChecks: true, checkpoints: [1, 4]) == (1, false))
    #expect(HandReplay.advance(index: 1, frameCount: 8, stopAtChecks: true, checkpoints: [1, 4]) == (2, true))
    #expect(HandReplay.advance(index: 3, frameCount: 8, stopAtChecks: false, checkpoints: [1, 4]) == (4, true))
    #expect(HandReplay.advance(index: 6, frameCount: 8, stopAtChecks: false, checkpoints: []) == (7, false))
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

  @Test func practiceShowsWaitsAndPublicDanger() {
    let concealed: [TileKind] = [
      .character1, .character2, .character3,
      .character4, .character5, .character6,
      .character7, .character8, .character9,
      .dot2, .dot3, .white, .white, .east,
    ]
    let waits = PracticeCoach.waitingTiles(
      concealed: concealed,
      removing: .east,
      melds: [],
      seatWind: .east,
      roundWind: .east,
      unseen: { kind in
        if kind == .dot1 { return 1 }
        if kind == .dot4 { return 2 }
        return 4
      }
    )
    #expect(waits.map(\.tile) == [.dot1, .dot4])
    #expect(waits.map(\.remaining) == [1, 2])

    let brief = PracticeCoach.brief(
      concealed: concealed,
      melds: [],
      discarding: true,
      selected: .east,
      discards: [[], [], [], []],
      exposedMelds: [[], [], [], []],
      scores: [0, 0, 0, 0],
      seat: 0,
      seatWind: .east,
      roundWind: .east,
      unseen: { _ in 4 }
    )
    #expect(brief.waitLine.contains("打出东后听"))
    #expect(brief.waitLine.contains("1筒剩4"))
    #expect(brief.waitLine.contains("4筒剩4"))
    #expect(brief.dangerLine.contains("低"))
    #expect(brief.dangerLine.contains("没有副露"))

    let pairs: [TileKind] = [
      .character1, .character1, .character2, .character2, .character3, .character3,
      .character4, .character4, .character5, .character5, .character6, .character6,
      .character7, .character8,
    ]
    #expect(PracticeCoach.closeFanNotes(tiles: pairs).contains("接近七对，还差1对"))
    let flush: [TileKind] = [
      .character1, .character1, .character2, .character2, .character3, .character3,
      .character4, .character4, .character5, .character5, .character6, .character7,
      .character8, .dot9,
    ]
    #expect(PracticeCoach.closeFanNotes(tiles: flush).contains("接近清一色，还差打出1张其他花色"))

    let pung = Meld(type: .pung, tiles: [.white, .white, .white])
    let quiet = PracticeCoach.danger(
      tile: .character5, seat: 0, discards: [[], [], [], []], exposedMelds: [[], [], [], []],
      scores: [0, 0, 0, 0], visibleCount: 0)
    let exposed = PracticeCoach.danger(
      tile: .character5, seat: 0, discards: [[], [], [], []],
      exposedMelds: [[], [pung, pung], [], []], scores: [0, 0, 0, 0], visibleCount: 0)
    let seenOut = PracticeCoach.danger(
      tile: .character5, seat: 0, discards: [[], [], [], []],
      exposedMelds: [[], [pung, pung], [], []], scores: [0, 0, 0, 0], visibleCount: 3)
    let safeDiscard = PracticeCoach.danger(
      tile: .character5, seat: 0, discards: [[], [.character5], [], []],
      exposedMelds: [[], [pung, pung], [], []], scores: [0, 0, 0, 0], visibleCount: 1)
    #expect(quiet.level == "低")
    #expect(exposed.level == "高")
    #expect(exposed.reason.contains("中张"))
    #expect(seenOut.level == "低")
    #expect(safeDiscard.level == "低")

    var players = Array(repeating: PlayerState(), count: 4)
    players[1].concealed = (0..<4).map { Tile(kind: .south, copy: $0) }
    let state = GameState(
      wall: Wall(tiles: []), players: players, phase: .awaitingDiscard(seat: 0))
    #expect(PublicInfo.unseenCount(state: state, kind: .south) == 4)
  }

  @Test func careerCatalogKeepsChapterOnePlayable() {
    #expect(CareerCatalog.chapters.count == 5)
    #expect(CareerCatalog.levels.count == 50)
    let playable = CareerCatalog.levels.filter(\.playable)
    #expect(playable.count == 50)
    let chapterOne = playable.filter { $0.chapter == 1 }
    #expect(chapterOne.count == 10)
    #expect(chapterOne.allSatisfy { $0.difficulty == .beginner })
    #expect(playable.contains { $0.isBoss && $0.title.contains("阿岚") })
    #expect(CareerCatalog.levels.filter { $0.chapter > 1 }.allSatisfy { $0.playable })
    for number in 2...5 {
      let levels = CareerCatalog.levels.filter { $0.chapter == number }
      #expect(levels.count == 10)
      #expect(levels.filter(\.isBoss).count == 1)
      for level in levels {
        #expect(CareerGrader.stars(for: level, outcome: reachableClear(level)) == 3)
      }
    }
    #expect(CareerCatalog.level(id: "2-10")?.title.contains("烈风") == true)
    #expect(CareerCatalog.level(id: "3-10")?.title.contains("静川") == true)
    #expect(CareerCatalog.level(id: "4-10")?.title.contains("墨衡") == true)
    #expect(CareerCatalog.level(id: "5-10")?.title.contains("玄策") == true)
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
    let lines = CareerGrader.starLines(for: level, outcome: won)
    #expect(lines.map(\.met) == [true, true, true])
    #expect(CareerGrader.missingSummary(for: level, outcome: won) == "三星都达成")
    let partial = HandOutcome(
      humanWon: true, selfDrawn: false, dealtIn: false, drawn: false, nonFlowerPoints: 8,
      awards: [], exposedMelds: 0, kongs: 0, concealedKongs: 0)
    #expect(CareerGrader.starLines(for: level, outcome: partial).map(\.met) == [true, false, false])
    let missing = CareerGrader.missingSummary(for: level, outcome: partial)
    #expect(missing.contains("第2星：自摸"))
    #expect(missing.contains("第3星：至少 16 番"))
    #expect(CareerCatalog.nextPlayable(after: "1-01")?.id == "1-02")
    #expect(CareerCatalog.nextPlayable(after: "1-10")?.id == "2-01")
    #expect(CareerCatalog.nextPlayable(after: "5-10") == nil)
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

  @Test func fullMatchRotatesWindsAndRanksTheTotal() {
    #expect(FullMatch.handCount == 16)
    #expect(FullMatch.winds == [.east, .south, .west, .north])
    let winds = (0..<FullMatch.handCount).map(FullMatch.roundWind(handIndex:))
    #expect(winds.filter { $0 == .east }.count == 4)
    #expect(winds.filter { $0 == .south }.count == 4)
    #expect(winds.filter { $0 == .west }.count == 4)
    #expect(winds.filter { $0 == .north }.count == 4)
    #expect(FullMatch.roundWind(handIndex: 0) == .east)
    #expect(FullMatch.roundWind(handIndex: 4) == .south)
    #expect(FullMatch.roundWind(handIndex: 15) == .north)
    #expect(FullMatch.handInRound(handIndex: 5) == 2)
    #expect(FullMatch.isFinalHand(14) == false)
    #expect(FullMatch.isFinalHand(15))
    let dealers = (0..<FullMatch.handCount).map {
      FullMatch.dealer(handIndex: $0, initialDealer: 1)
    }
    #expect(dealers.prefix(4).map { $0 } == [1, 2, 3, 0])
    #expect(dealers[4] == 1)
    #expect(FullMatch.seatWind(seat: 0, dealer: dealers[4]) == .north)
    #expect(EastRound.handCount == 4)
    #expect(EastRound.roundWind == .east)
    let totals = FullMatch.ranks([12, 12, -4, -20])
    #expect(totals == [1, 1, 3, 4])
    #expect(totals.reduce(0, +) != 0)
    let deltas = [8, -4, -2, -2]
    #expect(EastRound.accumulate([0, 0, 0, 0], deltas).reduce(0, +) == 0)
  }

  @Test func scriptedSpecialHandsClearTheirStars() throws {
    let cases: [(String, CareerPuzzle, Fan)] = [
      ("4-03", .sevenPairs, .sevenPairs),
      ("4-04", .honorsKnitted, .lesserHonorsKnitted),
      ("4-05", .knittedStraight, .knittedStraight),
    ]
    for (id, puzzle, fan) in cases {
      let level = CareerCatalog.level(id: id)!
      #expect(level.puzzle == puzzle)
      #expect(level.star1 == star(for: puzzle))
      var state = CareerDeals.opening(puzzle)
      try state.apply(.draw(seat: 0))
      let score = try #require(
        WinContextBuilder.selfDrawScore(state: state, seat: 0, roundWind: .east, seatWind: .east))
      #expect(score.isLegalWin)
      #expect(score.awards.contains { $0.fan == fan })
      let outcome = HandOutcome(
        humanWon: true, selfDrawn: true, dealtIn: false, drawn: false,
        nonFlowerPoints: score.nonFlowerPoints, awards: score.awards.map(\.fan),
        exposedMelds: 0, kongs: 0, concealedKongs: 0)
      #expect(CareerGrader.stars(for: level, outcome: outcome) == 3)
      let ordinary = HandOutcome(
        humanWon: true, selfDrawn: true, dealtIn: false, drawn: false,
        nonFlowerPoints: 24, awards: [.selfDraw], exposedMelds: 0, kongs: 0, concealedKongs: 0)
      #expect(CareerGrader.stars(for: level, outcome: ordinary) == 0)
    }
    #expect(CareerCatalog.level(id: "1-01")?.puzzle == nil)
    #expect(CareerCatalog.level(id: "1-01")?.star1 == .win)
  }

  @Test func practiceReadsShantenBlocksAndConflicts() {
    let tenpai: [TileKind] = [
      .character1, .character2, .character3,
      .character4, .character5, .character6,
      .character7, .character8, .character9,
      .dot2, .dot3, .white, .white,
    ]
    #expect(PracticeCoach.shanten(of: tenpai, meldCount: 0) == 0)
    let studies = PracticeCoach.discardStudies(
      concealed: tenpai + [.east],
      melds: [],
      seatWind: .east,
      roundWind: .east,
      unseen: { _ in 2 }
    )
    let east = studies.first { $0.tile == .east }
    #expect(east?.shanten == 0)
    #expect((east?.usefulTiles ?? 0) > 0)
    let meld = Meld(type: .pung, tiles: [.white, .white, .white])
    #expect(PracticeCoach.blockedFanNames(melds: [meld]).contains("七对"))
    #expect(PracticeCoach.newlyBlocked(before: [], after: [meld]).contains("全不靠"))
    #expect(PracticeCoach.droppedBelowEight(before: 10, after: 6))
    #expect(PracticeCoach.conflictingFanNames(tiles: tenpai, melds: []).contains("清一色"))
    #expect(PracticeCoach.conflictingFanNames(tiles: tenpai, melds: []).contains("断幺"))
    let off = PracticeSwitches(waits: false, recommendation: false, remaining: true, fans: false, danger: false)
    let brief = PracticeCoach.brief(
      concealed: tenpai + [.east], melds: [], discarding: true, selected: .east,
      discards: [[], [], [], []], exposedMelds: [[], [], [], []], scores: [10, 0, 0, 0],
      seat: 0, seatWind: .east, roundWind: .east, unseen: { _ in 2 }, switches: off)
    #expect(brief.waitLine.contains("关闭"))
    #expect(brief.shantenLine.isEmpty)
    #expect(PracticeCoach.situationLine(scores: [10, 0, 0, 0], seat: 0).contains("领先"))
  }

  @Test func replaySeparatesRecordedRulesFromCurrentAnalysis() {
    let record = sample(
      mode: .full, winner: 0, discarder: nil, method: .selfDraw, fan: 16, delta: 24)
    let same = HandReplay.readings(record: record)
    #expect(same.recorded.version == record.ruleVersion)
    #expect(same.current.version == MCRRuleBook.version)
    #expect(same.recorded.title.contains("原规则"))
    #expect(same.current.title.contains("当前规则"))
    let old = HandRecord(
      mode: .full, seed: 1, difficulty: .beginner, steps: [], canReplay: false,
      winner: 0, discarder: nil, winMethod: .selfDraw, fanPoints: 8, nonFlowerPoints: 8,
      awardFans: [], deltas: [8, -8, 0, 0], chowCount: 0, pungCount: 0, kongCount: 0,
      concealedKongCount: 0, humanExposedMelds: 0, ruleVersion: "MCR-old")
    let changed = HandReplay.readings(record: old)
    #expect(changed.recorded.version == "MCR-old")
    #expect(changed.current.detail.contains("MCR-old"))
    #expect(changed.current.detail.contains(MCRRuleBook.version))
    let chow = Meld(
      type: .chow, tiles: [.character1, .character2, .character3], claimedFrom: 3)
    #expect(PracticeCoach.newlyBlocked(before: [], after: [chow]).contains("七对"))
    let json = #"{"music":0.2,"effects":0.4,"voice":0.8}"#
    let audio = try! JSONDecoder().decode(AudioSettings.self, from: Data(json.utf8))
    #expect(audio.hapticsEnabled)
    var career = CareerProgress()
    career.bestStars["2-10"] = 1
    let items = CosmeticCatalog.items(career: career)
    #expect(items.first { $0.id == "table-wood" }?.unlocked == true)
    #expect(items.first { $0.id == "character-liefeng" }?.unlocked == true)
    #expect(items.first { $0.id == "table-final" }?.unlocked == false)
  }

  @Test func repeatDealerStaysForAWinOrDrawOnlyWhenEnabled() {
    var passed = 2
    var seats = [passed]
    for _ in 1..<EastRound.handCount {
      passed = EastRound.nextDealer(current: passed, continuation: .draw, repeats: false)
      seats.append(passed)
    }
    #expect(seats == [2, 3, 0, 1])
    #expect(seats == (0..<EastRound.handCount).map { EastRound.dealer(handIndex: $0, initialDealer: 2) })
    #expect(EastRound.nextDealer(current: 1, continuation: .win(1), repeats: false) == 2)
    #expect(EastRound.nextDealer(current: 1, continuation: .draw, repeats: false) == 2)
    #expect(EastRound.nextDealer(current: 1, continuation: .win(0), repeats: false) == 2)
    #expect(EastRound.nextDealer(current: 1, continuation: .win(1), repeats: true) == 1)
    #expect(EastRound.nextDealer(current: 1, continuation: .draw, repeats: true) == 1)
    #expect(EastRound.nextDealer(current: 1, continuation: .win(0), repeats: true) == 2)
    #expect(FullMatch.nextDealer(current: 0, continuation: .draw, repeats: true) == 0)
    #expect(FullMatch.nextDealer(current: 0, continuation: .win(2), repeats: true) == 1)
    #expect(EastRound.handCount == 4)
    #expect(FullMatch.handCount == 16)

    var dealer = 0
    let endings: [EastRound.Continuation] = [.win(0), .draw, .win(1)]
    var dealt = [dealer]
    for ending in endings {
      dealer = EastRound.nextDealer(current: dealer, continuation: ending, repeats: true)
      dealt.append(dealer)
    }
    #expect(dealt == [0, 0, 0, 1])
  }

  @Test func practiceHidesFanUntilTenpai() {
    let scattered: [TileKind] = [
      .character1, .character9, .dot1, .dot9, .bamboo1, .bamboo9,
      .east, .south, .west, .north, .red, .green, .white, .character5,
    ]
    let early = PracticeCoach.brief(
      concealed: scattered,
      melds: [],
      discarding: true,
      selected: .east,
      discards: [[], [], [], []],
      exposedMelds: [[], [], [], []],
      scores: [0, 0, 0, 0],
      seat: 0,
      seatWind: .east,
      roundWind: .east,
      unseen: { _ in 4 }
    )
    #expect(early.shantenLine.contains("向听"))
    #expect(early.shantenLine.contains("有效"))
    #expect(!early.shantenLine.contains("番"))
    #expect(!early.shantenLine.contains("约"))
    #expect(early.fanLine.isEmpty)
    #expect(early.waitLine.isEmpty)
    #expect(early.dangerLine.isEmpty)
    #expect(PracticeCoach.shanten(of: scattered.filter { $0 != .east }, meldCount: 0) > 0)

    let tenpai: [TileKind] = [
      .character1,
      .character2, .character3, .character4,
      .character5, .character6, .character7,
      .character8, .character9,
      .dot2, .dot3, .dot4,
      .bamboo5, .bamboo5,
    ]
    let ready = PracticeCoach.brief(
      concealed: tenpai,
      melds: [],
      discarding: true,
      selected: .character1,
      discards: [[], [], [], []],
      exposedMelds: [[], [], [], []],
      scores: [0, 0, 0, 0],
      seat: 0,
      seatWind: .east,
      roundWind: .east,
      unseen: { _ in 4 }
    )
    #expect(ready.waitLine.contains("听"))
    #expect(ready.fanLine.contains("番"))
    #expect(!ready.dangerLine.isEmpty)
    #expect(ready.shantenLine.contains("约"))
  }

  @Test func laterCareerLevelsUseRoundsWithoutChangingChapterOne() {
    let chapterOne = CareerCatalog.levels.filter { $0.chapter == 1 }
    #expect(chapterOne.allSatisfy { $0.table == .single(dealer: 0) })
    #expect(chapterOne.map(\.star1) == [
      .win, .win, .win, .noDealIn, .win, .win, .win, .win, .win, .win,
    ])
    #expect(CareerCatalog.level(id: "4-03")?.table == .single(dealer: 0))
    #expect(CareerCatalog.level(id: "4-04")?.table == .single(dealer: 0))
    #expect(CareerCatalog.level(id: "4-05")?.table == .single(dealer: 0))
    #expect(CareerCatalog.level(id: "4-03")?.puzzle == .sevenPairs)
    #expect(CareerCatalog.level(id: "5-05")?.table == .eastRound(initialDealer: 1))
    #expect(CareerCatalog.level(id: "5-06")?.table == .eastRound(initialDealer: 3))
    #expect(CareerCatalog.level(id: "5-09")?.table == .fullMatch(initialDealer: 1))
    #expect(CareerCatalog.level(id: "5-10")?.table == .fullMatch(initialDealer: 2))
    let later = CareerCatalog.levels.filter { $0.chapter > 1 }
    #expect(later.contains { $0.table.rotates })
    #expect(later.contains {
      if case .single(let dealer) = $0.table { return dealer != 0 }
      return false
    })
  }

  @Test func diceGradesPointBands() {
    for face in 1...4 {
      #expect(DailyDice.grade(faces: [face]) == .plain)
    }
    #expect(DailyDice.grade(faces: [5]) == .small)
    #expect(DailyDice.grade(faces: [6]) == .great)

    #expect(DailyDice.grade(faces: [1, 1]) == .plain)
    #expect(DailyDice.grade(faces: [2, 6]) == .plain)
    #expect(DailyDice.grade(faces: [3, 6]) == .small)
    #expect(DailyDice.grade(faces: [4, 6]) == .small)
    #expect(DailyDice.grade(faces: [5, 6]) == .great)
    #expect(DailyDice.grade(faces: [6, 6]) == .great)

    #expect(DailyDice.grade(faces: [1, 1, 1]) == .plain)
    #expect(DailyDice.grade(faces: [2, 4, 5]) == .plain)
    #expect(DailyDice.grade(faces: [2, 4, 6]) == .small)
    #expect(DailyDice.grade(faces: [4, 5, 5]) == .small)
    #expect(DailyDice.grade(faces: [4, 5, 6]) == .great)
    #expect(DailyDice.grade(faces: [6, 6, 6]) == .great)
    #expect(DailyDice.grade(faces: []) == .plain)
    #expect(DailyDice.grade(faces: [6, 6, 6, 6]) == .plain)
  }

  @Test func fortuneLastsThreeGamesAndANewRollReplacesIt() {
    var track = FortuneTrack()
    track.roll(faces: [6])
    #expect(track.tier == .great)
    #expect(track.queuedGames == 3)
    #expect(!track.activeGame)
    #expect(track.gamesRemaining == 3)
    #expect(track.remainingLine == "运势还剩 3 局")

    let first = track.beginGame()
    #expect(first)
    #expect(track.queuedGames == 2)
    #expect(track.gamesRemaining == 3)
    #expect(track.drawHelp)
    #expect(track.openingHelp)
    track.finishGame()
    #expect(track.gamesRemaining == 2)

    let second = track.beginGame()
    track.finishGame()
    let third = track.beginGame()
    track.finishGame()
    #expect(second && third)
    #expect(track.gamesRemaining == 0)
    #expect(track.remainingLine == nil)
    let fourth = track.beginGame()
    #expect(fourth == false)
    #expect(!track.drawHelp)
    #expect(!track.openingHelp)

    track.roll(faces: [6])
    let usedOnce = track.beginGame()
    #expect(usedOnce)
    track.roll(faces: [5])
    #expect(track.tier == .small)
    #expect(!track.activeGame)
    #expect(track.queuedGames == 3)
    #expect(track.gamesRemaining == 3)
    let refreshed = track.beginGame()
    #expect(refreshed)
    #expect(track.drawHelp)
    #expect(!track.openingHelp)

    track.roll(faces: [1, 1])
    #expect(track.tier == .plain)
    #expect(track.gamesRemaining == 0)
    let plainStart = track.beginGame()
    #expect(plainStart == false)

    track.roll(faces: [6, 6])
    var started = 0
    while track.beginGame() {
      started += 1
      track.finishGame()
    }
    let extra = track.beginGame()
    #expect(started == 3)
    #expect(extra == false)
  }

  @Test func fortuneExchangesOnlyTilesAlreadyInHandOrWall() throws {
    let characters = (1...9).compactMap { TileKind(suit: .characters, rank: $0) }
    let paired = characters + [.east, .east, .south, .west, .white]
    #expect(FortuneAid.openingPairExchange(hand: paired, upcoming: [.south]) == nil)

    let singles = characters + [.east, .south, .west, .north, .white]
    #expect(FortuneAid.openingPairExchange(hand: singles, upcoming: [.red, .green]) == nil)
    let opening = try #require(
      FortuneAid.openingPairExchange(hand: singles, upcoming: [.spring, .red, .east]))
    #expect(opening.offset == 2)
    #expect(opening.remove != .east)
    #expect(singles.contains(opening.remove))

    let drawn = TileKind(suit: .bamboo, rank: 9)!
    let concealed = characters + [
      TileKind(suit: .dots, rank: 1)!,
      TileKind(suit: .dots, rank: 2)!,
      .east, .east, drawn,
    ]
    let upcoming: [TileKind] = [.spring, .white, TileKind(suit: .dots, rank: 3)!, .red]
    let current = PracticeCoach.shanten(of: concealed, meldCount: 0)
    let offset = try #require(
      FortuneAid.improvingDrawOffset(
        concealed: concealed, meldCount: 0, drawn: drawn, upcoming: upcoming))
    #expect(offset == 2)
    var without = concealed
    without.removeAll { $0 == drawn }
    #expect(PracticeCoach.shanten(of: without + [upcoming[offset]], meldCount: 0) < current)

    var game = GameState(seed: 5, dealer: 0)
    let wallBefore = game.wall.tiles
    let handTile = game.players[0].concealed[0]
    let fromWall = try #require(game.wall.upcomingTiles(limit: 1).first)
    let exchanged = game.exchangeOpening(seat: 0, handTile: handTile, upcomingOffset: 0)
    #expect(exchanged)
    #expect(Set(game.wall.tiles) == Set(wallBefore))
    #expect(game.players[0].concealed.contains(fromWall))
    #expect(game.wall.tiles.contains(handTile))
  }

  @Test func replayBranchKeepsTheOriginalDiscard() throws {
    var live = GameState(seed: 11, dealer: 0)
    let played = live.players[0].concealed[0]
    let other = try #require(live.players[0].concealed.first { $0 != played })
    let steps: [ReplayStep] = [.command(.discard(seat: 0, tile: played))]
    try live.apply(.discard(seat: 0, tile: played))
    let frames = try HandReplay.frames(seed: 11, steps: steps, dealer: 0)
    let branch = try #require(HandReplay.branch(frames: frames, index: 1))
    #expect(branch.played == played)
    #expect(branch.alternatives.contains(other))
    #expect(!branch.alternatives.contains(played))
    #expect(branch.prefixSteps.isEmpty)
    var forked = branch.state
    try forked.apply(.discard(seat: 0, tile: other))
    let original = try HandReplay.state(seed: 11, steps: steps, dealer: 0)
    #expect(original.discards.last == played)
    #expect(forked.discards.last == other)
  }

  private func star(for puzzle: CareerPuzzle) -> StarCondition {
    switch puzzle {
    case .sevenPairs: return .sevenPairs
    case .honorsKnitted: return .honorsKnitted
    case .knittedStraight: return .knittedStraight
    }
  }

  private func reachableClear(_ level: CareerLevel) -> HandOutcome {
    let conditions = [level.star1, level.star2, level.star3]
    let melded = conditions.contains(.anyMeld)
    let kong = conditions.contains(.anyKong) || conditions.contains(.concealedKong)
    var awards: [Fan] = [.allChows, .allSimples, .oneVoidedSuit, .noHonors, .selfDraw]
    if conditions.contains(.sevenPairs) { awards.append(.sevenPairs) }
    if conditions.contains(.honorsKnitted) { awards.append(.lesserHonorsKnitted) }
    if conditions.contains(.knittedStraight) { awards.append(.knittedStraight) }
    return HandOutcome(
      humanWon: true,
      selfDrawn: true,
      dealtIn: false,
      drawn: false,
      nonFlowerPoints: 24,
      awards: awards,
      exposedMelds: melded ? 1 : 0,
      kongs: kong ? 1 : 0,
      concealedKongs: conditions.contains(.concealedKong) ? 1 : 0
    )
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
