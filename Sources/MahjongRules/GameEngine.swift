/// M0 command/event state machine. It owns rule legality; presentation code only sends commands.
public enum ClaimType: Int, Codable, Sendable {
  case chow = 1
  case pung = 2
  case exposedKong = 3
  case win = 4
}
public struct Claim: Equatable, Codable, Sendable {
  public let seat: Int
  public let type: ClaimType
  public let chowTiles: [TileKind]

  public init(seat: Int, type: ClaimType, chowTiles: [TileKind] = []) {
    self.seat = seat
    self.type = type
    self.chowTiles = chowTiles
  }
}
public enum ClaimResolver {
  public static func resolve(discarder: Int, claims: [Claim]) -> Claim? {
    claims.sorted {
      if $0.type.rawValue != $1.type.rawValue { return $0.type.rawValue > $1.type.rawValue }
      return distance(from: discarder, to: $0.seat) < distance(from: discarder, to: $1.seat)
    }.first
  }

  private static func distance(from: Int, to: Int) -> Int {
    (to - from + 4) % 4
  }
}
public struct PlayerState: Codable, Sendable {
  public var concealed: [Tile]
  public var melds: [Meld]
  public var flowers: [Tile]
  public var isWinSuspended: Bool

  public init(
    concealed: [Tile] = [],
    melds: [Meld] = [],
    flowers: [Tile] = [],
    isWinSuspended: Bool = false
  ) {
    self.concealed = concealed
    self.melds = melds
    self.flowers = flowers
    self.isWinSuspended = isWinSuspended
  }
}
public enum HandPhase: Equatable, Codable, Sendable {
  case awaitingDraw(seat: Int)
  case awaitingDiscard(seat: Int)
  case awaitingResponses(discarder: Int, tile: Tile)
  case awaitingRobKong(declarer: Int, meldIndex: Int, tile: Tile)
  case endedDraw
  case endedWin(winner: Int)
}
public enum GameCommand: Codable, Equatable, Sendable {
  case draw(seat: Int)
  case discard(seat: Int, tile: Tile)
  case concealedKong(seat: Int, kind: TileKind)
  case addedKong(seat: Int, meldIndex: Int, tile: Tile)
  case resolveClaims([Claim])
}
public enum GameEvent: Equatable, Codable, Sendable {
  case drew(seat: Int, tile: Tile)
  case exposedFlower(seat: Int, tile: Tile)
  case discarded(seat: Int, tile: Tile)
  case claimed(seat: Int, type: ClaimType, tile: TileKind)
  case declaredKong(seat: Int, kind: TileKind, concealed: Bool)
  case handDrawn
  case handWon(seat: Int)
}
public enum RuleViolation: Error, Equatable {
  case wrongPhase
  case wrongSeat
  case tileNotHeld
  case illegalClaim
  case illegalKong
  case noReplacementTile
}
public struct GameState: Codable, Sendable {
  public private(set) var wall: Wall
  public private(set) var players: [PlayerState]
  public private(set) var discards: [Tile]
  public private(set) var phase: HandPhase
  public private(set) var events: [GameEvent]

  /// `dealer` is the East seat for this hand. That seat receives 14 tiles and discards first.
  /// Dealer 0 keeps the original deal order.
  public init(seed: UInt64, dealer: Int = 0) {
    precondition((0..<4).contains(dealer))
    wall = Wall(seed: seed)
    players = Array(repeating: PlayerState(), count: 4)
    discards = []
    phase = .awaitingDiscard(seat: dealer)
    events = []

    for round in 0..<14 {
      for offset in 0..<4 where round < 13 || offset == 0 {
        dealPlayableTile(to: (dealer + offset) % 4)
      }
    }
  }

  public init(
    wall: Wall,
    players: [PlayerState],
    discards: [Tile] = [],
    phase: HandPhase,
    events: [GameEvent] = []
  ) {
    precondition(players.count == 4)
    self.wall = wall
    self.players = players
    self.discards = discards
    self.phase = phase
    self.events = events
  }

  public mutating func apply(_ command: GameCommand) throws {
    switch command {
    case let .draw(seat):
      try draw(seat: seat)
    case let .discard(seat, tile):
      try discard(seat: seat, tile: tile)
    case let .concealedKong(seat, kind):
      try concealedKong(seat: seat, kind: kind)
    case let .addedKong(seat, meldIndex, tile):
      try addedKong(seat: seat, meldIndex: meldIndex, tile: tile)
    case let .resolveClaims(claims):
      try resolveClaims(claims)
    }
  }

