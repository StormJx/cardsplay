import MahjongAI
import MahjongRules

public enum StarCondition: String, Codable, Sendable {
  case win
  case selfDraw
  case noDealIn
  case concealedWin
  case minFan16
  case minFan24
  case anyMeld
  case anyKong
  case concealedKong
  case basicFan
  case sevenPairs
  case honorsKnitted
  case knittedStraight

  public var title: String {
    switch self {
    case .win: return "和牌"
    case .selfDraw: return "自摸"
    case .noDealIn: return "不点炮"
    case .concealedWin: return "门前和牌"
    case .minFan16: return "至少 16 番"
    case .minFan24: return "至少 24 番"
    case .anyMeld: return "有一次吃碰或明杠"
    case .anyKong: return "有一次杠"
    case .concealedKong: return "有一次暗杠"
    case .basicFan: return "含平和、断幺、缺一门或无字"
    case .sevenPairs: return "以七对和牌"
    case .honorsKnitted: return "以全不靠和牌"
    case .knittedStraight: return "以组合龙和牌"
    }
  }
}

public enum CareerPuzzle: String, Codable, Sendable {
  case sevenPairs
  case honorsKnitted
  case knittedStraight
}

public struct HandOutcome: Equatable, Sendable {
  public let humanWon: Bool
  public let selfDrawn: Bool
  public let dealtIn: Bool
  public let drawn: Bool
  public let nonFlowerPoints: Int
  public let awards: [Fan]
  public let exposedMelds: Int
  public let kongs: Int
  public let concealedKongs: Int

  public init(
    humanWon: Bool,
    selfDrawn: Bool,
    dealtIn: Bool,
    drawn: Bool,
    nonFlowerPoints: Int,
    awards: [Fan],
    exposedMelds: Int,
    kongs: Int,
    concealedKongs: Int
  ) {
    self.humanWon = humanWon
    self.selfDrawn = selfDrawn
    self.dealtIn = dealtIn
    self.drawn = drawn
    self.nonFlowerPoints = nonFlowerPoints
    self.awards = awards
    self.exposedMelds = exposedMelds
    self.kongs = kongs
    self.concealedKongs = concealedKongs
  }
}

public enum CareerTable: Equatable, Sendable {
  case single(dealer: Int)
  case eastRound(initialDealer: Int)
  case fullMatch(initialDealer: Int)

  public var handCount: Int {
    switch self {
    case .single: return 1
    case .eastRound: return EastRound.handCount
    case .fullMatch: return FullMatch.handCount
    }
  }

  public var initialDealer: Int {
    switch self {
    case .single(let dealer), .eastRound(let dealer), .fullMatch(let dealer):
      return ((dealer % 4) + 4) % 4
    }
  }

  public var rotates: Bool {
    if case .single = self { return false }
    return true
  }

  public var isEastRound: Bool {
    if case .eastRound = self { return true }
    return false
  }

  public func isFinal(_ handIndex: Int) -> Bool {
    handIndex >= handCount - 1
  }
}

public struct CareerLevel: Identifiable, Sendable {
  public let id: String
  public let chapter: Int
  public let index: Int
  public let title: String
  public let briefing: String
  public let difficulty: AIDifficulty
  public let playable: Bool
  public let isBoss: Bool
  public let star1: StarCondition
  public let star2: StarCondition
  public let star3: StarCondition
  public let puzzle: CareerPuzzle?
  public let table: CareerTable

  public init(
    id: String,
    chapter: Int,
    index: Int,
    title: String,
    briefing: String,
    difficulty: AIDifficulty,
    playable: Bool,
    isBoss: Bool,
    star1: StarCondition,
    star2: StarCondition,
    star3: StarCondition,
    puzzle: CareerPuzzle? = nil,
    table: CareerTable = .single(dealer: 0)
  ) {
    self.id = id
    self.chapter = chapter
    self.index = index
    self.title = title
    self.briefing = briefing
    self.difficulty = difficulty
    self.playable = playable
    self.isBoss = isBoss
    self.star1 = star1
    self.star2 = star2
    self.star3 = star3
    self.puzzle = puzzle
    self.table = table
  }

