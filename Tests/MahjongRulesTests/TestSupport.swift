@testable import MahjongRules

func tile(_ text: String) -> TileKind {
  if let last = text.last, let rank = Int(text.dropLast()) {
    let suit: Suit
    switch last {
    case "m": suit = .characters
    case "p": suit = .dots
    case "s": suit = .bamboo
    default: fatalError("Unknown tile \(text)")
    }
    return TileKind(suit: suit, rank: rank)!
  }
  switch text {
  case "E": return .east
  case "S": return .south
  case "W": return .west
  case "N": return .north
  case "R": return .red
  case "G": return .green
  case "Wh": return .white
  default: fatalError("Unknown tile \(text)")
  }
}
func tiles(_ notation: String) -> [TileKind] {
  var result: [TileKind] = []
  var digits: [Int] = []
  for character in notation {
    if let digit = character.wholeNumberValue {
      digits.append(digit)
      continue
    }
    let suit: Suit?
    switch character {
    case "m": suit = .characters
    case "p": suit = .dots
    case "s": suit = .bamboo
    default: suit = nil
    }
    if let suit {
      result += digits.map { TileKind(suit: suit, rank: $0)! }
      digits = []
    }
  }
  precondition(digits.isEmpty)
  return result
}
func context(
  _ notation: String,
  honors: [TileKind] = [],
  melds: [Meld] = [],
  winning: TileKind? = nil,
  method: WinMethod = .selfDraw,
  seat: Wind = .east,
  round: Wind = .east,
  flowers: Int = 0,
  lastWall: Bool = false,
  lastDiscard: Bool = false,
  visible: [TileKind: Int] = [:]
) -> WinContext {
  let concealed = tiles(notation) + honors
  return WinContext(
    concealedTiles: concealed,
    melds: melds,
    winningTile: winning ?? concealed.last!,
    method: method,
    seatWind: seat,
    roundWind: round,
    flowerCount: flowers,
    isLastWallTile: lastWall,
    isLastDiscard: lastDiscard,
    visibleTileCounts: visible
  )
}
func pung(_ kind: TileKind, concealed: Bool = false) -> Meld {
  .init(
    type: concealed ? .concealedKong : .pung,
    tiles: Array(repeating: kind, count: concealed ? 4 : 3)
  )
}
func chow(_ notation: String) -> Meld {
  .init(type: .chow, tiles: tiles(notation))
}
func awardSet(_ result: ScoreResult?) -> Set<Fan> {
  Set(result?.awards.map(\.fan) ?? [])
}
