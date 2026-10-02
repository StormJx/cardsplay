import MahjongAI
import MahjongRules
import SpriteKit
import SwiftUI

struct M3LandscapeTable: View {
  @ObservedObject var model: PrototypeGame

  private let boardScene: GameScene = {
    let scene = GameScene(size: CGSize(width: 1_200, height: 700))
    scene.scaleMode = .resizeFill
    return scene
  }()

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.height < 390
      ZStack {
        SpriteView(scene: boardScene)
          .ignoresSafeArea()

        VStack(spacing: compact ? 3 : 5) {
          statusBar
          board(compact: compact)
          operationBar
          if model.practiceHints, model.result == nil, !model.showGameSetup {
            practiceHints(compact: compact)
          }
          playerArea(compact: compact)
        }
        .padding(.leading, max(7, proxy.safeAreaInsets.leading + 3))
        .padding(.trailing, max(7, proxy.safeAreaInsets.trailing + 3))
        .padding(.vertical, compact ? 3 : 5)

        if model.isPaused { pauseOverlay }
        if let result = model.result { resultOverlay(result) }
        if model.showGameSetup { gameSetupOverlay }
      }
    }
    .sheet(isPresented: $model.showSettings) {
      settingsView
    }
  }

  private var statusBar: some View {
    HStack(spacing: 9) {
      Label(model.tableLabel, systemImage: "flag.fill")
      Text(model.yourWindLabel)
      Divider().frame(height: 13)
      Text("牌墙 \(model.game.wall.remainingCount)")
        .monospacedDigit()
      Divider().frame(height: 13)
      Text("轮到：\(model.currentActorName)")
        .fontWeight(.semibold)
        .foregroundStyle(.yellow)
      Text(model.selectedDifficulty.displayName)
        .foregroundStyle(.cyan)
      Spacer(minLength: 5)
      ForEach(0..<4, id: \.self) { seat in
        Text("\(scoreName(seat)) \(signedScore(seat))")
          .monospacedDigit()
      }
      Button {
        model.togglePause()
      } label: {
        Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
      }
      Button {
        model.showSettings = true
      } label: {
        Image(systemName: "gearshape.fill")
      }
    }
    .font(.system(size: 11, weight: .medium))
    .buttonStyle(.borderless)
    .padding(.horizontal, 9)
    .frame(height: 25)
    .background(.black.opacity(0.58), in: Capsule())
    .accessibilityElement(children: .contain)
    .accessibilityLabel("牌局状态栏")
  }

  private func board(compact: Bool) -> some View {
    GeometryReader { board in
      let width = board.size.width
      let height = board.size.height
      let sideInset = max(66, min(82, width * 0.1))
      let riverInset = max(125, min(148, width * 0.18))

      ZStack {
        seatPanel(seat: 2, role: "对家", orientation: .top, compact: compact)
          .position(x: width / 2, y: compact ? 17 : 22)

        DiscardZone(
          title: "对家弃牌",
          tiles: model.discardRivers[2],
          orientation: .top,
          compact: compact
        )
        .position(x: width / 2, y: compact ? 72 : 83)

        seatPanel(seat: 3, role: "上家", orientation: .left, compact: compact)
          .position(x: sideInset * 0.42, y: height / 2)

        DiscardZone(
          title: "上家弃牌",
          tiles: model.discardRivers[3],
          orientation: .left,
          compact: compact
        )
        .position(x: riverInset, y: height / 2)

        seatPanel(seat: 1, role: "下家", orientation: .right, compact: compact)
          .position(x: width - sideInset * 0.42, y: height / 2)

        DiscardZone(
          title: "下家弃牌",
          tiles: model.discardRivers[1],
          orientation: .right,
          compact: compact
        )
        .position(x: width - riverInset, y: height / 2)

        DiscardZone(
          title: "你的弃牌",
          tiles: model.discardRivers[0],
          orientation: .bottom,
          compact: compact
        )
        .position(x: width / 2, y: height - (compact ? 49 : 57))

        VStack(spacing: 3) {
          Text(model.currentOperationTitle)
            .font(.system(size: compact ? 13 : 15, weight: .bold))
          Text(model.message)
            .font(.system(size: compact ? 9 : 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(.black.opacity(0.52), in: Capsule())
        .frame(maxWidth: max(190, width - riverInset * 2 - 15))
        .position(x: width / 2, y: height / 2)
      }
    }
    .frame(maxHeight: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(.yellow.opacity(0.16), lineWidth: 1)
    }
  }

  private func seatPanel(
    seat: Int,
    role: String,
    orientation: SeatOrientation,
    compact: Bool
  ) -> some View {
    let profile = model.opponentProfile(seat: seat)
    return VStack(spacing: 2) {
      HStack(spacing: 2) {
        Image(systemName: profile.avatarSystemName)
        Text("\(role) · \(profile.name)")
      }
      .font(.system(size: compact ? 8 : 9, weight: .bold))
      .lineLimit(1)
      Text(
        model.isEastRound
          ? "\(model.windTag(seat)) · \(profile.difficulty.displayName)"
          : "\(profile.difficulty.displayName) · \(profile.personality.archetype.displayName)"
      )
        .font(.system(size: 6))
        .foregroundStyle(.cyan)
      if orientation == .top {
        HiddenHand(count: model.game.players[seat].concealed.count, vertical: false)
        MeldRack(melds: model.game.players[seat].melds, vertical: false)
      } else {
        HStack(spacing: 3) {
          HiddenHand(count: model.game.players[seat].concealed.count, vertical: true)
          MeldRack(melds: model.game.players[seat].melds, vertical: true)
        }
      }
    }
    .padding(4)
    .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      model.isEastRound
        ? "\(role)，\(model.windTag(seat))，\(profile.name)，\(model.game.players[seat].concealed.count)张暗牌"
        : "\(role)，\(profile.name)，\(profile.difficulty.displayName)，\(profile.personality.archetype.displayName)，\(model.game.players[seat].concealed.count)张暗牌"
    )
  }

  private var operationBar: some View {
    HStack(spacing: 7) {
      Text("当前操作")
        .font(.caption2.bold())
        .foregroundStyle(.secondary)

      if model.actions.isEmpty {
        Text(model.operationHint)
          .font(.caption.bold())
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.black.opacity(0.3), in: Capsule())
      } else {
        ForEach(model.actions) { action in
          Button(action.title) {
            model.perform(action)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .tint(action == .win ? .red : (action == .skip ? .gray : .orange))
          .accessibilityIdentifier("action-\(action.id)")
        }
      }

      if case .awaitingDiscard(seat: 0) = model.game.phase {
        Button("打出") {
          model.discardSelected()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(model.selectedTile == nil)
        .accessibilityIdentifier("discard-button")
      }
      Spacer(minLength: 0)
    }
    .frame(height: 34)
  }

  private func practiceHints(compact: Bool) -> some View {
    let brief = model.practiceBrief
    return VStack(alignment: .leading, spacing: 1) {
      Text(brief?.waitLine ?? "听 轮到你时再看")
      Text(brief?.fanLine ?? "番 轮到你时再看")
      Text(brief?.dangerLine ?? "危险 点一张牌查看")
    }
    .font(.system(size: compact ? 9 : 10, weight: .medium))
    .foregroundStyle(.cyan)
    .lineLimit(1)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityIdentifier("practice-hints")
  }

  private func playerArea(compact: Bool) -> some View {
    HStack(spacing: 7) {
      VStack(spacing: 2) {
        Text(model.isEastRound ? "自己 · \(model.windTag(0))" : "自己")
          .font(.caption2.bold())
        MeldRack(melds: model.game.players[0].melds, vertical: true)
        if !model.game.players[0].flowers.isEmpty {
          HStack(spacing: 1) {
            ForEach(model.game.players[0].flowers, id: \.self) { tile in
              GraphicTileFace(kind: tile.kind, selected: false, miniature: true)
                .frame(width: 13, height: 18)
            }
          }
        }
      }
      .frame(width: 45)

      if isStandardTileShowcase {
        HStack(spacing: 2) {
          ForEach(standardTileShowcase, id: \.self) { kind in
            GraphicTileFace(kind: kind, selected: false, miniature: false)
              .frame(width: compact ? 29 : 35, height: compact ? 48 : 58)
              .accessibilityLabel(kind.displayName)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      } else {
        GeometryReader { hand in
          let count = max(14, model.game.players[0].concealed.count)
          let spacing: CGFloat = 2
          let tileWidth = min(
            compact ? 38 : 43,
            (hand.size.width - CGFloat(count - 1) * spacing) / CGFloat(count)
          )
          HStack(spacing: spacing) {
            ForEach(model.sortedPlayerTiles, id: \.self) { tile in
              Button {
                model.select(tile)
              } label: {
                GraphicTileFace(
                  kind: tile.kind,
                  selected: model.selectedTile == tile,
                  miniature: false
                )
                .frame(width: tileWidth, height: compact ? 54 : 61)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("tile-\(tile.kind.rawValue)-\(tile.copy)")
              .accessibilityLabel(tile.kind.displayName)
              .accessibilityAddTraits(model.selectedTile == tile ? .isSelected : [])
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .frame(height: compact ? 64 : 72)
    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private var gameSetupOverlay: some View {
    ScrollView {
      setupForm
    }
    .frame(maxWidth: 420, maxHeight: 360)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    .padding()
  }

  private var setupForm: some View {
    VStack(spacing: 10) {
      Text(model.setupTitle)
        .font(.title2.bold())
      if let note = model.setupNote {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      VStack(spacing: 8) {
        ForEach(AIDifficulty.allCases, id: \.self) { difficulty in
          Button {
            model.selectedDifficulty = difficulty
          } label: {
            HStack {
              Text(difficulty.displayName)
              Spacer()
              if model.selectedDifficulty == difficulty {
                Image(systemName: "checkmark")
              }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
          }
          .buttonStyle(.borderedProminent)
          .tint(model.selectedDifficulty == difficulty ? .teal : .gray)
          .accessibilityIdentifier("difficulty-\(difficulty.rawValue)")
        }
      }

      Text(setupDescription)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      HStack {
        Button("返回") { model.returnHome() }
          .buttonStyle(.bordered)
        Button(model.setupButtonTitle) {
          model.startGame(difficulty: model.selectedDifficulty)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("start-game")
      }
    }
    .padding(20)
  }

  private var setupDescription: String {
    switch model.selectedDifficulty {
    case .beginner:
      return "随机与基础牌效并用，防守较弱"
    case .normal:
      return "牌效优先，并依据公开牌做基础防守"
    case .expert:
      return "综合公开牌河、危险度、分数与角色番路；不读取暗牌"
    }
  }

  private var isStandardTileShowcase: Bool {
    ProcessInfo.processInfo.arguments.contains("-standard-tile-showcase")
  }

  private var standardTileShowcase: [TileKind] {
    [
      .character1, .character5, .character9,
      .bamboo1, .bamboo5, .bamboo9,
      .dot1, .dot5, .dot9,
      .east, .south, .west, .north,
      .red, .green, .white,
      .spring, .plum,
    ]
  }

  private var pauseOverlay: some View {
    VStack(spacing: 10) {
      Image(systemName: "pause.circle.fill").font(.largeTitle)
      Text("牌局已暂停").font(.headline)
      Text("当前动作已经保存").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("回到主页") { model.returnHome() }
          .buttonStyle(.bordered)
        Button("继续") { model.togglePause() }
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(22)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
  }

  private func resultOverlay(_ result: RoundResult) -> some View {
    VStack(spacing: 8) {
      if model.isEastRound {
        Text(model.tableLabel)
          .font(.caption.bold())
          .foregroundStyle(.secondary)
      }
      if result.isDraw {
        Text("流局").font(.title.bold())
        Text("牌墙已摸完，本局无人和牌")
      } else if let winner = result.winner, let score = result.score {
        Text("\(model.playerLabel(winner))和牌")
          .font(.title2.bold())
        Text(result.discarder == nil ? "自摸" : "\(model.playerLabel(result.discarder!))放铳")
          .foregroundStyle(.secondary)
        Text(score.awards.map { "\($0.fan.name) \($0.points)番" }.joined(separator: " · "))
          .font(.caption)
          .multilineTextAlignment(.center)
        Text("合计 \(score.totalPoints) 番")
          .font(.headline)
          .foregroundStyle(.yellow)
        ScrollView(.horizontal) {
          HStack(spacing: 6) {
            ForEach(Array(score.awards.enumerated()), id: \.offset) { _, award in
              Button("\(award.fan.name) \(award.points)") {
                model.highlightedFan = award.fan.rawValue
                model.route = .guides
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        }
        .frame(height: 32)
        Text(deltaLine(result.deltas))
          .font(.caption2.monospacedDigit())
        if let careerNote = model.careerNote {
          Text(careerNote).font(.caption.bold()).foregroundStyle(.yellow)
        }
      }
      if model.isEastRound {
        Text(model.roundComplete ? "东风圈总分" : "四家目前总分")
          .font(.caption.bold())
        Text(model.cumulativeLine)
          .font(.caption2.monospacedDigit())
          .multilineTextAlignment(.center)
      }
      HStack {
        Button("返回主页") { model.returnHome() }
          .buttonStyle(.bordered)
        Button(model.primaryResultButton) { model.advanceResult() }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("result-primary")
        if model.lastRecordCanReplay, let id = model.lastRecordID {
          Button("复盘") { model.openReplay(id) }
            .buttonStyle(.bordered)
        }
      }
    }
    .frame(maxWidth: 520)
    .padding(22)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    .padding()
    .accessibilityIdentifier("result-overlay")
  }

  private var settingsView: some View {
    NavigationStack {
      Form {
        Section("电脑出牌速度") {
          Slider(value: $model.aiDelay, in: 0.05...0.8)
          Text("只调整等待时间，不改变电脑规则或能力。")
            .font(.caption)
        }
        Section("声音") {
          volumeSlider("音乐", value: model.library.audio.music) {
            model.updateAudioVolume(\.music, $0)
          }
          volumeSlider("音效", value: model.library.audio.effects) {
            model.updateAudioVolume(\.effects, $0)
          }
          volumeSlider("语音", value: model.library.audio.voice) {
            model.updateAudioVolume(\.voice, $0)
          }
          Text("音乐、音效和普通话短语音分开调节。")
            .font(.caption)
        }
        Button("开始新一局", role: .destructive) {
          model.showSettings = false
          model.newGame()
        }
      }
      .navigationTitle("基础设置")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") {
            model.showSettings = false
            model.saveForBackground()
          }
        }
      }
    }
  }

  private func volumeSlider(
    _ title: String,
    value: Double,
    set: @escaping (Double) -> Void
  ) -> some View {
    HStack {
      Text(title).frame(width: 36, alignment: .leading)
      Slider(value: Binding(get: { value }, set: set), in: 0...1)
    }
  }

  private func signedScore(_ seat: Int) -> String {
    let score = model.cumulativeScores[seat]
    return "\(score >= 0 ? "+" : "")\(score)"
  }

  private func scoreName(_ seat: Int) -> String {
    if model.isEastRound { return model.windTag(seat) }
    return String(PrototypeGame.playerNames[seat].prefix(2))
  }

  private func deltaLine(_ deltas: [Int]) -> String {
    deltas.enumerated().map {
      "\(model.playerLabel($0.offset)) \($0.element >= 0 ? "+" : "")\($0.element)"
    }.joined(separator: "　")
  }
}
private enum SeatOrientation {
  case top, left, right
}
private struct HiddenHand: View {
  let count: Int
  let vertical: Bool

  var body: some View {
    Group {
      if vertical {
        VStack(spacing: 1) {
          backs
        }
      } else {
        HStack(spacing: 1) {
          backs
        }
      }
    }
  }

  @ViewBuilder
  private var backs: some View {
    ForEach(0..<count, id: \.self) { _ in
      RoundedRectangle(cornerRadius: 1.5)
        .fill(.teal.gradient)
        .overlay {
          RoundedRectangle(cornerRadius: 1.5)
            .stroke(.white.opacity(0.55), lineWidth: 0.5)
        }
        .frame(width: vertical ? 13 : 10, height: vertical ? 6 : 15)
    }
  }
}
private struct MeldRack: View {
  let melds: [Meld]
  let vertical: Bool

  private var tiles: [TileKind] { melds.flatMap(\.tiles) }

  var body: some View {
    Group {
      if tiles.isEmpty {
        Text("鸣牌 —")
          .font(.system(size: 7))
          .foregroundStyle(.secondary)
      } else if vertical {
        VStack(spacing: 0.5) {
          faces
        }
      } else {
        HStack(spacing: 0.5) {
          faces
        }
      }
    }
    .accessibilityLabel(
      tiles.isEmpty ? "没有鸣牌" : "鸣牌 \(tiles.map(\.displayName).joined(separator: "，"))")
  }

  @ViewBuilder
  private var faces: some View {
    ForEach(Array(tiles.enumerated()), id: \.offset) { _, kind in
      GraphicTileFace(kind: kind, selected: false, miniature: true)
        .frame(width: vertical ? 13 : 10, height: vertical ? 18 : 15)
    }
  }
}
private struct DiscardZone: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let title: String
  let tiles: [Tile]
  let orientation: DiscardOrientation
  let compact: Bool

  private var visibleTiles: [Tile] {
    Array(tiles.suffix(compact ? 18 : 24))
  }

  var body: some View {
    let grid = VStack(spacing: 2) {
      Text(title)
        .font(.system(size: 7, weight: .medium))
        .foregroundStyle(.secondary)
      LazyVGrid(
        columns: Array(repeating: GridItem(.fixed(compact ? 17 : 19), spacing: 1), count: 6),
        alignment: .leading,
        spacing: 1
      ) {
        ForEach(Array(visibleTiles.enumerated()), id: \.offset) { index, tile in
          GraphicTileFace(
            kind: tile.kind,
            selected: index == visibleTiles.count - 1,
            miniature: true,
            contentRotationDegrees: orientation.contentCounterRotation
          )
          .frame(width: compact ? 17 : 19, height: compact ? 23 : 26)
          .scaleEffect(!reduceMotion && index == visibleTiles.count - 1 ? 1.12 : 1)
          .animation(reduceMotion ? .none : .spring(duration: 0.22), value: tiles.count)
        }
      }
      .frame(
        width: CGFloat(6 * (compact ? 17 : 19) + 5),
        height: compact ? 72 : 106,
        alignment: .topLeading
      )
    }
    .padding(3)
    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))

    if orientation.isSide {
      grid
        .rotationEffect(.degrees(orientation == .left ? -90 : 90))
        .frame(width: compact ? 80 : 112, height: compact ? 112 : 126)
    } else {
      grid
    }
  }
}
private enum DiscardOrientation {
  case top, bottom, left, right

  var isSide: Bool { self == .left || self == .right }

  var contentCounterRotation: Double {
    switch self {
    case .left: return 90
    case .right: return -90
    case .top, .bottom: return 0
    }
  }
}
struct GraphicTileFace: View {
  let kind: TileKind
  let selected: Bool
  let miniature: Bool
  let contentRotationDegrees: Double

  init(
    kind: TileKind,
    selected: Bool,
    miniature: Bool,
    contentRotationDegrees: Double = 0
  ) {
    self.kind = kind
    self.selected = selected
    self.miniature = miniature
    self.contentRotationDegrees = contentRotationDegrees
  }

  var body: some View {
    GeometryReader { proxy in
      tileGraphic
        .rotationEffect(.degrees(contentRotationDegrees))
        .padding(miniature ? 1.5 : max(2, proxy.size.width * 0.09))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: miniature ? 1.5 : 4))
        .overlay {
          RoundedRectangle(cornerRadius: miniature ? 1.5 : 4)
            .stroke(
              selected ? Color.yellow : Color.black.opacity(0.22), lineWidth: selected ? 2 : 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: selected ? 3 : 0.5)
        .offset(y: selected && !miniature ? -4 : 0)
    }
    .aspectRatio(0.7, contentMode: .fit)
  }

  @ViewBuilder
  private var tileGraphic: some View {
    if let suit = kind.suit, let rank = kind.rank {
      if suit == .characters {
        CharacterTile(rank: rank, miniature: miniature)
      } else {
        PipPattern(suit: suit, rank: rank)
      }
    } else if let wind = kind.wind {
      Text(["东", "南", "西", "北"][wind.rawValue])
        .font(.system(size: miniature ? 8 : 27, weight: .black, design: .serif))
        .minimumScaleFactor(0.5)
        .foregroundStyle(wind == .east ? .blue : .black)
    } else if let dragon = kind.dragon {
      DragonTile(dragon: dragon, miniature: miniature)
    } else if let flower = kind.flower {
      Text(["春", "夏", "秋", "冬", "梅", "兰", "竹", "菊"][flower.rawValue])
        .font(.system(size: miniature ? 7 : 22, weight: .black, design: .serif))
        .minimumScaleFactor(0.45)
        .foregroundStyle(
          [Color.pink, .red, .orange, .blue, .pink, .purple, .green, .orange][flower.rawValue])
    }
  }
}
private struct CharacterTile: View {
  let rank: Int
  let miniature: Bool

  private var numeral: String {
    ["一", "二", "三", "四", "五", "六", "七", "八", "九"][rank - 1]
  }

  var body: some View {
    VStack(spacing: miniature ? -2 : -3) {
      Text(numeral)
        .foregroundStyle(.black)
      Text("万")
        .foregroundStyle(.red)
    }
    .font(.system(size: miniature ? 7 : 21, weight: .black, design: .serif))
    .minimumScaleFactor(0.42)
    .lineLimit(1)
  }
}
private struct DragonTile: View {
  let dragon: Dragon
  let miniature: Bool

  var body: some View {
    Group {
      switch dragon {
      case .red:
        Text("中")
          .foregroundStyle(.red)
      case .green:
        Text("发")
          .foregroundStyle(.green)
      case .white:
        RoundedRectangle(cornerRadius: miniature ? 1 : 3)
          .fill(.white)
          .overlay {
            RoundedRectangle(cornerRadius: miniature ? 1 : 3)
              .stroke(.blue, lineWidth: miniature ? 1 : 3)
          }
          .padding(miniature ? 1 : 3)
      }
    }
    .font(.system(size: miniature ? 8 : 28, weight: .black, design: .serif))
    .minimumScaleFactor(0.45)
  }
}
private struct PipPattern: View {
  let suit: Suit
  let rank: Int

  private let positions: [[Int]] = [
    [],
    [4],
    [0, 8],
    [0, 4, 8],
    [0, 2, 6, 8],
    [0, 2, 4, 6, 8],
    [0, 2, 3, 5, 6, 8],
    [0, 2, 3, 4, 5, 6, 8],
    [0, 1, 2, 3, 5, 6, 7, 8],
    [0, 1, 2, 3, 4, 5, 6, 7, 8],
  ]

  var body: some View {
    GeometryReader { proxy in
      let gap = max(0.5, proxy.size.width * 0.04)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 3),
        spacing: gap
      ) {
        ForEach(0..<9, id: \.self) { index in
          if positions[rank].contains(index) {
            mark(index: index)
          } else {
            Color.clear
          }
        }
      }
    }
  }

  @ViewBuilder
  private func mark(index: Int) -> some View {
    switch suit {
    case .dots:
      Circle()
        .fill([Color.red, .blue, .green][index % 3])
        .overlay { Circle().stroke(.black.opacity(0.18), lineWidth: 0.4) }
    case .bamboo:
      if rank == 1 {
        Image(systemName: "bird.fill")
          .resizable()
          .scaledToFit()
          .foregroundStyle(.green)
      } else {
        BambooStalk(alternate: !index.isMultiple(of: 2))
      }
    case .characters:
      Color.clear
    }
  }
}
private struct BambooStalk: View {
  let alternate: Bool

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      ZStack {
        Capsule()
          .fill(alternate ? Color.teal : Color.green)
          .frame(width: width * 0.48)
        VStack {
          Capsule()
            .fill(Color.green.opacity(0.9))
            .frame(height: max(0.7, proxy.size.height * 0.16))
          Spacer()
          Capsule()
            .fill(Color.green.opacity(0.9))
            .frame(height: max(0.7, proxy.size.height * 0.16))
        }
        Rectangle()
          .fill(.yellow.opacity(0.72))
          .frame(width: width * 0.52, height: max(0.6, proxy.size.height * 0.09))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
extension PrototypeGame {
  fileprivate var sortedPlayerTiles: [Tile] {
    game.players[0].concealed.sorted {
      if $0.kind != $1.kind { return $0.kind < $1.kind }
      return $0.copy < $1.copy
    }
  }

  fileprivate var discardRivers: [[Tile]] {
    var rivers = Array(repeating: [Tile](), count: 4)
    var pendingDiscardSeat: Int?
    for event in game.events {
      switch event {
      case let .discarded(seat, tile):
        rivers[seat].append(tile)
        pendingDiscardSeat = seat
      case .claimed:
        if let seat = pendingDiscardSeat, !rivers[seat].isEmpty {
          rivers[seat].removeLast()
        }
        pendingDiscardSeat = nil
      case .drew:
        pendingDiscardSeat = nil
      default:
        break
      }
    }
    return rivers
  }

  fileprivate var currentActorName: String {
    switch game.phase {
    case let .awaitingDraw(seat), let .awaitingDiscard(seat):
      return playerLabel(seat)
    case let .awaitingResponses(discarder, _):
      return "响应\(playerLabel(discarder))"
    case let .awaitingRobKong(declarer, _, _):
      return "抢杠响应\(playerLabel(declarer))"
    case .endedDraw, .endedWin:
      return "本局结束"
    }
  }

  fileprivate var currentOperationTitle: String {
    if result != nil { return "本局结束" }
    if isPaused { return "已暂停" }
    if !actions.isEmpty { return "请选择：\(actions.map(\.title).joined(separator: " / "))" }
    switch game.phase {
    case .awaitingDiscard(seat: 0): return "请选择一张牌打出"
    case .awaitingDraw(seat: 0): return "正在摸牌"
    case let .awaitingDiscard(seat), let .awaitingDraw(seat):
      return "\(playerLabel(seat))正在操作"
    case .awaitingResponses: return "等待吃 / 碰 / 杠 / 和 / 过"
    case .awaitingRobKong: return "等待抢杠和 / 过"
    case .endedDraw, .endedWin: return "本局结束"
    }
  }

  fileprivate var operationHint: String {
    switch game.phase {
    case .awaitingDiscard(seat: 0): return "点选手牌后打出"
    case .awaitingResponses: return "等待响应"
    case .awaitingRobKong: return "等待抢杠"
    default: return "等待对手操作"
    }
  }
}
