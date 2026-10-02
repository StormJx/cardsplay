import Foundation
import MahjongRules

public struct Achievement: Identifiable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let detail: String
  public let category: String
  public let unlocked: Bool
}

public enum AchievementBook {
  public static func evaluate(records: [HandRecord], career: CareerProgress) -> [Achievement] {
    let wins = records.filter(\.humanWon)
    let uniqueFans = Set(wins.flatMap(\.awardFans))
    let definitions: [(String, String, String, String, Bool)] = [
      ("first-self-draw", "第一次自摸", "第一次以自摸或杠上开花和牌。", "规则探索",
        wins.contains(where: \.selfDrawn)),
      ("first-rob-kong", "第一次抢杠和", "和出别人补杠的牌。", "规则探索",
        wins.contains { $0.winMethod == .robbingKong }),
      ("first-kong-flower", "第一次杠上开花", "杠后补牌并自摸和牌。", "规则探索",
        wins.contains { $0.winMethod == .kongReplacement }),
      ("fans-10", "番种入门", "自己和出过 10 种不同番。", "规则探索", uniqueFans.count >= 10),
      ("fans-40", "番种进阶", "自己和出过 40 种不同番。", "规则探索", uniqueFans.count >= 40),
      ("fans-81", "八十一番", "81 种番都至少和出过一次。", "规则探索", uniqueFans.count >= 81),
      ("hand-24", "二十四番", "单手达到 24 番。", "技术表现",
        wins.contains { $0.fanPoints >= 24 }),
      ("hand-48", "四十八番", "单手达到 48 番。", "技术表现",
        wins.contains { $0.fanPoints >= 48 }),
      ("hand-88", "八十八番", "单手达到 88 番。", "技术表现",
        wins.contains { $0.fanPoints >= 88 }),
      ("no-deal-in-3", "连续三盘不点炮", "连续三盘都不是由你放铳。", "技术表现",
        dealInStreak(records) >= 3),
      ("chapter-1-clear", "巷口茶馆通关", "第一章十关都至少一星。", "生涯挑战",
        CareerCatalog.chapterCleared(1, stars: career.bestStars, minimum: 1)),
      ("chapter-1-perfect", "茶馆全星", "第一章十关都是三星。", "生涯挑战",
        CareerCatalog.chapterCleared(1, stars: career.bestStars, minimum: 3)),
      ("all-bosses", "击败全部主事", "五章 Boss 都至少一星。", "生涯挑战",
        CareerCatalog.allBossesCleared(career.bestStars)),
      ("all-three-stars", "五十关全星", "五十关都是三星。", "生涯挑战",
        CareerCatalog.allLevels(atLeast: 3, stars: career.bestStars)),
    ]
    return definitions.map { item in
      Achievement(
        id: item.0, title: item.1, detail: item.2, category: item.3, unlocked: item.4)
    }
  }

  private static func dealInStreak(_ records: [HandRecord]) -> Int {
    var best = 0
    var current = 0
    for record in records.sorted(by: { $0.playedAt < $1.playedAt }) {
      if record.dealtIn {
        current = 0
      } else {
        current += 1
        best = max(best, current)
      }
    }
    return best
  }
}
