import Foundation
import Testing

@testable import MahjongAI
@testable import MahjongRules

@Suite("M2 分级电脑对手")
struct MahjongAITests {
  @Test func beginnerIsSeededAndVariesWhileNormalIsStable() {
    let information = fixture("123456m234p678s", honors: [.east, .north])
    let beginner = OpponentProfile.standardOpponents(difficulty: .beginner)[0]
    let normal = OpponentProfile.standardOpponents(difficulty: .normal)[0]

    let beginnerChoices = Set(
      (0..<24).map {
        MahjongAIDecider.chooseDiscard(
          information: information, profile: beginner, decisionSeed: UInt64($0)
        ).chosenTile
      })
    #expect(beginnerChoices.count > 1)

    let first = MahjongAIDecider.chooseDiscard(
      information: information, profile: normal, decisionSeed: 1)
    let second = MahjongAIDecider.chooseDiscard(
      information: information, profile: normal, decisionSeed: 999)
    #expect(first.chosenTile == .north)
    #expect(first.chosenTile == second.chosenTile)
    #expect(first.explanation.contains("牌效"))
  }

  @Test func expertConservativeUsesPublicDiscardAsSafeTile() {
    var discards = Array(repeating: [TileKind](), count: 4)
    discards[2] = [.dot5, .dot1, .dot9]
    var melds = Array(repeating: [Meld](), count: 4)
    melds[2] = [
      pung(.red), pung(.green), pung(.east),
    ]
    let information = fixture(
      "123m456p789s11s",
      honors: [.white, .west, .north],
      discards: discards,
      publicMelds: melds,
      scores: [0, 0, 48, 0]
    )

    let normal = OpponentProfile(
      seat: 1, name: "普通", avatarSystemName: "person", personality: .conservative,
      difficulty: .normal)
    let expert = OpponentProfile(
      seat: 1, name: "高手", avatarSystemName: "person", personality: .conservative,
      difficulty: .expert)

    let normalDecision = MahjongAIDecider.chooseDiscard(
      information: information, profile: normal, decisionSeed: 7)
    let expertDecision = MahjongAIDecider.chooseDiscard(
      information: information, profile: expert, decisionSeed: 7)

    #expect(normalDecision.chosenTile == .north)
    #expect(expertDecision.chosenTile == .dot5)
    #expect(expertDecision.candidates.first?.danger == 0)
    #expect(expertDecision.explanation.contains("安全"))
  }

  @Test func expertBigHandPersonalityKeepsDominantSuit() {
    let information = fixture("123456789m22m45p", honors: [.north])
    let normal = OpponentProfile(
      seat: 3, name: "普通", avatarSystemName: "person", personality: .bigHand,
      difficulty: .normal)
    let expert = OpponentProfile(
      seat: 3, name: "高手", avatarSystemName: "person", personality: .bigHand,
      difficulty: .expert)

    let normalDecision = MahjongAIDecider.chooseDiscard(
      information: information, profile: normal, decisionSeed: 3)
    let expertDecision = MahjongAIDecider.chooseDiscard(
      information: information, profile: expert, decisionSeed: 3)

    #expect(normalDecision.chosenTile == .north)
    #expect(expertDecision.chosenTile.suit == .dots)
    #expect(expertDecision.candidates.first?.fanPlan ?? 0 > 0)
  }

