import Testing

@testable import MahjongRules

@Suite("和牌结构枚举")
struct WinningAnalyzerTests {
  @Test func enumeratesBasicHandAndRejectsIncompleteHand() {
    let valid = context("123m123p123s789s55p", winning: .dot5)
    let structures = WinningAnalyzer.structures(for: valid)
    #expect(structures.contains { $0.shape == .standard })

    let invalid = context("123m123p123s789s56p", winning: .dot6)
    #expect(WinningAnalyzer.structures(for: invalid).isEmpty)
  }

  @Test func enumeratesEveryStandardDecomposition() {
    let ambiguous = context("11223344556677m", winning: .character7)
    let structures = WinningAnalyzer.structures(for: ambiguous)
    #expect(structures.contains { $0.shape == .sevenPairs })
    #expect(structures.contains { $0.shape == .standard })
    #expect(structures.count >= 4)
  }

  @Test func sevenPairsAllowsFourIdenticalAsTwoPairs() {
    let hand = context("11112233445566m", winning: .character6)
    #expect(WinningAnalyzer.structures(for: hand).contains { $0.shape == .sevenPairs })
  }

  @Test func thirteenOrphansRequiresAllThirteenKinds() {
    let honors: [TileKind] = [.east, .south, .west, .north, .red, .green, .white]
    let hand = context("119m19p19s", honors: honors, winning: .character1)
    #expect(WinningAnalyzer.structures(for: hand).contains { $0.shape == .thirteenOrphans })

    let missing = context("111m19p19s", honors: honors, winning: .character1)
    #expect(!WinningAnalyzer.structures(for: missing).contains { $0.shape == .thirteenOrphans })
  }

  @Test func recognizesGreaterAndLesserHonorsKnitted() {
    let allHonors: [TileKind] = [.east, .south, .west, .north, .red, .green, .white]
    let greater = context("147m258p3s", honors: allHonors, winning: .bamboo3)
    #expect(WinningAnalyzer.structures(for: greater).contains { $0.shape == .greaterHonorsKnitted })

    let sixHonors: [TileKind] = [.east, .south, .west, .north, .red, .green]
    let lesser = context("147m258p36s", honors: sixHonors, winning: .bamboo6)
    #expect(WinningAnalyzer.structures(for: lesser).contains { $0.shape == .lesserHonorsKnitted })
  }

  @Test func recognizesKnittedStraightWithMeldAndPair() {
    let hand = context(
      "147m258p369s55m",
      melds: [pung(.east)],
      winning: .character5
    )
    let structures = WinningAnalyzer.structures(for: hand)
    #expect(structures.contains { $0.shape == .knittedStraight })
  }

  @Test func validatesPhysicalMultiplicityAndConcealedCount() {
    let fiveEast = context("", honors: [.east, .east, .east, .east, .east], winning: .east)
    #expect(WinningAnalyzer.structures(for: fiveEast).isEmpty)

    let wrongCount = context("123m123p123s55p", winning: .dot5)
    #expect(WinningAnalyzer.structures(for: wrongCount).isEmpty)
  }
}
