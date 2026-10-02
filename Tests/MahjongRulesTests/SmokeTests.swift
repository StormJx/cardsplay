import Testing

@testable import MahjongRules

@Test func packageBuilds() {
  #expect(TileSet.all.count == 144)
}