  @Test func personalitiesChangeClaimBehavior() {
    let information = fixture("123456m234p678s", honors: [.east, .north])
    let aggressive = OpponentProfile(
      seat: 1, name: "激进", avatarSystemName: "hare", personality: .aggressive,
      difficulty: .expert)
    let bigHand = OpponentProfile(
      seat: 3, name: "大牌", avatarSystemName: "crown", personality: .bigHand,
      difficulty: .expert)

    let offSuitChow = AIClaimChoice.chow([.dot3, .dot4, .dot5])
    #expect(
      MahjongAIDecider.shouldClaim(
        offSuitChow,
        discardedTile: .dot3,
        information: information,
        profile: aggressive,
        decisionSeed: 4
      ))
    #expect(
      !MahjongAIDecider.shouldClaim(
        offSuitChow,
        discardedTile: .dot3,
        information: information,
        profile: bigHand,
        decisionSeed: 4
      ))
  }

  @Test func profilesExposeNamesAvatarsAndDistinctPersonalities() {
    let profiles = OpponentProfile.standardOpponents(difficulty: .normal)
    #expect(profiles.map(\.name) == ["阿岚", "静川", "墨衡"])
    #expect(Set(profiles.map(\.avatarSystemName)).count == 3)
    #expect(Set(profiles.map { $0.personality.archetype }).count == 3)
  }

  @Test func kongLeavesThePairAndTheTenpaiTile() {
    let pairOnly = kongInformation([
      .character1, .character2, .character3,
      .character4, .character5, .character6,
      .character7, .character8, .character9,
      .dot3,
      .east, .east, .east, .east,
    ])
    #expect(!MahjongAIDecider.shouldDeclareKong(kind: .east, removing: 4, information: pairOnly))

    let spareQuad = kongInformation([
      .character1, .character2, .character3,
      .character4, .character5, .character6,
      .bamboo5, .bamboo5,
      .dot7, .dot8,
      .east, .east, .east, .east,
    ])
    #expect(MahjongAIDecider.shouldDeclareKong(kind: .east, removing: 4, information: spareQuad))

    let tanki = kongInformation(
      [
        .character1, .character2, .character3,
        .dot4, .dot5, .dot6,
        .bamboo7, .bamboo8, .bamboo9,
        .dot9,
        .white,
      ],
      melds: [Meld(type: .pung, tiles: [.red, .red, .red])]
    )
    #expect(!MahjongAIDecider.shouldDeclareKong(kind: .white, removing: 1, information: tanki))

    let spare = kongInformation(
      [
        .character1, .character2, .character3,
        .dot4, .dot5, .dot6,
        .east, .east,
        .bamboo7, .bamboo8,
        .white,
      ],
      melds: [Meld(type: .pung, tiles: [.red, .red, .red])]
    )
    #expect(MahjongAIDecider.shouldDeclareKong(kind: .white, removing: 1, information: spare))

    let hidden = kongInformation([
      .character1, .character2, .character3,
      .character4, .character5, .character6,
      .bamboo5, .bamboo5,
      .dot7, .dot8,
      .east, .east, .east, .east,
    ])
    #expect(
      MahjongAIDecider.shouldDeclareKong(kind: .east, removing: 4, information: hidden)
        == MahjongAIDecider.shouldDeclareKong(kind: .east, removing: 4, information: spareQuad))
  }

  @Test func exposedKongKeepsThePairAndChowUsesEfficiency() {
    let spare = kongInformation([
      .character1, .character2, .character3,
      .character4, .character5, .character6,
      .character7, .character8,
      .dot9, .dot9,
      .east, .east, .east,
    ])
    let aggressive = OpponentProfile.standardOpponents(difficulty: .expert)[0]
    #expect(
      MahjongAIDecider.shouldClaim(
        .exposedKong, discardedTile: .east, information: spare, profile: aggressive,
        decisionSeed: 1))

    let onlyPair = kongInformation([
      .character1, .character2, .character3,
      .character4, .character5, .character6,
      .character7, .character8,
      .dot9,
      .bamboo9,
      .east, .east, .east,
    ])
    #expect(
      !MahjongAIDecider.shouldClaim(
        .exposedKong, discardedTile: .east, information: onlyPair, profile: aggressive,
        decisionSeed: 1))

    let chowHand = kongInformation([
      .character2, .character3, .character3, .character5, .character6,
      .dot1, .dot9, .bamboo1, .bamboo9,
      .south, .north, .white, .green,
    ])
    let chosen = MahjongAIDecider.chooseChow(
      options: [
        [.character2, .character3, .character4],
        [.character3, .character4, .character5],
        [.character4, .character5, .character6],
      ],
      discardedTile: .character4,
      information: chowHand,
      profile: aggressive,
      decisionSeed: 2
    )
    #expect(chosen == [.character4, .character5, .character6])
  }

  @Test func dangerCountsTilesInHandAndIgnoresConcealedKongs() {
    var melds = Array(repeating: [Meld](), count: 4)
    melds[2] = [pung(.red), pung(.green)]
    let holdingThree = AIInformationSet(
      seat: 1,
      ownTiles: [.character5, .character5, .character5, .east],
      ownMelds: [],
      discards: Array(repeating: [], count: 4),
      publicMelds: melds,
      exposedFlowers: Array(repeating: [], count: 4),
      wallRemaining: 40,
      scores: [0, 0, 0, 0],
      roundWind: .east,
      actionNumber: 4
    )
    let holdingOne = AIInformationSet(
      seat: 1,
      ownTiles: [.character5, .east, .south, .west],
      ownMelds: [],
      discards: Array(repeating: [], count: 4),
      publicMelds: melds,
      exposedFlowers: Array(repeating: [], count: 4),
      wallRemaining: 40,
      scores: [0, 0, 0, 0],
      roundWind: .east,
      actionNumber: 4
    )
    let safe = MahjongAIDecider.chooseDiscard(
      information: holdingThree, profile: OpponentProfile.standardOpponents(difficulty: .expert)[1],
      decisionSeed: 1)
    let exposed = MahjongAIDecider.chooseDiscard(
      information: holdingOne, profile: OpponentProfile.standardOpponents(difficulty: .expert)[1],
      decisionSeed: 1)
    #expect(safe.candidates.first { $0.tile == .character5 }?.danger == 0)
    #expect((exposed.candidates.first { $0.tile == .character5 }?.danger ?? 0) > 0)

    var hidden = melds
    hidden[2].append(Meld(type: .concealedKong, tiles: Array(repeating: .east, count: 4)))
    let withHidden = AIInformationSet(
      seat: 1,
      ownTiles: holdingOne.ownTiles,
      ownMelds: [],
      discards: Array(repeating: [], count: 4),
      publicMelds: hidden,
      exposedFlowers: Array(repeating: [], count: 4),
      wallRemaining: 40,
      scores: [0, 0, 0, 0],
      roundWind: .east,
      actionNumber: 4
    )
    #expect(withHidden.visibleTileCounts[.east, default: 0] == 0)
    #expect(withHidden.visibleTileCounts[.east, default: 0] == holdingOne.visibleTileCounts[.east, default: 0])
  }

  @Test func informationSetSerializationContainsNoHiddenState() throws {
    let information = fixture("123456m234p678s", honors: [.east, .north])
    let data = try JSONEncoder().encode(information)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("wallTiles"))
    #expect(!json.contains("opponentHands"))
    #expect(!json.contains("shuffleSeed"))
    #expect(!json.contains("future"))
    #expect(json.contains("ownTiles"))
    #expect(json.contains("wallRemaining"))
  }

  @Test func tenThousandSeededDecisionsAlwaysChooseAHeldTile() {
    let difficulties = AIDifficulty.allCases
    for seed in 0..<10_000 {
      var wall = Wall(seed: UInt64(seed))
      var hand: [TileKind] = []
      while hand.count < 14, let tile = wall.drawReplacingFlowers().tile {
        hand.append(tile.kind)
      }
      let difficulty = difficulties[seed % difficulties.count]
      let profile = OpponentProfile.standardOpponents(difficulty: difficulty)[seed % 3]
      let information = AIInformationSet(
        seat: profile.seat,
        ownTiles: hand,
        ownMelds: [],
        discards: Array(repeating: [], count: 4),
        publicMelds: Array(repeating: [], count: 4),
        exposedFlowers: Array(repeating: [], count: 4),
        wallRemaining: wall.remainingCount,
        scores: [0, 0, 0, 0],
        roundWind: .east,
        actionNumber: seed
      )
      let decision = MahjongAIDecider.chooseDiscard(
        information: information,
        profile: profile,
        decisionSeed: UInt64(seed)
      )
      #expect(hand.contains(decision.chosenTile))
      #expect(decision.candidates.allSatisfy { hand.contains($0.tile) })
      #expect(Set(decision.candidates.map(\.tile)).count == decision.candidates.count)
    }
  }
}
private func kongInformation(_ tiles: [TileKind], melds: [Meld] = []) -> AIInformationSet {
  AIInformationSet(
    seat: 1,
    ownTiles: tiles,
    ownMelds: melds,
    discards: Array(repeating: [], count: 4),
    publicMelds: Array(repeating: [], count: 4),
    exposedFlowers: Array(repeating: [], count: 4),
    wallRemaining: 40,
    scores: [0, 0, 0, 0],
    roundWind: .east,
    actionNumber: 3
  )
}
private func fixture(
  _ notation: String,
  honors: [TileKind] = [],
  discards: [[TileKind]] = Array(repeating: [], count: 4),
  publicMelds: [[Meld]] = Array(repeating: [], count: 4),
  scores: [Int] = [0, 0, 0, 0]
) -> AIInformationSet {
  AIInformationSet(
    seat: 1,
    ownTiles: parseTiles(notation) + honors,
    ownMelds: [],
    discards: discards,
    publicMelds: publicMelds,
    exposedFlowers: Array(repeating: [], count: 4),
    wallRemaining: 70,
    scores: scores,
    roundWind: .east,
    actionNumber: 12
  )
}
private func parseTiles(_ notation: String) -> [TileKind] {
  var result: [TileKind] = []
  var digits: [Int] = []
  for character in notation {
    if let digit = character.wholeNumberValue {
      digits.append(digit)
      continue
    }
    let suit: Suit?
    switch character {
    case "m": suit = .characters
    case "p": suit = .dots
    case "s": suit = .bamboo
    default: suit = nil
    }
    if let suit {
      result += digits.map { TileKind(suit: suit, rank: $0)! }
      digits = []
    }
  }
  return result
}
private func pung(_ tile: TileKind) -> Meld {
  Meld(type: .pung, tiles: [tile, tile, tile])
}
