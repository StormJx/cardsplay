/// Deterministic two-ended wall. Normal draws use the front; flowers and kongs use the back.
public struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64

  public init(seed: UInt64) {
    state = seed
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
public struct Wall: Codable, Equatable, Sendable {
  public private(set) var tiles: [Tile]
  public private(set) var frontIndex: Int
  public private(set) var backIndex: Int

  public init(seed: UInt64) {
    var rng = SplitMix64(seed: seed)
    var tiles = TileSet.all
    if tiles.count > 1 {
      for i in stride(from: tiles.count - 1, through: 1, by: -1) {
        let j = Int(rng.next() % UInt64(i + 1))
        tiles.swapAt(i, j)
      }
    }
    self.init(tiles: tiles)
  }

  public init(tiles: [Tile]) {
    precondition(Set(tiles).count == tiles.count, "A wall cannot contain duplicate physical tiles")
    self.tiles = tiles
    frontIndex = 0
    backIndex = tiles.count - 1
  }

  public var remainingCount: Int {
    max(0, backIndex - frontIndex + 1)
  }

  public var isEmpty: Bool { remainingCount == 0 }
  public var hasNormalTileRemaining: Bool {
    guard !isEmpty else { return false }
    return tiles[frontIndex...backIndex].contains { !$0.kind.isFlower }
  }

  public mutating func drawFront() -> Tile? {
    guard !isEmpty else { return nil }
    defer { frontIndex += 1 }
    return tiles[frontIndex]
  }

  public mutating func drawBack() -> Tile? {
    guard !isEmpty else { return nil }
    defer { backIndex -= 1 }
    return tiles[backIndex]
  }

  /// Draws a playable tile and exposes every encountered flower.
  public mutating func drawReplacingFlowers(fromBack: Bool = false) -> (
    tile: Tile?, flowers: [Tile]
  ) {
    var flowers: [Tile] = []
    var tile = fromBack ? drawBack() : drawFront()
    while let current = tile, current.kind.isFlower {
      flowers.append(current)
      tile = drawBack()
    }
    return (tile, flowers)
  }

  public func upcomingTiles(limit: Int) -> [Tile] {
    guard limit > 0, !isEmpty else { return [] }
    let last = min(backIndex, frontIndex + limit - 1)
    guard last >= frontIndex else { return [] }
    return Array(tiles[frontIndex...last])
  }

  /// Puts an already-drawn tile back into the wall and returns the upcoming tile that replaces it.
  public mutating func swapDrawn(_ tile: Tile, withUpcomingOffset offset: Int) -> Tile? {
    guard let drawnIndex = tiles.firstIndex(of: tile) else { return nil }
    let index = frontIndex + offset
    guard drawnIndex < frontIndex || drawnIndex > backIndex else { return nil }
    guard (frontIndex...backIndex).contains(index) else { return nil }
    guard !tiles[index].kind.isFlower else { return nil }
    tiles.swapAt(drawnIndex, index)
    return tiles[drawnIndex]
  }

  public var drawnTiles: [Tile] {
    guard !tiles.isEmpty else { return [] }
    let front = frontIndex > 0 ? Array(tiles[0..<frontIndex]) : []
    let back = backIndex + 1 < tiles.count ? Array(tiles[(backIndex + 1)...]) : []
    return front + back
  }
}
