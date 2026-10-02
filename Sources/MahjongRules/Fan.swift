/// Versioned, machine-readable MCR product ruling table.

public enum Fan: Int, CaseIterable, Codable, Sendable {
  case bigFourWinds = 1
  case bigThreeDragons, allGreen, nineGates, fourKongs, sevenShiftedPairs, thirteenOrphans
  case allTerminals, littleFourWinds, littleThreeDragons, allHonors, fourConcealedPungs,
    pureTerminalChows
  case quadrupleChow, fourPureShiftedPungs
  case fourPureShiftedChows, threeKongs, allTerminalsAndHonors
  case sevenPairs, greaterHonorsKnitted, allEvenPungs, fullFlush, pureTripleChow, pureShiftedPungs,
    upperTiles, middleTiles, lowerTiles
  case pureStraight, threeSuitedTerminalChows, pureShiftedChows, allFives, triplePung,
    threeConcealedPungs
  case lesserHonorsKnitted, knittedStraight, upperFour, lowerFour, bigThreeWinds
  case mixedStraight, reversibleTiles, mixedTripleChow, mixedShiftedPungs, chickenHand,
    lastTileDraw, lastTileClaim, outWithReplacement, robbingKong, twoConcealedKongs
  case allPungs, halfFlush, mixedShiftedChows, allTypes, meldedHand, twoDragonPungs
  case outsideHand, fullyConcealedHand, twoMeldedKongs, lastTile
  case dragonPung, prevalentWind, seatWind, concealedHand, allChows, tileHog, doublePung,
    twoConcealedPungs, concealedKong, allSimples
  case pureDoubleChow, mixedDoubleChow, shortStraight, twoTerminalChows, pungOfTerminalsOrHonors,
    meldedKong, oneVoidedSuit, noHonors, edgeWait, closedWait, singleWait, selfDraw, flower

  public var name: String {
    Self.names[rawValue - 1]
  }

  public var points: Int {
    switch rawValue {
    case 1...7: return 88
    case 8...13: return 64
    case 14...15: return 48
    case 16...18: return 32
    case 19...27: return 24
    case 28...33: return 16
    case 34...38: return 12
    case 39...48: return 8
    case 49...54: return 6
    case 55...58: return 4
    case 59...68: return 2
    default: return 1
    }
  }

  private static let names = [
    "大四喜", "大三元", "绿一色", "九莲宝灯", "四杠", "连七对", "十三幺",
    "清幺九", "小四喜", "小三元", "字一色", "四暗刻", "一色双龙会",
    "一色四同顺", "一色四节高",
    "一色四步高", "三杠", "混幺九",
    "七对", "七星不靠", "全双刻", "清一色", "一色三同顺", "一色三节高", "全大", "全中", "全小",
    "清龙", "三色双龙会", "一色三步高", "全带五", "三同刻", "三暗刻",
    "全不靠", "组合龙", "全大于五", "全小于五", "三风刻",
    "花龙", "推不倒", "三色三同顺", "三色三节高", "无番和", "妙手回春", "海底捞月", "杠上开花", "抢杠和", "双暗杠",
    "碰碰和", "混一色", "三色三步高", "五门齐", "全求人", "双箭刻",
    "全带幺", "不求人", "双明杠", "和绝张",
    "箭刻", "圈风刻", "门风刻", "门前清", "平和", "四归一", "双同刻", "双暗刻", "暗杠", "断幺",
    "一般高", "喜相逢", "连六", "老少副", "幺九刻", "明杠", "缺一门", "无字", "边张", "坎张", "单钓将", "自摸", "花牌",
  ]
}
public struct FanDefinition: Codable, Sendable {
  public let fan: Fan
  public let points: Int
  public let excludedFans: Set<Fan>
  public let repeatable: Bool
  public let requiresEventEvidence: Bool
  public let explanationTemplate: String

  public init(
    fan: Fan,
    excludedFans: Set<Fan>,
    repeatable: Bool = false,
    requiresEventEvidence: Bool = false
  ) {
    self.fan = fan
    points = fan.points
    self.excludedFans = excludedFans
    self.repeatable = repeatable
    self.requiresEventEvidence = requiresEventEvidence
    explanationTemplate = "因牌型或事件满足「\(fan.name)」，计 \(fan.points) 番"
  }
}
public enum MCRRuleBook {
  public static let version = "MCR-2006-product-1"

  public static let definitions: [Fan: FanDefinition] = Dictionary(
    uniqueKeysWithValues: Fan.allCases.map { fan in
      let repeatable: Set<Fan> = [
        .tileHog, .pureDoubleChow, .mixedDoubleChow, .shortStraight,
        .twoTerminalChows, .pungOfTerminalsOrHonors, .meldedKong, .flower,
      ]
      let event: Set<Fan> = [
        .lastTileDraw, .lastTileClaim, .outWithReplacement, .robbingKong,
        .lastTile, .edgeWait, .closedWait, .singleWait, .selfDraw, .flower,
      ]
      return (
        fan,
        FanDefinition(
          fan: fan,
          excludedFans: exclusions[fan] ?? [],
          repeatable: repeatable.contains(fan),
          requiresEventEvidence: event.contains(fan)
        )
      )
    }
  )

