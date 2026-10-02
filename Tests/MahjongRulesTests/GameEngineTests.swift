import Testing

@testable import MahjongRules

@Suite("行牌状态机")
struct GameEngineTests {
  @Test func rotatedDealerReceivesFourteenTilesAndDiscardsFirst() {
    let baseline = GameState(seed: 42)
    let east = GameState(seed: 42, dealer: 0)
    #expect(east.players[0].concealed.map(\.kind) == baseline.players[0].concealed.map(\.kind))
    #expect(east.phase == .awaitingDiscard(seat: 0))

    for dealer in 0..<4 {
      let game = GameState(seed: 42, dealer: dealer)
      #expect(game.players[dealer].concealed.count == 14)
      for seat in 0..<4 where seat != dealer {
        #expect(game.players[seat].concealed.count == 13)
      }
      #expect(game.players.flatMap(\.concealed).allSatisfy { !$0.kind.isFlower })
      #expect(game.physicalTileCount == 144)
      #expect(game.phase == .awaitingDiscard(seat: dealer))
    }
  }

  @Test func initialDealReplacesFlowersAndConserves144Tiles() {
    let game = GameState(seed: 42)
    #expect(game.players[0].concealed.count == 14)
    #expect(game.players[1].concealed.count == 13)
    #expect(game.players[2].concealed.count == 13)
    #expect(game.players[3].concealed.count == 13)
    #expect(game.players.flatMap(\.concealed).allSatisfy { !$0.kind.isFlower })
    #expect(game.physicalTileCount == 144)
    #expect(game.phase == .awaitingDiscard(seat: 0))
  }

