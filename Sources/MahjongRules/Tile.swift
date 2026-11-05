/// A logical Mahjong tile. Raw values are stable and form the rules serialization format.

/// A physical tile. `copy` distinguishes the four copies of normal tiles.

public enum Suit: Int, CaseIterable, Codable, Sendable {
  case characters, dots, bamboo
}
public enum Wind: Int, CaseIterable, Codable, Sendable {
  case east, south, west, north
}
public enum Dragon: Int, CaseIterable, Codable, Sendable {
  case red, green, white
}
public enum Flower: Int, CaseIterable, Codable, Sendable {
  case spring, summer, autumn, winter, plum, orchid, bamboo, chrysanthemum
}
public enum TileKind: Int, CaseIterable, Codable, Comparable, Sendable {
  case character1, character2, character3, character4, character5
  case character6, character7, character8, character9
  case dot1, dot2, dot3, dot4, dot5, dot6, dot7, dot8, dot9
  case bamboo1, bamboo2, bamboo3, bamboo4, bamboo5
  case bamboo6, bamboo7, bamboo8, bamboo9
  case east, south, west, north, red, green, white
  case spring, summer, autumn, winter, plum, orchid, flowerBamboo, chrysanthemum

  public static func < (lhs: TileKind, rhs: TileKind) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public init?(suit: Suit, rank: Int) {
    guard (1...9).contains(rank) else { return nil }
    self.init(rawValue: suit.rawValue * 9 + rank - 1)
  }

  public init(wind: Wind) {
    self.init(rawValue: 27 + wind.rawValue)!
  }

  public init(dragon: Dragon) {
    self.init(rawValue: 31 + dragon.rawValue)!
  }

  public init(flower: Flower) {
    self.init(rawValue: 34 + flower.rawValue)!
  }

  public var suit: Suit? {
    guard rawValue < 27 else { return nil }
    return Suit(rawValue: rawValue / 9)
  }

  public var rank: Int? {
    guard rawValue < 27 else { return nil }
    return rawValue % 9 + 1
  }

  public var wind: Wind? {
    guard (27...30).contains(rawValue) else { return nil }
    return Wind(rawValue: rawValue - 27)
  }

  public var dragon: Dragon? {
    guard (31...33).contains(rawValue) else { return nil }
    return Dragon(rawValue: rawValue - 31)
  }

  public var flower: Flower? {
    guard rawValue >= 34 else { return nil }
    return Flower(rawValue: rawValue - 34)
  }

  public var isSuited: Bool { suit != nil }
  public var isHonor: Bool { wind != nil || dragon != nil }
  public var isFlower: Bool { flower != nil }
  public var isTerminal: Bool { rank == 1 || rank == 9 }
  public var isTerminalOrHonor: Bool { isTerminal || isHonor }
  public var isSimple: Bool {
    guard let rank else { return false }
    return (2...8).contains(rank)
  }

  public var spokenName: String {
    if let suit, let rank {
      return "\(rank)\(["万", "筒", "条"][suit.rawValue])"
    }
    if let wind { return ["东", "南", "西", "北"][wind.rawValue] }
    if let dragon { return ["中", "发", "白"][dragon.rawValue] }
    return "花"
  }

  public var shortName: String {
    if let suit, let rank {
      return "\(rank)\(["m", "p", "s"][suit.rawValue])"
    }
    if let wind { return ["E", "S", "W", "N"][wind.rawValue] }
    if let dragon { return ["R", "G", "Wh"][dragon.rawValue] }
    return ["Sp", "Su", "Au", "Wi", "Pl", "Or", "Ba", "Ch"][flower!.rawValue]
  }
}
public struct Tile: Hashable, Codable, Sendable {
  public let kind: TileKind
  public let copy: Int

  public init(kind: TileKind, copy: Int) {
    precondition(copy >= 0 && copy < (kind.isFlower ? 1 : 4))
    self.kind = kind
    self.copy = copy
  }
}
public enum TileSet {
  public static let all: [Tile] = TileKind.allCases.flatMap { kind in
    (0..<(kind.isFlower ? 1 : 4)).map { Tile(kind: kind, copy: $0) }
  }

  public static let normalKinds = TileKind.allCases.filter { !$0.isFlower }
  public static let orphanKinds = TileKind.allCases.filter {
    !$0.isFlower && $0.isTerminalOrHonor
  }

  public static func validateCounts(_ kinds: [TileKind], allowFlowers: Bool = false) -> Bool {
    var counts: [TileKind: Int] = [:]
    for kind in kinds {
      if kind.isFlower && !allowFlowers { return false }
      counts[kind, default: 0] += 1
      if counts[kind]! > (kind.isFlower ? 1 : 4) { return false }
    }
    return true
  }
}
extension Array where Element == TileKind {
  public var sortedTiles: [TileKind] { sorted() }

  public var counts: [TileKind: Int] {
    reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }
}
