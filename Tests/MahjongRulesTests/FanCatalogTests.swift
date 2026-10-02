import Testing

@testable import MahjongRules

@Suite("81 番逐项案例")
struct FanCatalogTests {
  @Test(arguments: Fan.allCases)
  func everyFanHasAConcretePositiveExample(_ fan: Fan) {
    let hand = positiveExample(for: fan)
    let matchingScores = MCRScorer.scores(hand).filter { result in
      result.awards.contains { $0.fan == fan }
    }
    #expect(
      !matchingScores.isEmpty,
      "第 \(fan.rawValue) 番「\(fan.name)」正例未检出；输入为 \(hand.allTiles.map(\.shortName))"
    )
  }

  @Test(arguments: Fan.allCases)
  func everyFanHasAConcreteNegativeExample(_ fan: Fan) {
    let hand = negativeExample(for: fan)
    let scores = MCRScorer.scores(hand)
    #expect(!scores.isEmpty, "「\(fan.name)」反例必须先是合法和牌结构")
    #expect(
      scores.allSatisfy { result in
        !result.awards.contains { $0.fan == fan }
      },
      "「\(fan.name)」反例错误命中"
    )
  }

  @Test func higherFansSuppressActuallyPresentLowerFans() {
    let examples: [(source: Fan, suppressed: Set<Fan>, context: WinContext)] = [
      (
        .thirteenOrphans,
        [.allTypes, .fullyConcealedHand, .concealedHand, .singleWait],
        positiveExample(for: .thirteenOrphans)
      ),
      (
        .sevenShiftedPairs,
        [.sevenPairs, .fullFlush, .fullyConcealedHand, .singleWait],
        positiveExample(for: .sevenShiftedPairs)
      ),
      (
        .nineGates,
        [.fullFlush, .fullyConcealedHand, .twoConcealedPungs, .singleWait],
        positiveExample(for: .nineGates)
      ),
      (
        .fourConcealedPungs,
        [.allPungs, .threeConcealedPungs, .twoConcealedPungs],
        positiveExample(for: .fourConcealedPungs)
      ),
      (
        .pureTerminalChows,
        [.fullFlush, .allChows, .pureDoubleChow, .twoTerminalChows],
        positiveExample(for: .pureTerminalChows)
      ),
      (
        .quadrupleChow,
        [.pureTripleChow, .pureDoubleChow, .tileHog],
        positiveExample(for: .quadrupleChow)
      ),
      (
        .fourPureShiftedPungs,
        [.pureShiftedPungs, .allPungs],
        positiveExample(for: .fourPureShiftedPungs)
      ),
      (
        .fourPureShiftedChows,
        [.pureShiftedChows, .shortStraight],
        positiveExample(for: .fourPureShiftedChows)
      ),
      (
        .pureStraight,
        [.shortStraight, .twoTerminalChows],
        positiveExample(for: .pureStraight)
      ),
      (
        .triplePung,
        [.doublePung],
        positiveExample(for: .triplePung)
      ),
      (
        .lastTileDraw,
        [.selfDraw],
        positiveExample(for: .lastTileDraw)
      ),
      (
        .outWithReplacement,
        [.selfDraw],
        positiveExample(for: .outWithReplacement)
      ),
      (
        .fullyConcealedHand,
        [.concealedHand, .selfDraw],
        positiveExample(for: .fullyConcealedHand)
      ),
    ]

    for example in examples {
      let results = MCRScorer.scores(example.context).filter {
        $0.awards.contains { $0.fan == example.source }
      }
      #expect(!results.isEmpty, "排斥例缺少高番「\(example.source.name)」")
      for result in results {
        for lower in example.suppressed {
          #expect(
            !result.awards.contains { $0.fan == lower },
            "「\(example.source.name)」未排斥「\(lower.name)」"
          )
        }
      }
    }
  }
}
private func positiveExample(for fan: Fan) -> WinContext {
  switch fan {
  case .bigFourWinds:
    return context(
      "55m", melds: [pung(.east), pung(.south), pung(.west), pung(.north)],
      winning: .character5)
  case .bigThreeDragons:
    return context(
      "123m55p", melds: [pung(.red), pung(.green), pung(.white)], winning: .dot5)
  case .allGreen:
    return context("22233344466688s", winning: .bamboo8)
  case .nineGates:
    return context("11123456789995m", winning: .character5)
  case .fourKongs:
    return context(
      "55m",
      melds: [
        kong(.character1, concealed: true), kong(.dot2, concealed: true),
        kong(.bamboo3), kong(.east, added: true),
      ],
      winning: .character5)
  case .sevenShiftedPairs:
    return context("11223344556677m", winning: .character7)
  case .thirteenOrphans:
    return context(
      "119m19p19s",
      honors: [.east, .south, .west, .north, .red, .green, .white],
      winning: .character1)
  case .allTerminals:
    return context("111999m111999p11s", winning: .bamboo1)
  case .littleFourWinds:
    return context(
      "123m", honors: [.north, .north],
      melds: [pung(.east), pung(.south), pung(.west)], winning: .north)
  case .littleThreeDragons:
    return context(
      "123m", honors: [.white, .white],
      melds: [pung(.red), pung(.green), pung(.east)], winning: .white)
  case .allHonors:
    return context(
      "",
      honors: [
        .east, .east, .east, .south, .south, .south, .west, .west, .west,
        .red, .red, .red, .white, .white,
      ],
      winning: .white)
  case .fourConcealedPungs:
    return context("111222333m444p55s", winning: .bamboo5)
  case .pureTerminalChows:
    return context("12312378978955m", winning: .character5)
  case .quadrupleChow:
    return context("12312312312355m", winning: .character5)
  case .fourPureShiftedPungs:
    return context("111222333444m55p", winning: .dot5)
  case .fourPureShiftedChows:
    return context("12323434545677m", winning: .character7)
  case .threeKongs:
    return context(
      "123m55p",
      melds: [kong(.character7), kong(.dot8), kong(.bamboo9, concealed: true)],
      winning: .dot5)
  case .allTerminalsAndHonors:
    return context(
      "111999m11p",
      honors: [.east, .east, .east, .red, .red, .red],
      winning: .dot1)
  case .sevenPairs:
    return context("112233m445566p77s", winning: .bamboo7)
  case .greaterHonorsKnitted:
    return context(
      "147m258p3s",
      honors: [.east, .south, .west, .north, .red, .green, .white],
      winning: .bamboo3)
  case .allEvenPungs:
    return context("222444m666p888s22p", winning: .dot2)
  case .fullFlush:
    return context("12345678923455m", winning: .character5)
  case .pureTripleChow:
    return context("123123123m789p55s", winning: .bamboo5)
  case .pureShiftedPungs:
    return context("111222333m789p55s", winning: .bamboo5)
  case .upperTiles:
    return context("777888999m777p99s", winning: .bamboo9)
  case .middleTiles:
    return context("444555666m444p55s", winning: .bamboo5)
  case .lowerTiles:
    return context("111222333m111p22s", winning: .bamboo2)
  case .pureStraight:
    return context("123456789m123p55s", winning: .bamboo5)
  case .threeSuitedTerminalChows:
    return context("123789m123789p55s", winning: .bamboo5)
  case .pureShiftedChows:
    return context("123234345m789p55s", winning: .bamboo5)
  case .allFives:
    return context("345456m567p555s55p", winning: .dot5)
  case .triplePung:
    return context("555m555p555s123m77p", winning: .dot7)
  case .threeConcealedPungs:
    return context("111222333m456p55s", winning: .bamboo5)
  case .lesserHonorsKnitted:
    return context(
      "147m258p36s",
      honors: [.east, .south, .west, .north, .red, .green],
      winning: .bamboo6)
  case .knittedStraight:
    return context(
      "147m258p369s55m", melds: [pung(.east)], winning: .character5)
  case .upperFour:
    return context("678789m678p999s66p", winning: .dot6)
  case .lowerFour:
    return context("123234m123p444s22p", winning: .dot2)
  case .bigThreeWinds:
    return context(
      "123m55p", melds: [pung(.east), pung(.south), pung(.west)], winning: .dot5)
  case .mixedStraight:
    return context("123m456p789s234m55p", winning: .dot5)
  case .reversibleTiles:
    return context(
      "123345888p456s", honors: [.white, .white], winning: .white)
  case .mixedTripleChow:
    return context("123m123p123s789m55p", winning: .dot5)
  case .mixedShiftedPungs:
    return context("333m444p555s789m22p", winning: .dot2)
  case .chickenHand:
    return context(
      "789m", honors: [.white, .white],
      melds: [chow("234p"), chow("678s"), pung(.bamboo5)],
      winning: .character9, method: .discard, round: .south)
  case .lastTileDraw:
    return context("111222333m444p55s", winning: .bamboo5, lastWall: true)
  case .lastTileClaim:
    return context(
      "111222333m444p55s", winning: .bamboo5, method: .discard, lastDiscard: true)
  case .outWithReplacement:
    return context("111222333m444p55s", winning: .bamboo5, method: .kongReplacement)
  case .robbingKong:
    return context("111222333m444p55s", winning: .bamboo5, method: .robbingKong)
  case .twoConcealedKongs:
    return context(
      "123m456p55s",
      melds: [kong(.bamboo7, concealed: true), kong(.character9, concealed: true)],
      winning: .bamboo5)
  case .allPungs:
    return context(
      "222p333s444m55p", melds: [pung(.character1)], winning: .dot5)
  case .halfFlush:
    return context(
      "123111789m", honors: [.east, .east, .east, .red, .red], winning: .red)
  case .mixedShiftedChows:
    return context("123m234p345s777m55p", winning: .dot5)
  case .allTypes:
    return context(
      "123m456p789s", honors: [.east, .east, .east, .red, .red], winning: .red)
  case .meldedHand:
    return context(
      "", honors: [.white, .white],
      melds: [chow("123m"), chow("456p"), chow("789s"), pung(.character2)],
      winning: .white, method: .discard)
  case .twoDragonPungs:
    return context(
      "123m456p55s", melds: [pung(.red), pung(.green)], winning: .bamboo5)
  case .outsideHand:
    return context(
      "123789m111p99s", melds: [pung(.east)], winning: .bamboo9)
  case .fullyConcealedHand:
    return context("123m456p789s234m55p", winning: .dot5)
  case .twoMeldedKongs:
    return context(
      "123m456p55s", melds: [kong(.character7), kong(.dot8)], winning: .bamboo5)
  case .lastTile:
    return context(
      "111222333m444p55s", winning: .bamboo5, visible: [.bamboo5: 3])
  case .dragonPung:
    return context(
      "123456m789p55s", melds: [pung(.red)], winning: .bamboo5, method: .discard)
  case .prevalentWind:
    return context(
      "123456m789p55s", melds: [pung(.east)], winning: .bamboo5,
      method: .discard, round: .east)
  case .seatWind:
    return context(
      "123456m789p55s", melds: [pung(.south)], winning: .bamboo5,
      method: .discard, seat: .south, round: .west)
  case .concealedHand:
    return context(
      "123m456p789s234m55p", winning: .character1, method: .discard)
  case .allChows:
    return context("123m456m789p234s55p", winning: .dot5)
  case .tileHog:
    return context("111123m456p789s55p", winning: .dot5)
  case .doublePung:
    return context("555m555p123s789m22p", winning: .dot2)
  case .twoConcealedPungs:
    return context("111222m456p789s55p", winning: .dot5)
  case .concealedKong:
    return context(
      "123m456p789s55p", melds: [kong(.east, concealed: true)], winning: .dot5)
  case .allSimples:
    return context("234m345p456s678m55p", winning: .dot5)
  case .pureDoubleChow:
    return context("123123m456p789s55p", winning: .dot5)
  case .mixedDoubleChow:
    return context("123m123p456s777m55p", winning: .dot5)
  case .shortStraight:
    return context("123456m789p234s55p", winning: .dot5)
  case .twoTerminalChows:
    return context("123789m456p234s55p", winning: .dot5)
  case .pungOfTerminalsOrHonors:
    return context("111m234p567s789p55m", winning: .character5)
  case .meldedKong:
    return context(
      "123m456p789s55p", melds: [kong(.east)], winning: .dot5)
  case .oneVoidedSuit:
    return context("123456m789234p55m", winning: .character5)
  case .noHonors:
    return context("123m456m789p234s55p", winning: .dot5)
  case .edgeWait:
    return context(
      "123m456m789p123s55p", winning: .character3, method: .discard)
  case .closedWait:
    return context(
      "123m456m789p123s55p", winning: .character2, method: .discard)
  case .singleWait:
    return context(
      "123456m789p55s", melds: [pung(.red)], winning: .bamboo5, method: .discard)
  case .selfDraw:
    return context(
      "456m789p234s55p", melds: [chow("123m")], winning: .dot5)
  case .flower:
    return context(
      "456m789p234s55p", melds: [chow("123m")], winning: .dot5, flowers: 1)
  }
}
private func negativeExample(for fan: Fan) -> WinContext {
  switch fan {
  case .mixedStraight:
    return positiveExample(for: .allPungs)
  case .fullyConcealedHand, .selfDraw:
    return context(
      "456m789p234s55p", melds: [chow("123m")], winning: .dot5, method: .discard)
  case .allChows:
    return positiveExample(for: .allPungs)
  case .singleWait:
    return context(
      "123m456p789s234m55p", winning: .character4, method: .discard)
  case .noHonors:
    return context(
      "123456m789p", honors: [.east, .east, .east, .red, .red], winning: .red)
  default:
    return context("123m456p789s234m55p", winning: .dot5)
  }
}
private func kong(_ kind: TileKind, concealed: Bool = false, added: Bool = false) -> Meld {
  let type: MeldType = concealed ? .concealedKong : (added ? .addedKong : .exposedKong)
  return Meld(type: type, tiles: Array(repeating: kind, count: 4))
}