  public var starTitles: [String] { [star1.title, star2.title, star3.title] }
}

public struct CareerChapter: Identifiable, Sendable {
  public let number: Int
  public let title: String
  public let theme: String
  public let levels: [CareerLevel]

  public var id: Int { number }
}

public struct CareerProgress: Codable, Sendable {
  public var bestStars: [String: Int]

  public init(bestStars: [String: Int] = [:]) {
    self.bestStars = bestStars
  }
}

public struct CareerStarLine: Equatable, Sendable {
  public let index: Int
  public let title: String
  public let met: Bool

  public init(index: Int, title: String, met: Bool) {
    self.index = index
    self.title = title
    self.met = met
  }
}

public enum CareerGrader {
  public static func stars(for level: CareerLevel, outcome: HandOutcome) -> Int {
    let met = [level.star1, level.star2, level.star3].map { conditionMet($0, outcome) }
    guard met[0] else { return 0 }
    return met.filter { $0 }.count
  }

  public static func starLines(for level: CareerLevel, outcome: HandOutcome) -> [CareerStarLine] {
    [level.star1, level.star2, level.star3].enumerated().map { offset, condition in
      CareerStarLine(
        index: offset + 1,
        title: condition.title,
        met: conditionMet(condition, outcome)
      )
    }
  }

  public static func missingSummary(for level: CareerLevel, outcome: HandOutcome) -> String {
    let missing = starLines(for: level, outcome: outcome).filter { !$0.met }
    if missing.isEmpty { return "三星都达成" }
    return "缺的是" + missing.map { "第\($0.index)星：\($0.title)" }.joined(separator: "、")
  }

  public static func hint(for level: CareerLevel, outcome: HandOutcome) -> String {
    let earned = stars(for: level, outcome: outcome)
    if earned >= 1 { return "本关 \(earned) 星" }
    return "未通关：第 1 星需要\(level.star1.title)"
  }

  private static func conditionMet(_ condition: StarCondition, _ outcome: HandOutcome) -> Bool {
    switch condition {
    case .win:
      return outcome.humanWon
    case .selfDraw:
      return outcome.selfDrawn
    case .noDealIn:
      return !outcome.dealtIn
    case .concealedWin:
      return outcome.humanWon && outcome.exposedMelds == 0
    case .minFan16:
      return outcome.humanWon && outcome.nonFlowerPoints >= 16
    case .minFan24:
      return outcome.humanWon && outcome.nonFlowerPoints >= 24
    case .anyMeld:
      return outcome.exposedMelds > 0
    case .anyKong:
      return outcome.kongs > 0
    case .concealedKong:
      return outcome.concealedKongs > 0
    case .basicFan:
      let basic: Set<Fan> = [.allChows, .allSimples, .oneVoidedSuit, .noHonors]
      return outcome.humanWon && outcome.awards.contains { basic.contains($0) }
    case .sevenPairs:
      return outcome.humanWon && outcome.awards.contains(.sevenPairs)
    case .honorsKnitted:
      return outcome.humanWon && outcome.awards.contains(.lesserHonorsKnitted)
    case .knittedStraight:
      return outcome.humanWon && outcome.awards.contains(.knittedStraight)
    }
  }
}

public enum CareerCatalog {
  public static let chapters: [CareerChapter] = [
    chapterOne(),
    playableChapter(
      number: 2, title: "城市牌社", theme: "牌效、有效牌、常见 8–16 番",
      rows: chapterTwoRows),
    playableChapter(
      number: 3, title: "湖畔邀请赛", theme: "已见牌、防守、攻守转换",
      rows: chapterThreeRows),
    playableChapter(
      number: 4, title: "国标大师赛", theme: "复合番、番种排斥、特殊牌型",
      rows: chapterFourRows),
    playableChapter(
      number: 5, title: "四风终局", theme: "分数战略、读牌、综合决策",
      rows: chapterFiveRows),
  ]

