import MahjongRules
import SpriteKit
import SwiftUI

struct MahjongGameView: View {
  @StateObject private var model = PrototypeGame()
  @Environment(\.scenePhase) private var scenePhase

  private let boardScene: GameScene = {
    let scene = GameScene(size: CGSize(width: 1_200, height: 700))
    scene.scaleMode = .resizeFill
    return scene
  }()

  var body: some View {
    Group {
      switch model.route {
      case .home:
        HomeMenu(model: model)
      case .more:
        MoreMenu(model: model)
      case .settings:
        SettingsPage(model: model)
      case .table:
        M3LandscapeTable(model: model)
      case .career:
        CareerMenu(model: model)
      case .stats:
        StatsPage(model: model)
      case .achievements:
        AchievementsPage(model: model)
      case .guides:
        FanGuidePage(model: model)
      case .replays:
        ReplayListPage(model: model)
      case let .replay(id):
        ReplayPage(model: model, recordID: id)
      case .help:
        RulesHelpPage(model: model)
      case .appearance:
        AppearancePage(model: model)
      }
    }
    .preferredColorScheme(.dark)
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { model.saveForBackground() }
    }
    .onAppear {
      TableSound.shared.sync(model.library.audio, calm: model.musicIsCalm)
    }
  }

  private var header: some View {
    HStack {
      Text("单机国标麻将 · 一盘")
        .font(.headline)
      Text("东圈")
        .font(.subheadline)
        .foregroundStyle(.yellow)
      Spacer()
      Text("牌墙 \(model.game.wall.remainingCount) 张")
        .monospacedDigit()
      Button(model.isPaused ? "继续" : "暂停") {
        model.togglePause()
      }
      .buttonStyle(.bordered)
      Button("设置") {
        model.showSettings = true
      }
      .buttonStyle(.bordered)
    }
    .font(.caption)
  }

  private var opponents: some View {
    HStack(spacing: 10) {
      ForEach(1..<4, id: \.self) { seat in
        VStack(spacing: 3) {
          HStack {
            Text(PrototypeGame.playerNames[seat])
              .fontWeight(.semibold)
            Spacer()
            Text(scoreText(seat))
              .monospacedDigit()
          }
          HStack(spacing: 2) {
            Text("🀫 × \(model.game.players[seat].concealed.count)")
            Spacer()
            if !model.game.players[seat].melds.isEmpty {
              Text(model.game.players[seat].melds.map(meldText).joined(separator: " · "))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            }
            if !model.game.players[seat].flowers.isEmpty {
              Text("花 \(model.game.players[seat].flowers.count)")
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
      }
    }
  }

  private var tableCenter: some View {
    VStack(spacing: 7) {
      Text(model.message)
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.black.opacity(0.36), in: Capsule())

      ScrollView(.horizontal) {
        HStack(spacing: 4) {
          if model.game.discards.isEmpty {
            Text("弃牌区")
              .foregroundStyle(.secondary)
          } else {
            ForEach(Array(model.game.discards.suffix(28).enumerated()), id: \.offset) {
              _, tile in
              Text(tile.kind.displayName)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 31, height: 40)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
            }
          }
        }
      }
      .scrollIndicators(.hidden)
      .frame(height: 44)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var actionBar: some View {
    HStack(spacing: 8) {
      ForEach(model.actions) { action in
        Button(action.title) {
          model.perform(action)
        }
        .buttonStyle(.borderedProminent)
        .tint(action == .win ? .red : (action == .skip ? .gray : .orange))
        .accessibilityIdentifier("action-\(action.id)")
      }

      if case .awaitingDiscard(seat: 0) = model.game.phase {
        Button("打出选中牌") {
          model.discardSelected()
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(model.selectedTile == nil)
        .accessibilityIdentifier("discard-button")
        .accessibilityLabel(
          model.selectedTile.map { "打出\($0.kind.displayName)" } ?? "打出选中的牌"
        )
      }
    }
    .frame(minHeight: 36)
  }

  private var playerArea: some View {
    VStack(spacing: 5) {
      HStack {
        Text("你的手牌")
          .font(.caption.bold())
        Text(scoreText(0))
          .font(.caption.monospacedDigit())
        if !model.game.players[0].melds.isEmpty {
          Text(model.game.players[0].melds.map(meldText).joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(.yellow)
        }
        if !model.game.players[0].flowers.isEmpty {
          Text("花牌 \(model.game.players[0].flowers.count)")
            .font(.caption2)
        }
        Spacer()
        Text("点牌后点击“打出”")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      ScrollView(.horizontal) {
        HStack(spacing: 4) {
          ForEach(sortedPlayerTiles, id: \.self) { tile in
            Button {
              model.select(tile)
            } label: {
              TileFace(kind: tile.kind, selected: model.selectedTile == tile)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tile-\(tile.kind.rawValue)-\(tile.copy)")
            .accessibilityLabel(tile.kind.displayName)
            .accessibilityAddTraits(model.selectedTile == tile ? .isSelected : [])
          }
        }
        .padding(.top, 6)
      }
      .scrollIndicators(.hidden)
      .frame(height: 70)
    }
    .padding(8)
    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 12))
  }

  private var pauseOverlay: some View {
    VStack(spacing: 14) {
      Text("牌局已暂停")
        .font(.title2.bold())
      Text("当前进度已经自动保存")
        .foregroundStyle(.secondary)
      Button("继续") { model.togglePause() }
        .buttonStyle(.borderedProminent)
    }
    .padding(28)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
  }

  private func resultOverlay(_ result: RoundResult) -> some View {
    VStack(spacing: 10) {
      if result.isDraw {
        Text("流局")
          .font(.largeTitle.bold())
        Text("牌墙已摸完，本局无人和牌")
      } else if let winner = result.winner, let score = result.score {
        Text("\(PrototypeGame.playerNames[winner])和牌")
          .font(.title.bold())
        Text(result.discarder == nil ? "自摸" : "\(PrototypeGame.playerNames[result.discarder!])放铳")
          .foregroundStyle(.secondary)
        Text(score.awards.map { "\($0.fan.name) \($0.points)番" }.joined(separator: " · "))
          .multilineTextAlignment(.center)
          .font(.subheadline)
        Text("合计 \(score.totalPoints) 番")
          .font(.title3.bold())
          .foregroundStyle(.yellow)
        Text(
          result.deltas.enumerated().map {
            "\(PrototypeGame.playerNames[$0.offset]) \($0.element >= 0 ? "+" : "")\($0.element)"
          }.joined(separator: "　")
        )
        .font(.caption.monospacedDigit())
      }
      Button("再来一局") {
        model.newGame()
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: 560)
    .padding(26)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    .padding()
    .accessibilityIdentifier("result-overlay")
  }

  private var settingsView: some View {
    NavigationStack {
      Form {
        Section("电脑出牌速度") {
          Slider(value: $model.aiDelay, in: 0.05...0.8)
          Text("仅调整演示等待，不改变电脑规则或能力。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Section("原型说明") {
          Text("电脑只选择规则引擎给出的第一个合法动作，不读取暗牌。")
          Button("开始新一局", role: .destructive) {
            model.showSettings = false
            model.newGame()
          }
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

  private var sortedPlayerTiles: [Tile] {
    model.game.players[0].concealed.sorted {
      if $0.kind != $1.kind { return $0.kind < $1.kind }
      return $0.copy < $1.copy
    }
  }

  private func scoreText(_ seat: Int) -> String {
    let score = model.cumulativeScores[seat]
    return "\(score >= 0 ? "+" : "")\(score)"
  }

  private func meldText(_ meld: Meld) -> String {
    let prefix: String
    switch meld.type {
    case .chow: prefix = "吃"
    case .pung: prefix = "碰"
    case .exposedKong, .addedKong: prefix = "明杠"
    case .concealedKong: prefix = "暗杠"
    }
    return prefix + meld.tiles.map(\.displayName).joined()
  }
}
private struct TileFace: View {
  let kind: TileKind
  let selected: Bool

  var body: some View {
    VStack(spacing: 1) {
      if let rank = kind.rank {
        Text("\(rank)")
          .font(.title3.bold())
        Text(["万", "筒", "条"][kind.suit!.rawValue])
          .font(.caption.bold())
          .foregroundStyle(suitColor)
      } else {
        Text(kind.displayName)
          .font(.title3.bold())
          .foregroundStyle(honorColor)
      }
    }
    .foregroundStyle(.black)
    .frame(width: 42, height: 58)
    .background(.white, in: RoundedRectangle(cornerRadius: 5))
    .overlay {
      RoundedRectangle(cornerRadius: 5)
        .stroke(selected ? Color.yellow : Color.black.opacity(0.18), lineWidth: selected ? 3 : 1)
    }
    .offset(y: selected ? -6 : 0)
    .shadow(radius: selected ? 4 : 1)
  }

  private var suitColor: Color {
    switch kind.suit {
    case .characters: return .red
    case .dots: return .blue
    case .bamboo: return .green
    case nil: return .black
    }
  }

  private var honorColor: Color {
    if kind == .red { return .red }
    if kind == .green { return .green }
    return .black
  }
}
