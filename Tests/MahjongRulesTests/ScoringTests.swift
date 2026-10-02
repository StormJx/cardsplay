import Testing

@testable import MahjongRules

@Suite("MCR 番种与择高计分")
struct ScoringTests {
  @Test func ruleBookContainsAll81VersionedDefinitions() {
    #expect(Fan.allCases.count == 81)
    #expect(MCRRuleBook.definitions.count == 81)
    #expect(MCRRuleBook.exclusions.count == 81)
    #expect(Set(Fan.allCases) == Set(MCRRuleBook.definitions.keys))
    #expect(Set(Fan.allCases) == Set(MCRRuleBook.exclusions.keys))
    for fan in Fan.allCases {
      #expect(MCRRuleBook.definitions[fan]?.points == fan.points)
      #expect(MCRRuleBook.definitions[fan]?.explanationTemplate.isEmpty == false)
    }
    #expect(MCRRuleBook.version == "MCR-2006-product-1")
  }

  @Test func scoresThirteenOrphansAndSuppressesIncludedFans() {
    let honors: [TileKind] = [.east, .south, .west, .north, .red, .green, .white]
    let result = MCRScorer.score(context("119m19p19s", honors: honors, winning: .character1))
    #expect(result?.nonFlowerPoints == 88)
    #expect(awardSet(result).contains(.thirteenOrphans))
    #expect(!awardSet(result).contains(.allTerminalsAndHonors))
    #expect(
      result?.excluded.contains {
        $0.fan == .allTerminalsAndHonors && $0.excludedBy == .thirteenOrphans
      } == true)
  }

  @Test func choosesSevenShiftedPairsOverLowerDecompositions() {
    let result = MCRScorer.score(context("11223344556677m", winning: .character7))
    #expect(result?.nonFlowerPoints == 88)
    #expect(awardSet(result).contains(.sevenShiftedPairs))
    #expect(!awardSet(result).contains(.sevenPairs))
    #expect(result?.structure.shape == .sevenPairs)
  }

  @Test func scoresNineGates() {
    let result = MCRScorer.score(context("11123456789995m", winning: .character5))
    #expect(awardSet(result).contains(.nineGates))
    #expect(!awardSet(result).contains(.fullFlush))
    #expect(result?.nonFlowerPoints == 88)
  }

  @Test func scoresBigFourWindsAndBigThreeDragons() {
    let winds = [pung(.east), pung(.south), pung(.west), pung(.north)]
    let bigFour = MCRScorer.score(context("55m", melds: winds, winning: .character5))
    #expect(awardSet(bigFour).contains(.bigFourWinds))
    #expect(!awardSet(bigFour).contains(.bigThreeWinds))

    let dragons = [pung(.red), pung(.green), pung(.white)]
    let bigThree = MCRScorer.score(context("123m55p", melds: dragons, winning: .dot5))
    #expect(awardSet(bigThree).contains(.bigThreeDragons))
    #expect(!awardSet(bigThree).contains(.twoDragonPungs))
  }

  @Test func scoresAllGreenAndFourKongs() {
    let green = MCRScorer.score(context("22233344466688s", winning: .bamboo8))
    #expect(awardSet(green).contains(.allGreen))

    let kongs = [
      Meld(type: .concealedKong, tiles: Array(repeating: .character1, count: 4)),
      Meld(type: .concealedKong, tiles: Array(repeating: .dot2, count: 4)),
      Meld(type: .exposedKong, tiles: Array(repeating: .bamboo3, count: 4)),
      Meld(type: .addedKong, tiles: Array(repeating: .east, count: 4)),
    ]
    let four = MCRScorer.score(context("55m", melds: kongs, winning: .character5))
    #expect(awardSet(four).contains(.fourKongs))
    #expect(!awardSet(four).contains(.threeKongs))
  }

  @Test func scoresPureTerminalChowsAndExcludesComponents() {
    let result = MCRScorer.score(context("12312378978955m", winning: .character5))
    #expect(awardSet(result).contains(.pureTerminalChows))
    #expect(!awardSet(result).contains(.pureDoubleChow))
    #expect(!awardSet(result).contains(.twoTerminalChows))
  }

  @Test func scoresAllTerminalsHonorsAndFlushFamilies() {
    let terminals = MCRScorer.score(context("111999m111999p11s", winning: .bamboo1))
    #expect(awardSet(terminals).contains(.allTerminals))
    #expect(!awardSet(terminals).contains(.allPungs))

    let honors = MCRScorer.score(
      context(
        "",
        honors: [
          .east, .east, .east, .south, .south, .south, .west, .west, .west,
          .red, .red, .red, .white, .white,
        ], winning: .white))
    #expect(awardSet(honors).contains(.allHonors))

    let half = MCRScorer.score(
      context("123111789m", honors: [.east, .east, .east, .red, .red], winning: .red))
    #expect(awardSet(half).contains(.halfFlush))
  }

  @Test func scoresLittleHonorsAndConcealedPungs() {
    let littleFour = MCRScorer.score(
      context(
        "123m",
        honors: [.north, .north],
        melds: [pung(.east), pung(.south), pung(.west)],
        winning: .north
      ))
    #expect(awardSet(littleFour).contains(.littleFourWinds))

    let littleThree = MCRScorer.score(
      context(
        "123m",
        honors: [.white, .white],
        melds: [pung(.red), pung(.green), pung(.east)],
        winning: .white
      ))
    #expect(awardSet(littleThree).contains(.littleThreeDragons))

    let concealed = MCRScorer.score(context("111222333m444p55s", winning: .bamboo5))
    #expect(awardSet(concealed).contains(.fourConcealedPungs))
  }

  @Test func scoresChowCombinations() {
    let fourSame = MCRScorer.score(context("12312312312355m", winning: .character5))
    #expect(awardSet(fourSame).contains(.quadrupleChow))

    let fourSteps = MCRScorer.score(context("12323434545677m", winning: .character7))
    #expect(awardSet(fourSteps).contains(.fourPureShiftedChows))

    let pureStraight = MCRScorer.score(context("123456789m123p55s", winning: .bamboo5))
    #expect(awardSet(pureStraight).contains(.pureStraight))

    let mixedStraight = MCRScorer.score(context("123m456p789s234m55p", winning: .dot5))
    #expect(awardSet(mixedStraight).contains(.mixedStraight))

    let mixedTriple = MCRScorer.score(context("123m123p123s789m55p", winning: .dot5))
    #expect(awardSet(mixedTriple).contains(.mixedTripleChow))
  }

  @Test func scoresPungCombinationsAndRanges() {
    let shifted = MCRScorer.score(context("111222333444m55p", winning: .dot5))
    #expect(awardSet(shifted).contains(.fourPureShiftedPungs))

    let triple = MCRScorer.score(context("555m555p555s123m77p", winning: .dot7))
    #expect(awardSet(triple).contains(.triplePung))

    let even = MCRScorer.score(context("222444m666p888s22p", winning: .dot2))
    #expect(awardSet(even).contains(.allEvenPungs))

    let upper = MCRScorer.score(context("777888999m777p99s", winning: .bamboo9))
    #expect(awardSet(upper).contains(.upperTiles))

    let middle = MCRScorer.score(context("444555666m444p55s", winning: .bamboo5))
    #expect(awardSet(middle).contains(.middleTiles))

    let lower = MCRScorer.score(context("111222333m111p22s", winning: .bamboo2))
    #expect(awardSet(lower).contains(.lowerTiles))
  }

  @Test func scoresSpecialKnittedHands() {
    let honors: [TileKind] = [.east, .south, .west, .north, .red, .green, .white]
    let greater = MCRScorer.score(context("147m258p3s", honors: honors, winning: .bamboo3))
    #expect(awardSet(greater).contains(.greaterHonorsKnitted))

    let lesser = MCRScorer.score(
      context(
        "147m258p36s",
        honors: [.east, .south, .west, .north, .red, .green],
        winning: .bamboo6
      ))
    #expect(awardSet(lesser).contains(.lesserHonorsKnitted))

    let knitted = MCRScorer.score(
      context("147m258p369s55m", melds: [pung(.east)], winning: .character5))
    #expect(awardSet(knitted).contains(.knittedStraight))
  }

  @Test func eventFansRequireExplicitContext() {
    let base = "111222333m444p55s"
    #expect(!awardSet(MCRScorer.score(context(base, winning: .bamboo5))).contains(.lastTileDraw))
    #expect(
      awardSet(MCRScorer.score(context(base, winning: .bamboo5, lastWall: true))).contains(
        .lastTileDraw))
    #expect(
      awardSet(
        MCRScorer.score(context(base, winning: .bamboo5, method: .discard, lastDiscard: true))
      ).contains(.lastTileClaim))
    #expect(
      awardSet(MCRScorer.score(context(base, winning: .bamboo5, method: .kongReplacement)))
        .contains(.outWithReplacement))
    #expect(
      awardSet(MCRScorer.score(context(base, winning: .bamboo5, method: .robbingKong))).contains(
        .robbingKong))
    #expect(
      awardSet(MCRScorer.score(context(base, winning: .bamboo5, visible: [.bamboo5: 3]))).contains(
        .lastTile))
  }

  @Test func flowersDoNotSatisfyEightFanThreshold() {
    let low = context("123456m789p234s55p", winning: .dot5, method: .discard, flowers: 8)
    let result = MCRScorer.score(low)
    #expect(result != nil)
    #expect(result!.flowerPoints == 8)
    #expect(result!.totalPoints == result!.nonFlowerPoints + 8)
    #expect(!result!.isLegalWin)
  }

  @Test func scoresWaitsWindsDragonsAndKongs() {
    let dragon = MCRScorer.score(
      context(
        "123456m789p55s",
        melds: [pung(.red)],
        winning: .bamboo5,
        method: .discard
      ))
    #expect(awardSet(dragon).contains(.dragonPung))
    #expect(awardSet(dragon).contains(.singleWait))

    let winds = MCRScorer.score(
      context(
        "123456m789p55s",
        melds: [pung(.east)],
        winning: .bamboo5,
        method: .discard,
        seat: .east,
        round: .east
      ))
    #expect(awardSet(winds).contains(.prevalentWind))
    #expect(awardSet(winds).contains(.seatWind))

    let edge = MCRScorer.score(
      context("123m456m789p123s55p", winning: .character3, method: .discard))
    #expect(awardSet(edge).contains(.edgeWait))
    let closed = MCRScorer.score(
      context("123m456m789p123s55p", winning: .character2, method: .discard))
    #expect(awardSet(closed).contains(.closedWait))
  }

  @Test func chickenHandAppearsOnlyWhenNoOtherFanExists() {
    let hand = context(
      "789m",
      honors: [.white, .white],
      melds: [chow("234p"), chow("678s"), pung(.bamboo5)],
      winning: .character9,
      method: .discard,
      seat: .east,
      round: .south
    )
    let result = MCRScorer.score(hand)
    #expect(awardSet(result).contains(.chickenHand))
    #expect(result?.nonFlowerPoints == 8)
  }
}