  @Test func commandPhasesRejectWrongSeatAndMissingTile() throws {
    var game = GameState(seed: 1)
    #expect(throws: RuleViolation.wrongPhase) { try game.apply(.draw(seat: 0)) }
    #expect(throws: RuleViolation.wrongPhase) {
      try game.apply(.discard(seat: 1, tile: game.players[1].concealed[0]))
    }
    #expect(throws: RuleViolation.tileNotHeld) {
      try game.apply(.discard(seat: 0, tile: Tile(kind: .spring, copy: 0)))
    }
  }

  @Test func noClaimAdvancesToNextDrawAndWallExhaustionDrawsHand() throws {
    var game = GameState(
      wall: Wall(tiles: []),
      players: [
        PlayerState(concealed: [Tile(kind: .east, copy: 0)]),
        PlayerState(), PlayerState(), PlayerState(),
      ],
      phase: .awaitingDiscard(seat: 0)
    )
    try game.apply(.discard(seat: 0, tile: Tile(kind: .east, copy: 0)))
    try game.apply(.resolveClaims([]))
    #expect(game.phase == .awaitingDraw(seat: 1))
    try game.apply(.draw(seat: 1))
    #expect(game.phase == .endedDraw)
    #expect(game.events.last == .handDrawn)
  }

  @Test func chowIsLimitedToNextPlayerAndEnumeratesEveryRun() throws {
    let discard = Tile(kind: .character3, copy: 0)
    let player = PlayerState(concealed: [
      Tile(kind: .character1, copy: 0), Tile(kind: .character2, copy: 0),
      Tile(kind: .character4, copy: 0), Tile(kind: .character5, copy: 0),
    ])
    var game = GameState(
      wall: Wall(tiles: [Tile(kind: .dot9, copy: 3)]),
      players: [PlayerState(concealed: [discard]), player, PlayerState(), PlayerState()],
      phase: .awaitingDiscard(seat: 0)
    )
    #expect(game.legalChows(seat: 1, discard: .character3, discarder: 0).count == 3)
    #expect(game.legalChows(seat: 2, discard: .character3, discarder: 0).isEmpty)
    try game.apply(.discard(seat: 0, tile: discard))
    try game.apply(.resolveClaims([Claim(seat: 1, type: .chow, chowTiles: tiles("123m"))]))
    #expect(game.players[1].melds.first?.type == .chow)
    #expect(game.phase == .awaitingDiscard(seat: 1))
  }

  @Test func pungAndKongBeatChowWhileWinBeatsAll() {
    let claims = [
      Claim(seat: 1, type: .chow),
      Claim(seat: 3, type: .pung),
      Claim(seat: 2, type: .exposedKong),
      Claim(seat: 1, type: .win),
    ]
    #expect(ClaimResolver.resolve(discarder: 0, claims: claims)?.type == .win)
    #expect(
      ClaimResolver.resolve(discarder: 0, claims: Array(claims.dropLast()))?.type == .exposedKong)
    let equal = [Claim(seat: 3, type: .win), Claim(seat: 1, type: .win)]
    #expect(ClaimResolver.resolve(discarder: 0, claims: equal)?.seat == 1)
  }

  @Test func pungClaimMovesDiscardIntoMeld() throws {
    let discarded = Tile(kind: .east, copy: 0)
    var game = GameState(
      wall: Wall(tiles: [Tile(kind: .dot9, copy: 3)]),
      players: [
        PlayerState(concealed: [discarded]),
        PlayerState(concealed: [Tile(kind: .east, copy: 1), Tile(kind: .east, copy: 2)]),
        PlayerState(), PlayerState(),
      ],
      phase: .awaitingDiscard(seat: 0)
    )
    try game.apply(.discard(seat: 0, tile: discarded))
    try game.apply(.resolveClaims([Claim(seat: 1, type: .pung)]))
    #expect(game.discards.isEmpty)
    #expect(game.players[1].melds.first?.type == .pung)
    #expect(game.phase == .awaitingDiscard(seat: 1))
  }

  @Test func concealedAndAddedKongsDrawFromBack() throws {
    let fourEast = (0..<4).map { Tile(kind: .east, copy: $0) }
    let replacement = Tile(kind: .character1, copy: 0)
    var concealed = GameState(
      wall: Wall(tiles: [replacement]),
      players: [PlayerState(concealed: fourEast), PlayerState(), PlayerState(), PlayerState()],
      phase: .awaitingDiscard(seat: 0)
    )
    try concealed.apply(.concealedKong(seat: 0, kind: .east))
    #expect(concealed.players[0].melds.first?.type == .concealedKong)
    #expect(concealed.players[0].melds.first?.isKong == true)
    #expect(concealed.players[0].concealed == [replacement])

    let fourth = Tile(kind: .south, copy: 3)
    let back = Tile(kind: .dot1, copy: 0)
    var added = GameState(
      wall: Wall(tiles: [back]),
      players: [
        PlayerState(
          concealed: [fourth],
          melds: [Meld(type: .pung, tiles: [.south, .south, .south])]
        ),
        PlayerState(), PlayerState(), PlayerState(),
      ],
      phase: .awaitingDiscard(seat: 0)
    )
    try added.apply(.addedKong(seat: 0, meldIndex: 0, tile: fourth))
    #expect(added.phase == .awaitingRobKong(declarer: 0, meldIndex: 0, tile: fourth))
    try added.apply(.resolveClaims([]))
    #expect(added.players[0].melds[0].type == .addedKong)
    #expect(added.players[0].concealed == [back])
  }

  @Test func onlyAddedKongCanBeRobbedBeforeItCommits() throws {
    let fourth = Tile(kind: .south, copy: 3)
    var game = GameState(
      wall: Wall(tiles: [Tile(kind: .dot1, copy: 0)]),
      players: [
        PlayerState(
          concealed: [fourth],
          melds: [Meld(type: .pung, tiles: [.south, .south, .south])]
        ),
        PlayerState(), PlayerState(), PlayerState(),
      ],
      phase: .awaitingDiscard(seat: 0)
    )
    try game.apply(.addedKong(seat: 0, meldIndex: 0, tile: fourth))
    try game.apply(
      .resolveClaims([
        Claim(seat: 3, type: .win),
        Claim(seat: 1, type: .win),
      ]))
    #expect(game.phase == .endedWin(winner: 1))
    #expect(game.players[0].melds[0].type == .pung)
    #expect(game.players[0].concealed == [fourth])
  }

  @Test func kongIsIllegalWithoutReplacementTile() {
    let fourEast = (0..<4).map { Tile(kind: .east, copy: $0) }
    var game = GameState(
      wall: Wall(tiles: []),
      players: [PlayerState(concealed: fourEast), PlayerState(), PlayerState(), PlayerState()],
      phase: .awaitingDiscard(seat: 0)
    )
    #expect(game.concealedKongKinds(seat: 0).isEmpty)
    #expect(throws: RuleViolation.illegalKong) {
      try game.apply(.concealedKong(seat: 0, kind: .east))
    }
  }

  @Test func tenThousandSeededHandsExerciseClaimsKongsAndSafeWinChecks() throws {
    var chowCount = 0
    var pungCount = 0
    var exposedKongCount = 0
    var concealedKongCount = 0
    var addedKongCount = 0
    var scoreEvaluations = 0
    var legalWinCount = 0

    for seed in 0..<10_000 {
      var game = GameState(seed: UInt64(seed))
      var rng = SplitMix64(seed: UInt64(seed) ^ 0xD1B5_4A32_D192_ED03)
      var steps = 0
      while steps < 400 {
        #expect(game.physicalTileCount == 144)
        switch game.phase {
        case let .awaitingDiscard(seat):
          let added = game.addedKongIndices(seat: seat)
          if !added.isEmpty, rng.next() % 3 == 0 {
            let meldIndex = added[Int(rng.next() % UInt64(added.count))]
            let kind = game.players[seat].melds[meldIndex].kind
            let tile = game.players[seat].concealed.first { $0.kind == kind }!
            try game.apply(.addedKong(seat: seat, meldIndex: meldIndex, tile: tile))
            addedKongCount += 1
            break
          }

          let concealed = game.concealedKongKinds(seat: seat)
          if !concealed.isEmpty {
            let kind = concealed[Int(rng.next() % UInt64(concealed.count))]
            try game.apply(.concealedKong(seat: seat, kind: kind))
            concealedKongCount += 1
            break
          }

          let hand = game.players[seat].concealed
          let discard = hand[Int(rng.next() % UInt64(hand.count))]
          try game.apply(.discard(seat: seat, tile: discard))

        case let .awaitingResponses(discarder, discarded):
          var legalWins: [Claim] = []
          if steps % 20 == seed % 20 {
            let seat = (discarder + 1) % 4
            let player = game.players[seat]
            let candidate = WinContext(
              concealedTiles: player.concealed.map(\.kind) + [discarded.kind],
              melds: player.melds,
              winningTile: discarded.kind,
              method: .discard,
              seatWind: Wind(rawValue: seat)!,
              roundWind: .east,
              flowerCount: player.flowers.count
            )
            scoreEvaluations += 1
            if let score = MCRScorer.score(candidate), score.isLegalWin {
              #expect(score.nonFlowerPoints >= 8)
              legalWins.append(Claim(seat: seat, type: .win))
            }
          }
          if !legalWins.isEmpty {
            try game.apply(.resolveClaims(legalWins))
            legalWinCount += 1
            break
          }

          var kongs: [Claim] = []
          var pungs: [Claim] = []
          var chows: [Claim] = []
          for seat in 0..<4 where seat != discarder {
            if game.canExposedKong(seat: seat, discard: discarded.kind) {
              kongs.append(Claim(seat: seat, type: .exposedKong))
            }
            if game.canPung(seat: seat, discard: discarded.kind) {
              pungs.append(Claim(seat: seat, type: .pung))
            }
            for run in game.legalChows(seat: seat, discard: discarded.kind, discarder: discarder) {
              chows.append(Claim(seat: seat, type: .chow, chowTiles: run))
            }
          }

          let selected: Claim?
          if !kongs.isEmpty {
            selected = kongs[Int(rng.next() % UInt64(kongs.count))]
          } else if !pungs.isEmpty, chows.isEmpty || rng.next() % 3 == 0 {
            selected = pungs[Int(rng.next() % UInt64(pungs.count))]
          } else if !chows.isEmpty {
            selected = chows[Int(rng.next() % UInt64(chows.count))]
          } else {
            selected = nil
          }

          if let selected {
            try game.apply(.resolveClaims([selected]))
            switch selected.type {
            case .chow: chowCount += 1
            case .pung: pungCount += 1
            case .exposedKong: exposedKongCount += 1
            case .win: break
            }
          } else {
            try game.apply(.resolveClaims([]))
          }

        case .awaitingRobKong:
          try game.apply(.resolveClaims([]))

        case let .awaitingDraw(seat):
          try game.apply(.draw(seat: seat))

        case .endedDraw, .endedWin:
          break
        }
        steps += 1
        if case .endedDraw = game.phase { break }
        if case .endedWin = game.phase { break }
      }
      let ended: Bool
      switch game.phase {
      case .endedDraw, .endedWin: ended = true
      default: ended = false
      }
      #expect(ended)
      #expect(steps < 400)
      #expect(game.physicalTileCount == 144)
    }

    #expect(chowCount > 0)
    #expect(pungCount > 0)
    #expect(exposedKongCount > 0)
    #expect(concealedKongCount > 0)
    #expect(addedKongCount > 0)
    #expect(scoreEvaluations > 0)
    #expect(legalWinCount > 0)
  }
}