  public static var levels: [CareerLevel] { chapters.flatMap(\.levels) }

  public static func level(id: String) -> CareerLevel? {
    levels.first { $0.id == id }
  }

  public static func nextPlayable(after id: String) -> CareerLevel? {
    guard let start = levels.firstIndex(where: { $0.id == id }) else { return nil }
    return levels.dropFirst(start + 1).first(where: \.playable)
  }

  public static func chapterCleared(_ number: Int, stars: [String: Int], minimum: Int) -> Bool {
    guard let chapter = chapters.first(where: { $0.number == number }) else { return false }
    return chapter.levels.allSatisfy { (stars[$0.id] ?? 0) >= minimum }
  }

  public static func allBossesCleared(_ stars: [String: Int]) -> Bool {
    levels.filter(\.isBoss).allSatisfy { (stars[$0.id] ?? 0) >= 1 }
  }

  public static func allLevels(atLeast minimum: Int, stars: [String: Int]) -> Bool {
    levels.allSatisfy { (stars[$0.id] ?? 0) >= minimum }
  }

  private static func chapterOne() -> CareerChapter {
    let rows: [(String, String, StarCondition, StarCondition, StarCondition)] = [
      ("学会摸打", "和出任意合法牌型。第 2 星自摸，第 3 星至少 16 番。", .win, .selfDraw, .minFan16),
      ("八番起和", "不够 8 番不能和。和牌后冲击更高番。", .win, .minFan16, .minFan24),
      ("自摸一局", "第 1 星和牌，第 2 星必须自摸。", .win, .selfDraw, .minFan16),
      ("不点炮", "这一盘不要放铳。和牌或流局都可以拿第 1 星。", .noDealIn, .win, .selfDraw),
      ("门前清", "不吃、不碰、不明杠，再和牌。", .win, .concealedWin, .minFan16),
      ("基础番", "和牌时带上平和、断幺、缺一门或无字之一。", .win, .basicFan, .minFan24),
      ("鸣牌之后", "先完成一次吃、碰或明杠，再争取和牌。", .win, .anyMeld, .minFan16),
      ("杠一张", "这一盘声明过杠，并且和牌。", .win, .anyKong, .concealedKong),
      ("番数挑战", "和牌后看非花番能不能到 16、24。", .win, .minFan16, .minFan24),
      ("主事阿岚", "下家是速度型阿岚。和牌通关，自摸和 16 番是后两星。", .win, .selfDraw, .minFan16),
    ]
    let levels = rows.enumerated().map { offset, row in
      CareerLevel(
        id: String(format: "1-%02d", offset + 1),
        chapter: 1,
        index: offset + 1,
        title: row.0,
        briefing: row.1,
        difficulty: .beginner,
        playable: true,
        isBoss: offset == 9,
        star1: row.2,
        star2: row.3,
        star3: row.4
      )
    }
    return CareerChapter(
      number: 1, title: "巷口茶馆", theme: "摸打、吃碰杠、8 番起和、基础番种", levels: levels)
  }

  private typealias LevelRow = (
    String, String, AIDifficulty, StarCondition, StarCondition, StarCondition
  )

  private static func playableChapter(
    number: Int,
    title: String,
    theme: String,
    rows: [LevelRow]
  ) -> CareerChapter {
    let levels = rows.enumerated().map { offset, row in
      CareerLevel(
        id: String(format: "%d-%02d", number, offset + 1),
        chapter: number,
        index: offset + 1,
        title: row.0,
        briefing: row.1,
        difficulty: row.2,
        playable: true,
        isBoss: offset == 9,
        star1: row.3,
        star2: row.4,
        star3: row.5,
        puzzle: Self.puzzle(chapter: number, index: offset + 1),
        table: Self.table(chapter: number, index: offset + 1)
      )
    }
    return CareerChapter(number: number, title: title, theme: theme, levels: levels)
  }

