import Foundation

public struct CosmeticItem: Identifiable, Equatable, Sendable {
  public enum Kind: String, Sendable {
    case table
    case back
    case character
    case music
  }

  public let id: String
  public let kind: Kind
  public let title: String
  public let detail: String
  public let unlocked: Bool
}

public enum CosmeticCatalog {
  public static let starterTable = "table-wood"
  public static let starterBack = "back-basic"
  public static let starterCharacter = "character-alan"
  public static let starterMusic = "music-basic"

  public static func items(career: CareerProgress) -> [CosmeticItem] {
    definitions.map { item in
      CosmeticItem(
        id: item.id, kind: item.kind, title: item.title, detail: item.detail,
        unlocked: item.starter || unlocked(item.id, career: career))
    }
  }

  public static func isUnlocked(_ id: String, career: CareerProgress) -> Bool {
    if definitions.first(where: { $0.id == id })?.starter == true { return true }
    return unlocked(id, career: career)
  }

  private static func unlocked(_ id: String, career: CareerProgress) -> Bool {
    let stars = career.bestStars
    switch id {
    case "table-city":
      return chapterHasStar(2, stars: stars)
    case "character-liefeng":
      return (stars["2-10"] ?? 0) >= 1
    case "table-lake":
      return chapterHasStar(3, stars: stars)
    case "character-jingchuan", "music-calm":
      return (stars["3-10"] ?? 0) >= 1
    case "back-master", "character-moheng", "voice-fans":
      return (stars["4-10"] ?? 0) >= 1
    case "table-final", "character-xuance":
      return (stars["5-10"] ?? 0) >= 1
    default:
      return false
    }
  }

  private static func chapterHasStar(_ chapter: Int, stars: [String: Int]) -> Bool {
    CareerCatalog.levels.contains { $0.chapter == chapter && (stars[$0.id] ?? 0) >= 1 }
  }

  private static let definitions: [(
    id: String, kind: CosmeticItem.Kind, title: String, detail: String, starter: Bool
  )] = [
    ("table-wood", .table, "木纹茶桌", "第一章的桌面。", true),
    ("table-city", .table, "城市夜景", "第二章打出任意一星后解锁。", false),
    ("table-lake", .table, "湖畔桌景", "第三章打出任意一星后解锁。", false),
    ("table-final", .table, "终局桌景", "击败玄策后解锁。", false),
    ("back-basic", .back, "基础牌背", "默认牌背。", true),
    ("back-master", .back, "大师牌背", "击败墨衡后解锁。", false),
    ("character-alan", .character, "阿岚", "速度型，一开始就能用。", true),
    ("character-liefeng", .character, "烈风", "击败烈风后解锁。", false),
    ("character-jingchuan", .character, "静川", "击败静川后解锁。", false),
    ("character-moheng", .character, "墨衡", "击败墨衡后解锁。", false),
    ("character-xuance", .character, "玄策", "击败玄策后解锁。", false),
    ("music-basic", .music, "茶馆曲", "默认装扮。背景音乐是同一条循环，在设置里开关。", true),
    ("music-calm", .music, "湖畔曲", "击败静川后解锁。背景音乐仍是同一条循环，不会另换一首。", false),
    ("voice-fans", .music, "番种短语音", "击败墨衡后，和牌时补报一个番种名。", false),
  ]
}
