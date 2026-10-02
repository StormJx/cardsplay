public enum MeldType: String, Codable, Sendable {
  case chow, pung, exposedKong, concealedKong, addedKong
}
public struct Meld: Hashable, Codable, Sendable {
  public let type: MeldType
  public let tiles: [TileKind]
  public let claimedFrom: Int?

  public init(type: MeldType, tiles: [TileKind], claimedFrom: Int? = nil) {
    switch type {
    case .chow:
      precondition(tiles.count == 3)
      let sorted = tiles.sorted()
      precondition(sorted.allSatisfy(\.isSuited))
      precondition(Set(sorted.compactMap(\.suit)).count == 1)
      precondition(sorted[0].rank! + 1 == sorted[1].rank!)
      precondition(sorted[1].rank! + 1 == sorted[2].rank!)
    case .pung:
      precondition(tiles.count == 3 && Set(tiles).count == 1)
    case .exposedKong, .concealedKong, .addedKong:
      precondition(tiles.count == 4 && Set(tiles).count == 1)
    }
    self.type = type
    self.tiles = tiles.sorted()
    self.claimedFrom = claimedFrom
  }

  public var isExposed: Bool {
    type != .concealedKong
  }

  public var isKong: Bool {
    type == .exposedKong || type == .concealedKong || type == .addedKong
  }

  public var kind: TileKind { tiles[0] }
}
public enum WinMethod: String, Codable, Sendable {
  case selfDraw, discard, robbingKong, kongReplacement
}
public struct WinContext: Codable, Sendable {
  /// Concealed normal tiles, including the winning tile.
  public let concealedTiles: [TileKind]
  public let melds: [Meld]
  public let winningTile: TileKind
  public let method: WinMethod
  public let seatWind: Wind
  public let roundWind: Wind
  public let flowerCount: Int
  public let isLastWallTile: Bool
  public let isLastDiscard: Bool
  public let visibleTileCounts: [TileKind: Int]

  public init(
    concealedTiles: [TileKind],
    melds: [Meld] = [],
    winningTile: TileKind,
    method: WinMethod,
    seatWind: Wind = .east,
    roundWind: Wind = .east,
    flowerCount: Int = 0,
    isLastWallTile: Bool = false,
    isLastDiscard: Bool = false,
    visibleTileCounts: [TileKind: Int] = [:]
  ) {
    self.concealedTiles = concealedTiles
    self.melds = melds
    self.winningTile = winningTile
    self.method = method
    self.seatWind = seatWind
    self.roundWind = roundWind
    self.flowerCount = flowerCount
    self.isLastWallTile = isLastWallTile
    self.isLastDiscard = isLastDiscard
    self.visibleTileCounts = visibleTileCounts
  }

  public var allTiles: [TileKind] {
    concealedTiles + melds.flatMap(\.tiles)
  }

  public var hasExposedMeld: Bool {
    melds.contains(where: \.isExposed)
  }

  public var isSelfDrawn: Bool {
    method == .selfDraw || method == .kongReplacement
  }
}
public enum Group: Hashable, Codable, Sendable {
  case chow(suit: Suit, start: Int, exposed: Bool)
  case pung(tile: TileKind, concealed: Bool)
  case kong(tile: TileKind, concealed: Bool)

  public var tiles: [TileKind] {
    switch self {
    case let .chow(suit, start, _):
      return (start...(start + 2)).map { TileKind(suit: suit, rank: $0)! }
    case let .pung(tile, _): return [tile, tile, tile]
    case let .kong(tile, _): return [tile, tile, tile, tile]
    }
  }

  public var isChow: Bool {
    if case .chow = self { return true }
    return false
  }

  public var isPungLike: Bool { !isChow }
  public var isKong: Bool {
    if case .kong = self { return true }
    return false
  }
  public var isConcealedPungLike: Bool {
    switch self {
    case let .pung(_, concealed), let .kong(_, concealed): return concealed
    case .chow: return false
    }
  }
  public var firstTile: TileKind { tiles[0] }
  public var isExposed: Bool {
    switch self {
    case let .chow(_, _, exposed): return exposed
    case let .pung(_, concealed), let .kong(_, concealed): return !concealed
    }
  }
}
public enum HandShape: String, Codable, Sendable {
  case standard
  case sevenPairs
  case thirteenOrphans
  case lesserHonorsKnitted
  case greaterHonorsKnitted
  case knittedStraight
}
public struct WinningStructure: Hashable, Codable, Sendable {
  public let shape: HandShape
  public let groups: [Group]
  public let pair: TileKind?
  public let specialTiles: [TileKind]

  public init(
    shape: HandShape,
    groups: [Group] = [],
    pair: TileKind? = nil,
    specialTiles: [TileKind] = []
  ) {
    self.shape = shape
    self.groups = groups
    self.pair = pair
    self.specialTiles = specialTiles.sorted()
  }
}