  private static let chapterTwoRows: [LevelRow] = [
    ("有效牌", "和牌通关。第 2 星要带平和、断幺、缺一门或无字；第 3 星至少 16 番。", .beginner, .win, .basicFan, .minFan16),
    ("搭子取舍", "和牌通关。不吃不碰再和拿第 2 星，同时带上一个基础番拿第 3 星。", .beginner, .win, .concealedWin, .basicFan),
    ("八到十六番", "和牌通关。非花番到 16 拿第 2 星，到 24 拿第 3 星。", .beginner, .win, .minFan16, .minFan24),
    ("清一色路线", "可以往一门花色上靠。和牌通关；吃、碰或明杠一次拿第 2 星，16 番拿第 3 星。", .beginner, .win, .anyMeld, .minFan16),
    ("碰碰和路线", "和牌通关。先鸣一次牌拿第 2 星，这一盘杠过拿第 3 星。", .beginner, .win, .anyMeld, .anyKong),
    ("先手与速度", "和牌通关。自摸拿第 2 星，至少 16 番拿第 3 星。", .normal, .win, .selfDraw, .minFan16),
    ("见牌修正", "看过的牌会改有效张。和牌通关，基础番第 2 星，16 番第 3 星。", .normal, .win, .basicFan, .minFan16),
    ("番路选择", "选定一条番路再和。16 番第 2 星，24 番第 3 星。", .normal, .win, .minFan16, .minFan24),
    ("城市积分", "和牌通关。16 番第 2 星，自摸第 3 星。", .normal, .win, .minFan16, .selfDraw),
    ("烈风", "下家打得很冲。和牌通关，自摸拿第 2 星，16 番拿第 3 星。", .normal, .win, .selfDraw, .minFan16),
  ]

  private static let chapterThreeRows: [LevelRow] = [
    ("已见牌", "用已经出现的牌修正听张。和牌通关，基础番第 2 星，16 番第 3 星。", .normal, .win, .basicFan, .minFan16),
    ("危险度", "不放铳就过关。和牌第 2 星，自摸第 3 星。", .normal, .noDealIn, .win, .selfDraw),
    ("安全牌", "先保证不点炮。和牌第 2 星，门前和牌第 3 星。", .normal, .noDealIn, .win, .concealedWin),
    ("攻守转换", "能和就和。和牌通关，自摸第 2 星，16 番第 3 星。", .normal, .win, .selfDraw, .minFan16),
    ("守住领先", "不点炮即过关。和牌第 2 星，16 番第 3 星。", .normal, .noDealIn, .win, .minFan16),
    ("少点炮", "这一盘不要放铳。和牌第 2 星，自摸第 3 星。", .normal, .noDealIn, .win, .selfDraw),
    ("听张判断", "和牌通关。自摸第 2 星，带基础番第 3 星。", .normal, .win, .selfDraw, .basicFan),
    ("副露取舍", "鸣牌要算进番。和牌通关，吃碰或明杠一次拿第 2 星，16 番第 3 星。", .normal, .win, .anyMeld, .minFan16),
    ("湖畔积分", "和牌后冲番。16 番第 2 星，24 番第 3 星。", .normal, .win, .minFan16, .minFan24),
    ("静川", "对家很稳。不点炮过关，和牌第 2 星，16 番第 3 星。", .normal, .noDealIn, .win, .minFan16),
  ]