  public func legalChows(seat: Int, discard: TileKind, discarder: Int) -> [[TileKind]] {
    guard wall.remainingCount > 0, seat == (discarder + 1) % 4,
      let suit = discard.suit, let rank = discard.rank
    else { return [] }
    let held = players[seat].concealed.map(\.kind).counts
    return (-2...0).compactMap { offset in
      let start = rank + offset
      guard (1...7).contains(start) else { return nil }
      let run = (start...(start + 2)).map { TileKind(suit: suit, rank: $0)! }
      var needed = run
      needed.remove(at: needed.firstIndex(of: discard)!)
      return needed.allSatisfy { tile in
        needed.filter { $0 == tile }.count <= held[tile, default: 0]
      } ? run : nil
    }
  }

  public func canPung(seat: Int, discard: TileKind) -> Bool {
    wall.remainingCount > 0 && players[seat].concealed.filter { $0.kind == discard }.count >= 2
  }

  public func canExposedKong(seat: Int, discard: TileKind) -> Bool {
    wall.hasNormalTileRemaining && players[seat].concealed.filter { $0.kind == discard }.count >= 3
  }

  public func concealedKongKinds(seat: Int) -> [TileKind] {
    guard wall.hasNormalTileRemaining else { return [] }
    return players[seat].concealed.map(\.kind).counts
      .filter { $0.value == 4 }.map(\.key).sorted()
  }

  public func addedKongIndices(seat: Int) -> [Int] {
    guard wall.hasNormalTileRemaining else { return [] }
    let held = Set(players[seat].concealed.map(\.kind))
    return players[seat].melds.indices.filter {
      players[seat].melds[$0].type == .pung && held.contains(players[seat].melds[$0].kind)
    }
  }

  public var physicalTileCount: Int {
    wall.remainingCount
      + players.reduce(0) { total, player in
        total + player.concealed.count + player.melds.reduce(0) { $0 + $1.tiles.count }
          + player.flowers.count
      }
      + discards.count
  }

  @discardableResult
  public mutating func adjudicateWinDeclaration(seat: Int, context: WinContext) -> WinDeclaration {
    let decision = WinAdjudicator.adjudicate(context)
    switch decision {
    case .legal:
      phase = .endedWin(winner: seat)
      events.append(.handWon(seat: seat))
    case .wrongWin, .fraudulentWin:
      players[seat].isWinSuspended = true
    }
    return decision
  }

  private mutating func dealPlayableTile(to seat: Int) {
    let result = wall.drawReplacingFlowers()
    for flower in result.flowers {
      players[seat].flowers.append(flower)
      events.append(.exposedFlower(seat: seat, tile: flower))
    }
    if let tile = result.tile {
      players[seat].concealed.append(tile)
    }
  }

  private mutating func draw(seat: Int) throws {
    guard phase == .awaitingDraw(seat: seat) else { throw RuleViolation.wrongPhase }
    let result = wall.drawReplacingFlowers()
    for flower in result.flowers {
      players[seat].flowers.append(flower)
      events.append(.exposedFlower(seat: seat, tile: flower))
    }
    guard let tile = result.tile else {
      phase = .endedDraw
      events.append(.handDrawn)
      return
    }
    players[seat].concealed.append(tile)
    events.append(.drew(seat: seat, tile: tile))
    phase = .awaitingDiscard(seat: seat)
  }

  private mutating func discard(seat: Int, tile: Tile) throws {
    guard phase == .awaitingDiscard(seat: seat) else { throw RuleViolation.wrongPhase }
    guard let index = players[seat].concealed.firstIndex(of: tile) else {
      throw RuleViolation.tileNotHeld
    }
    players[seat].concealed.remove(at: index)
    discards.append(tile)
    events.append(.discarded(seat: seat, tile: tile))
    phase = .awaitingResponses(discarder: seat, tile: tile)
  }

  private mutating func concealedKong(seat: Int, kind: TileKind) throws {
    guard phase == .awaitingDiscard(seat: seat) else { throw RuleViolation.wrongPhase }
    guard concealedKongKinds(seat: seat).contains(kind) else { throw RuleViolation.illegalKong }
    let removed = remove(kind: kind, count: 4, from: seat)
    players[seat].melds.append(.init(type: .concealedKong, tiles: removed.map(\.kind)))
    events.append(.declaredKong(seat: seat, kind: kind, concealed: true))
    try drawReplacement(seat: seat)
  }

