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
    }
  }
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

public enum CareerGrader {
  public static func stars(for level: CareerLevel, outcome: HandOutcome) -> Int {
    let met = [level.star1, level.star2, level.star3].map { conditionMet($0, outcome) }
    guard met[0] else { return 0 }
    return met.filter { $0 }.count
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
    }
  }
}

public enum CareerCatalog {
  public static let chapters: [CareerChapter] = [
    chapterOne(),
    lockedChapter(
      number: 2, title: "城市牌社", theme: "牌效、有效牌、常见 8–16 番",
      difficulty: .normal,
      titles: ["有效牌", "搭子取舍", "八到十六番", "清一色路线", "碰碰和路线", "先手与速度", "见牌修正", "番路选择", "城市积分", "烈风"]),
    lockedChapter(
      number: 3, title: "湖畔邀请赛", theme: "已见牌、防守、攻守转换",
      difficulty: .normal,
      titles: ["已见牌", "危险度", "安全牌", "攻守转换", "守住领先", "少点炮", "听张判断", "副露取舍", "湖畔积分", "静川"]),
    lockedChapter(
      number: 4, title: "国标大师赛", theme: "复合番、番种排斥、特殊牌型",
      difficulty: .expert,
      titles: ["复合番", "不计关系", "七对", "全不靠", "组合龙", "门前取舍", "高番拆解", "特殊牌型", "大师积分", "墨衡"]),
    lockedChapter(
      number: 5, title: "四风终局", theme: "分数战略、读牌、综合决策",
      difficulty: .expert,
      titles: ["分数战略", "读公开牌", "落后追分", "领先少放铳", "圈风门风", "多盘累计", "关键弃张", "终局选择", "四风预赛", "玄策"]),
  ]

  public static var levels: [CareerLevel] { chapters.flatMap(\.levels) }

  public static func level(id: String) -> CareerLevel? {
    levels.first { $0.id == id }
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

  private static func lockedChapter(
    number: Int,
    title: String,
    theme: String,
    difficulty: AIDifficulty,
    titles: [String]
  ) -> CareerChapter {
    let levels = titles.enumerated().map { offset, name in
      CareerLevel(
        id: String(format: "%d-%02d", number, offset + 1),
        chapter: number,
        index: offset + 1,
        title: name,
        briefing: "\(title)的关卡数据。这一章还不能开打。",
        difficulty: difficulty,
        playable: false,
        isBoss: offset == 9,
        star1: .win,
        star2: .selfDraw,
        star3: .minFan16
      )
    }
    return CareerChapter(number: number, title: title, theme: theme, levels: levels)
  }
}