  private static let chapterFourRows: [LevelRow] = [
    ("复合番", "和牌通关。非花番到 16 拿第 2 星，到 24 拿第 3 星。", .normal, .win, .minFan16, .minFan24),
    ("不计关系", "和牌时留意番种会不会不计。基础番第 2 星，16 番第 3 星。", .normal, .win, .basicFan, .minFan16),
    ("七对", "固定残局：摸进最后一张就是七对，点「和」通关。自摸拿第 2 星，门前和拿第 3 星。", .normal, .sevenPairs, .selfDraw, .concealedWin),
    ("全不靠", "固定残局：摸进最后一张就是全不靠，点「和」通关。自摸拿第 2 星，门前和拿第 3 星。", .normal, .honorsKnitted, .selfDraw, .concealedWin),
    ("组合龙", "固定残局：摸进最后一张就是组合龙，点「和」通关。自摸拿第 2 星，门前和拿第 3 星。", .normal, .knittedStraight, .selfDraw, .concealedWin),
    ("门前取舍", "可以全程不鸣牌。和牌通关，门前和第 2 星，16 番第 3 星。", .expert, .win, .concealedWin, .minFan16),
    ("高番拆解", "和牌后拆开看番。16 番第 2 星，24 番第 3 星。", .expert, .win, .minFan16, .minFan24),
    ("特殊牌型", "和牌通关。带一个基础番拿第 2 星，24 番拿第 3 星。", .expert, .win, .basicFan, .minFan24),
    ("大师积分", "和牌通关。16 番第 2 星，自摸第 3 星。", .expert, .win, .minFan16, .selfDraw),
    ("墨衡", "对家爱做大牌。和牌通关，门前和第 2 星，24 番第 3 星。", .expert, .win, .concealedWin, .minFan24),
  ]

  private static let chapterFiveRows: [LevelRow] = [
    ("分数战略", "打满东风圈四盘，分数累计。和牌通关，16 番第 2 星，24 番第 3 星。", .expert, .win, .minFan16, .minFan24),
    ("读公开牌", "按桌面公开牌决定攻守。这一盘你不是东家。和牌通关，基础番第 2 星，16 番第 3 星。", .expert, .win, .basicFan, .minFan16),
    ("落后追分", "打满东风圈，用后面的盘追分。和牌通关，16 番第 2 星，24 番第 3 星。", .expert, .win, .minFan16, .minFan24),
    ("领先少放铳", "不点炮即过关。这一盘你不是东家。和牌第 2 星，自摸第 3 星。", .expert, .noDealIn, .win, .selfDraw),
    ("圈风门风", "打满东风圈。圈风保持东，门风随庄家轮换。和牌通关，基础番第 2 星，16 番第 3 星。", .expert, .win, .basicFan, .minFan16),
    ("多盘累计", "打满东风圈，四盘分数加在一起。和牌通关，16 番第 2 星，自摸第 3 星。", .expert, .win, .minFan16, .selfDraw),
    ("关键弃张", "先保证不放铳。这一盘你不是东家。和牌第 2 星，16 番第 3 星。", .expert, .noDealIn, .win, .minFan16),
    ("终局选择", "打满东风圈再看最后一盘。和牌通关，自摸第 2 星，16 番第 3 星。", .expert, .win, .selfDraw, .minFan16),
    ("四风预赛", "打完整十六盘，东南西北圈都会轮到。和牌通关，16 番第 2 星，24 番第 3 星。", .expert, .win, .minFan16, .minFan24),
    ("玄策", "综合型对手，打完整十六盘。和牌通关，自摸第 2 星，24 番第 3 星。", .expert, .win, .selfDraw, .minFan24),
  ]

  private static func table(chapter: Int, index: Int) -> CareerTable {
    if chapter == 1 { return .single(dealer: 0) }
    if chapter == 4, (3...5).contains(index) { return .single(dealer: 0) }
    if chapter == 5 {
      switch index {
      case 1: return .eastRound(initialDealer: 1)
      case 3: return .eastRound(initialDealer: 2)
      case 5: return .eastRound(initialDealer: 1)
      case 6: return .eastRound(initialDealer: 3)
      case 8: return .eastRound(initialDealer: 2)
      case 9: return .fullMatch(initialDealer: 1)
      case 10: return .fullMatch(initialDealer: 2)
      case 2: return .single(dealer: 1)
      case 4: return .single(dealer: 2)
      case 7: return .single(dealer: 3)
      default: return .single(dealer: index % 4)
      }
    }
    return .single(dealer: index % 4)
  }

  private static func puzzle(chapter: Int, index: Int) -> CareerPuzzle? {
    switch (chapter, index) {
    case (4, 3): return .sevenPairs
    case (4, 4): return .honorsKnitted
    case (4, 5): return .knittedStraight
    default: return nil
    }
  }
}