  private mutating func addedKong(seat: Int, meldIndex: Int, tile: Tile) throws {
    guard phase == .awaitingDiscard(seat: seat) else { throw RuleViolation.wrongPhase }
    guard addedKongIndices(seat: seat).contains(meldIndex),
      players[seat].melds[meldIndex].kind == tile.kind,
      let tileIndex = players[seat].concealed.firstIndex(of: tile)
    else { throw RuleViolation.illegalKong }
    _ = tileIndex
    phase = .awaitingRobKong(declarer: seat, meldIndex: meldIndex, tile: tile)
  }

  private mutating func drawReplacement(seat: Int) throws {
    let result = wall.drawReplacingFlowers(fromBack: true)
    for flower in result.flowers {
      players[seat].flowers.append(flower)
      events.append(.exposedFlower(seat: seat, tile: flower))
    }
    guard let tile = result.tile else { throw RuleViolation.noReplacementTile }
    players[seat].concealed.append(tile)
    events.append(.drew(seat: seat, tile: tile))
    phase = .awaitingDiscard(seat: seat)
  }

  private mutating func resolveClaims(_ claims: [Claim]) throws {
    if case let .awaitingRobKong(declarer, meldIndex, tile) = phase {
      let wins = claims.filter { $0.type == .win && $0.seat != declarer }
      if let winner = ClaimResolver.resolve(discarder: declarer, claims: wins) {
        phase = .endedWin(winner: winner.seat)
        events.append(.handWon(seat: winner.seat))
        return
      }
      guard claims.isEmpty else { throw RuleViolation.illegalClaim }
      guard let tileIndex = players[declarer].concealed.firstIndex(of: tile) else {
        throw RuleViolation.tileNotHeld
      }
      players[declarer].concealed.remove(at: tileIndex)
      players[declarer].melds[meldIndex] = .init(
        type: .addedKong, tiles: Array(repeating: tile.kind, count: 4))
      events.append(.declaredKong(seat: declarer, kind: tile.kind, concealed: false))
      try drawReplacement(seat: declarer)
      return
    }
    guard case let .awaitingResponses(discarder, discarded) = phase else {
      throw RuleViolation.wrongPhase
    }
    guard let claim = ClaimResolver.resolve(discarder: discarder, claims: claims) else {
      phase = .awaitingDraw(seat: (discarder + 1) % 4)
      return
    }
    guard claim.seat != discarder else { throw RuleViolation.illegalClaim }

    if claim.type == .win {
      guard !players[claim.seat].isWinSuspended else { throw RuleViolation.illegalClaim }
      phase = .endedWin(winner: claim.seat)
      events.append(.handWon(seat: claim.seat))
      return
    }

    switch claim.type {
    case .chow:
      guard
        legalChows(seat: claim.seat, discard: discarded.kind, discarder: discarder).contains(
          claim.chowTiles.sorted())
      else {
        throw RuleViolation.illegalClaim
      }
      var needed = claim.chowTiles
      needed.remove(at: needed.firstIndex(of: discarded.kind)!)
      for kind in needed { _ = remove(kind: kind, count: 1, from: claim.seat) }
      players[claim.seat].melds.append(
        .init(type: .chow, tiles: claim.chowTiles, claimedFrom: discarder))
    case .pung:
      guard canPung(seat: claim.seat, discard: discarded.kind) else {
        throw RuleViolation.illegalClaim
      }
      _ = remove(kind: discarded.kind, count: 2, from: claim.seat)
      players[claim.seat].melds.append(
        .init(
          type: .pung, tiles: Array(repeating: discarded.kind, count: 3), claimedFrom: discarder))
    case .exposedKong:
      guard canExposedKong(seat: claim.seat, discard: discarded.kind) else {
        throw RuleViolation.illegalClaim
      }
      _ = remove(kind: discarded.kind, count: 3, from: claim.seat)
      players[claim.seat].melds.append(
        .init(
          type: .exposedKong, tiles: Array(repeating: discarded.kind, count: 4),
          claimedFrom: discarder))
    case .win:
      break
    }
    _ = discards.popLast()
    events.append(.claimed(seat: claim.seat, type: claim.type, tile: discarded.kind))
    if claim.type == .exposedKong {
      try drawReplacement(seat: claim.seat)
    } else {
      phase = .awaitingDiscard(seat: claim.seat)
    }
  }

  @discardableResult
  private mutating func remove(kind: TileKind, count: Int, from seat: Int) -> [Tile] {
    var removed: [Tile] = []
    for _ in 0..<count {
      let index = players[seat].concealed.firstIndex { $0.kind == kind }!
      removed.append(players[seat].concealed.remove(at: index))
    }
    return removed
  }
}
