import Testing

@testable import MahjongRules

@Suite("牌张与确定性牌墙")
struct TileWallTests {
  @Test func tileSetHasExactly144PhysicalTiles() {
    #expect(TileSet.all.count == 144)
    #expect(Set(TileSet.all).count == 144)
    #expect(TileSet.all.filter { $0.kind.isFlower }.count == 8)
    for kind in TileSet.normalKinds {
      #expect(TileSet.all.filter { $0.kind == kind }.count == 4)
    }
  }

  @Test func tilePropertiesAndCountValidation() {
    #expect(TileKind(suit: .characters, rank: 1)?.isTerminal == true)
    #expect(TileKind(suit: .dots, rank: 5)?.isSimple == true)
    #expect(TileKind(wind: .north).isHonor)
    #expect(TileKind(flower: .plum).isFlower)
    #expect(TileKind.character1.shortName == "1m")
    #expect(TileKind.north.shortName == "N")
    #expect(TileKind.green.shortName == "G")
    #expect(TileKind.chrysanthemum.shortName == "Ch")
    #expect([TileKind.south, .east].sortedTiles == [.east, .south])
    #expect(TileKind(suit: .bamboo, rank: 0) == nil)
    #expect(TileSet.validateCounts([.east, .east, .east, .east]))
    #expect(!TileSet.validateCounts([.east, .east, .east, .east, .east]))
    #expect(!TileSet.validateCounts([.spring]))
    #expect(TileSet.validateCounts([.spring], allowFlowers: true))
  }

  @Test func seededWallIsReproducibleAndTwoEnded() {
    var first = Wall(seed: 2026)
    let second = Wall(seed: 2026)
    #expect(first == second)
    let front = first.drawFront()
    let back = first.drawBack()
    #expect(front != back)
    #expect(first.remainingCount == 142)
    #expect(second.remainingCount == 144)
    #expect(first.drawnTiles.count == 2)
  }

  @Test func flowerReplacementContinuesFromBack() {
    let normal = Tile(kind: .east, copy: 0)
    let frontFlower = Tile(kind: .spring, copy: 0)
    let backFlower = Tile(kind: .summer, copy: 0)
    var wall = Wall(tiles: [frontFlower, normal, backFlower])
    let result = wall.drawReplacingFlowers()
    #expect(result.tile == normal)
    #expect(result.flowers == [frontFlower, backFlower])
    #expect(wall.isEmpty)
  }

  @Test func emptyWallDrawsNothing() {
    var wall = Wall(tiles: [])
    #expect(wall.drawFront() == nil)
    #expect(wall.drawBack() == nil)
    #expect(wall.drawReplacingFlowers().tile == nil)
  }
}