  /// "Not counted" implications. Entries are applied transitively.
  public static let exclusions: [Fan: Set<Fan>] = [
    .bigFourWinds: [
      .littleFourWinds, .bigThreeWinds, .prevalentWind, .seatWind, .pungOfTerminalsOrHonors,
    ],
    .bigThreeDragons: [.littleThreeDragons, .twoDragonPungs, .dragonPung],
    .allGreen: [.halfFlush],
    .nineGates: [
      .fullFlush, .fullyConcealedHand, .concealedHand, .twoConcealedPungs, .pungOfTerminalsOrHonors,
      .singleWait,
    ],
    .fourKongs: [
      .threeKongs, .twoConcealedKongs, .twoMeldedKongs, .concealedKong, .meldedKong, .singleWait,
    ],
    .sevenShiftedPairs: [
      .sevenPairs, .fullFlush, .fullyConcealedHand, .concealedHand, .singleWait,
    ],
    .thirteenOrphans: [
      .allTerminalsAndHonors, .allTypes, .fullyConcealedHand, .concealedHand, .singleWait,
    ],
    .allTerminals: [
      .allTerminalsAndHonors, .allPungs, .outsideHand, .pungOfTerminalsOrHonors, .noHonors,
    ],
    .littleFourWinds: [.bigThreeWinds, .pungOfTerminalsOrHonors],
    .littleThreeDragons: [.twoDragonPungs, .dragonPung],
    .allHonors: [.allTerminalsAndHonors, .allPungs, .pungOfTerminalsOrHonors, .oneVoidedSuit],
    .fourConcealedPungs: [.threeConcealedPungs, .twoConcealedPungs, .allPungs, .concealedHand],
    .pureTerminalChows: [
      .threeSuitedTerminalChows, .fullFlush, .allChows, .twoTerminalChows, .pureDoubleChow,
      .noHonors,
    ],
    .quadrupleChow: [.pureTripleChow, .pureDoubleChow, .tileHog],
    .fourPureShiftedPungs: [.pureShiftedPungs, .allPungs],
    .fourPureShiftedChows: [.pureShiftedChows, .shortStraight],
    .threeKongs: [.twoConcealedKongs, .twoMeldedKongs, .concealedKong, .meldedKong],
    .allTerminalsAndHonors: [.allPungs, .outsideHand, .pungOfTerminalsOrHonors],
    .sevenPairs: [.concealedHand, .singleWait],
    .greaterHonorsKnitted: [.lesserHonorsKnitted, .allTypes, .concealedHand],
    .allEvenPungs: [.allPungs, .allSimples],
    .fullFlush: [.halfFlush, .oneVoidedSuit, .noHonors],
    .pureTripleChow: [.pureDoubleChow],
    .pureShiftedPungs: [.allPungs],
    .upperTiles: [.upperFour, .noHonors],
    .middleTiles: [.allSimples, .noHonors],
    .lowerTiles: [.lowerFour, .noHonors],
    .pureStraight: [.shortStraight, .twoTerminalChows],
    .threeSuitedTerminalChows: [.mixedDoubleChow, .twoTerminalChows, .allChows, .noHonors],
    .pureShiftedChows: [.shortStraight],
    .allFives: [.allSimples],
    .triplePung: [.doublePung],
    .threeConcealedPungs: [.twoConcealedPungs],
    .lesserHonorsKnitted: [.concealedHand],
    .knittedStraight: [],
    .upperFour: [.noHonors],
    .lowerFour: [.noHonors],
    .bigThreeWinds: [.pungOfTerminalsOrHonors],
    .mixedStraight: [.mixedDoubleChow],
    .reversibleTiles: [.oneVoidedSuit],
    .mixedTripleChow: [.mixedDoubleChow],
    .mixedShiftedPungs: [.doublePung],
    .chickenHand: [],
    .lastTileDraw: [.selfDraw],
    .lastTileClaim: [],
    .outWithReplacement: [.selfDraw],
    .robbingKong: [.lastTile],
    .twoConcealedKongs: [.twoConcealedPungs, .concealedKong],
    .allPungs: [.allChows],
    .halfFlush: [.oneVoidedSuit],
    .mixedShiftedChows: [],
    .allTypes: [],
    .meldedHand: [.singleWait],
    .twoDragonPungs: [.dragonPung],
    .outsideHand: [],
    .fullyConcealedHand: [.concealedHand, .selfDraw],
    .twoMeldedKongs: [.meldedKong],
    .lastTile: [],
    .dragonPung: [],
    .prevalentWind: [.pungOfTerminalsOrHonors],
    .seatWind: [.pungOfTerminalsOrHonors],
    .concealedHand: [],
    .allChows: [.pungOfTerminalsOrHonors],
    .tileHog: [],
    .doublePung: [],
    .twoConcealedPungs: [],
    .concealedKong: [],
    .allSimples: [.noHonors],
    .pureDoubleChow: [],
    .mixedDoubleChow: [],
    .shortStraight: [],
    .twoTerminalChows: [],
    .pungOfTerminalsOrHonors: [],
    .meldedKong: [],
    .oneVoidedSuit: [],
    .noHonors: [],
    .edgeWait: [],
    .closedWait: [],
    .singleWait: [],
    .selfDraw: [],
    .flower: [],
  ]
}
public struct FanAward: Hashable, Codable, Sendable {
  public let fan: Fan
  public let count: Int
  public let points: Int
  public let evidence: [String]

  public init(fan: Fan, count: Int = 1, evidence: [String] = []) {
    self.fan = fan
    self.count = count
    points = fan.points * count
    self.evidence = evidence
  }
}
public struct ExcludedFan: Hashable, Codable, Sendable {
  public let fan: Fan
  public let excludedBy: Fan
}
public struct ScoreResult: Hashable, Codable, Sendable {
  public let structure: WinningStructure
  public let awards: [FanAward]
  public let excluded: [ExcludedFan]
  public let nonFlowerPoints: Int
  public let flowerPoints: Int
  public let totalPoints: Int
  public let isLegalWin: Bool
  public let ruleVersion: String
}
