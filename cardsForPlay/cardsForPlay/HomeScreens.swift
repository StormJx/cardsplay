import MahjongAI
import MahjongProgress
import MahjongRules
import SwiftUI

struct HomeMenu: View {
  @ObservedObject var model: PrototypeGame

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        Text("单机国标麻将")
          .font(.title2.bold())
          .frame(maxWidth: .infinity, alignment: .leading)
        if hasUnfinishedSession {
          menu("继续牌局", "home-continue") { model.continueGame() }
        }
        menu("快速一盘", "home-quick") { model.beginSetup(mode: .quick) }
        menu("东风圈", "home-round") { model.beginSetup(mode: .round) }
        menu("生涯", "home-career") { model.route = .career }
        menu("更多", "home-more") { model.route = .more }
      }
      .padding(16)
      .frame(maxWidth: 360)
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.04, green: 0.16, blue: 0.12))
  }

  private var hasUnfinishedSession: Bool {
    guard let session = model.library.session else { return false }
    let handOpen = session.winner == nil && !session.drawn
    if session.mode == .round {
      return handOpen || !EastRound.isFinalHand(session.roundHandIndex ?? 0)
    }
    return handOpen
  }

  private func menu(_ title: String, _ identifier: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.borderedProminent)
    .tint(.teal)
    .accessibilityIdentifier(identifier)
  }
}

struct MoreMenu: View {
  @ObservedObject var model: PrototypeGame

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        pageHeader("更多", model: model)
        menu("练习一盘", "home-practice") { model.beginSetup(mode: .practice) }
        menu("战绩", "home-stats") { model.route = .stats }
        menu("成就", "home-achievements") { model.route = .achievements }
        menu("番种图鉴", "home-guides") {
          model.highlightedFan = nil
          model.route = .guides
        }
        menu("牌谱", "home-replays") { model.route = .replays }
        menu("规则要点", "home-help") { model.route = .help }
        menu("设置", "home-settings") { model.route = .settings }
      }
      .padding(16)
      .frame(maxWidth: 360)
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.04, green: 0.16, blue: 0.12))
  }

  private func menu(_ title: String, _ identifier: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.borderedProminent)
    .tint(.teal)
    .accessibilityIdentifier(identifier)
  }
}

struct SettingsPage: View {
  @ObservedObject var model: PrototypeGame

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        pageHeader("设置", model: model, backTitle: "返回更多") { model.route = .more }
        Text("电脑出牌速度").font(.headline)
        VStack(spacing: 8) {
          speedButton("慢", 0.65)
          speedButton("标准", 0.22)
          speedButton("快", 0.06)
        }
        Text("只调整等待时间，不改变电脑规则或能力。")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("声音").font(.headline)
        volumeSlider("音乐", value: model.library.audio.music) {
          model.updateAudioVolume(\.music, $0)
        }
        volumeSlider("音效", value: model.library.audio.effects) {
          model.updateAudioVolume(\.effects, $0)
        }
        volumeSlider("语音", value: model.library.audio.voice) {
          model.updateAudioVolume(\.voice, $0)
        }
      }
      .padding(16)
      .frame(maxWidth: 360)
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.04, green: 0.16, blue: 0.12))
  }

  private func speedButton(_ title: String, _ delay: Double) -> some View {
    let selected = abs(model.aiDelay - delay) < 0.001
    return Button {
      model.aiDelay = delay
      model.saveForBackground()
    } label: {
      Text(title).frame(maxWidth: .infinity, minHeight: 36)
    }
    .buttonStyle(.borderedProminent)
    .tint(selected ? .teal : .gray)
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
}

struct CareerMenu: View {
  @ObservedObject var model: PrototypeGame

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        pageHeader("生涯", model: model)
        ForEach(CareerCatalog.chapters) { chapter in
          VStack(alignment: .leading, spacing: 6) {
            Text("第\(chapter.number)章 \(chapter.title)")
              .font(.headline)
            Text(chapter.theme).font(.caption).foregroundStyle(.secondary)
            if chapter.number == 1 {
              ForEach(chapter.levels) { level in
                Button {
                  model.beginCareer(level)
                } label: {
                  levelRow(level)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("career-\(level.id)")
              }
            } else {
              ForEach(chapter.levels) { level in
                levelRow(level)
                  .opacity(0.55)
              }
              Text("这一章只保留关卡和星级数据，还不能开打。")
                .font(.caption2)
                .foregroundStyle(.orange)
            }
          }
          .padding(10)
          .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .padding(14)
    }
  }

  private func levelRow(_ level: CareerLevel) -> some View {
    let stars = model.library.career.bestStars[level.id] ?? 0
    return HStack {
      Text(level.isBoss ? "Boss" : "\(level.index)")
        .font(.caption.bold())
        .frame(width: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(level.title).font(.subheadline.bold())
        Text(level.playable ? level.briefing : "尚未开放")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
      Text(starText(stars))
        .font(.caption)
        .foregroundStyle(.yellow)
    }
  }
}

struct StatsPage: View {
  @ObservedObject var model: PrototypeGame
  @State private var filter = "全部"

  private var mode: PlayMode? {
    switch filter {
    case "快速": return .quick
    case "完整": return .full
    case "生涯": return .career
    case "练习": return .practice
    default: return nil
    }
  }

  var body: some View {
    let stats = RecordBook.stats(model.library.records, mode: mode)
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        pageHeader("战绩", model: model)
        Picker("范围", selection: $filter) {
          ForEach(["全部", "快速", "完整", "生涯", "练习"], id: \.self) { Text($0) }
        }
        .pickerStyle(.segmented)
        Text("数字由已保存牌谱重算。练习和快速分开。完整对局还没有牌可记。")
          .font(.caption2)
          .foregroundStyle(.secondary)
        grid([
          ("牌局", "\(stats.hands)"),
          ("第一名", rate(stats.firsts, stats.hands)),
          ("平均名次", stats.hands == 0 ? "—" : String(format: "%.2f", Double(stats.rankSum) / Double(stats.hands))),
          ("和牌率", rate(stats.wins, stats.hands)),
          ("自摸率", rate(stats.selfDraws, stats.hands)),
          ("点炮率", rate(stats.dealIns, stats.hands)),
          ("流局率", rate(stats.draws, stats.hands)),
          ("平均番", stats.wins == 0 ? "—" : String(format: "%.1f", Double(stats.fanSum) / Double(stats.wins))),
          ("最大番", stats.wins == 0 ? "—" : "\(stats.maxFan) \(stats.maxFanName)"),
          ("吃碰杠", "\(stats.chows)/\(stats.pungs)/\(stats.kongs)"),
          ("门前和牌", rate(stats.concealedWins, stats.wins)),
          ("近况", stats.recentDeltas.map { "\($0 >= 0 ? "+" : "")\($0)" }.joined(separator: " ")),
        ])
        let topFans = stats.fanCounts.sorted { $0.value > $1.value }.prefix(8)
        if !topFans.isEmpty {
          Text("和出过的番")
            .font(.headline)
          Text(topFans.map { "\(Fan(rawValue: $0.key)?.name ?? "") \($0.value)" }.joined(separator: " · "))
            .font(.caption)
        }
      }
      .padding(14)
    }
  }

  private func rate(_ part: Int, _ total: Int) -> String {
    guard total > 0 else { return "—" }
    return "\(part)/\(total)"
  }

  private func grid(_ rows: [(String, String)]) -> some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        VStack(alignment: .leading, spacing: 2) {
          Text(row.0).font(.caption2).foregroundStyle(.secondary)
          Text(row.1).font(.subheadline.bold()).lineLimit(2)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }
}

struct AchievementsPage: View {
  @ObservedObject var model: PrototypeGame

  var body: some View {
    let items = AchievementBook.evaluate(
      records: model.library.records, career: model.library.career)
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        pageHeader("成就", model: model)
        Text("只解锁本地记录，不改变胜率。")
          .font(.caption)
          .foregroundStyle(.secondary)
        ForEach(items) { item in
          HStack(alignment: .top) {
            Image(systemName: item.unlocked ? "checkmark.seal.fill" : "seal")
              .foregroundStyle(item.unlocked ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 2) {
              Text("\(item.title) · \(item.category)").font(.subheadline.bold())
              Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
          }
          .padding(8)
          .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
      }
      .padding(14)
    }
  }
}

struct FanGuidePage: View {
  @ObservedObject var model: PrototypeGame
  @State private var points = 0

  var body: some View {
    let guides = FanGuideBook.all.filter { points == 0 || $0.points == points }
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        pageHeader("番种图鉴", model: model)
        Text("81 番都来自当前规则表 \(MCRRuleBook.version)。未和出的番也可以看。")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Picker("番值", selection: $points) {
          Text("全部").tag(0)
          ForEach([88, 64, 48, 32, 24, 16, 12, 8, 6, 4, 2, 1], id: \.self) { value in
            Text("\(value)").tag(value)
          }
        }
        .pickerStyle(.segmented)
        if let raw = model.highlightedFan, let fan = Fan(rawValue: raw) {
          guideCard(FanGuideBook.guide(fan))
        }
        ForEach(guides) { guide in
          if guide.fan.rawValue != model.highlightedFan {
            guideCard(guide)
          }
        }
      }
      .padding(14)
    }
  }

  private func guideCard(_ guide: FanGuide) -> some View {
    let times = FanGuideBook.timesAchieved(guide.fan, records: model.library.records)
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(guide.points)番 \(guide.name)").font(.headline)
        Spacer()
        Text(times > 0 ? "已和出 \(times) 次" : "尚未和出")
          .font(.caption2)
          .foregroundStyle(times > 0 ? .yellow : .secondary)
      }
      Text(guide.summary).font(.caption)
      Text("限制：\(guide.limit)").font(.caption2).foregroundStyle(.secondary)
      Text("示例：\(guide.example)").font(.caption2)
      Text("不计：\(guide.excludedNames)").font(.caption2).foregroundStyle(.secondary)
      Text(guide.pitfall).font(.caption2).foregroundStyle(.orange)
      if let record = FanGuideBook.bestRecord(for: guide.fan, records: model.library.records) {
        Button("打开这一番的牌谱") { model.openReplay(record.id) }
          .font(.caption)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }
}

struct ReplayListPage: View {
  @ObservedObject var model: PrototypeGame

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        pageHeader("牌谱", model: model)
        if model.library.records.isEmpty {
          Text("打完一局后会留在这里。最多保留 \(ProgressLibrary.transcriptLimit) 局。")
            .foregroundStyle(.secondary)
        }
        ForEach(model.library.records.reversed()) { record in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("\(record.mode.displayName) · \(record.difficulty.displayName)")
                .font(.subheadline.bold())
              Text(summary(record))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if record.canReplay {
              Button("复盘") { model.openReplay(record.id) }
                .buttonStyle(.bordered)
            } else {
              Text("不能逐步回放")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Button("删除") { model.deleteRecord(record.id) }
              .buttonStyle(.bordered)
              .tint(.red)
          }
          .padding(8)
          .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
      }
      .padding(14)
    }
  }

  private func summary(_ record: HandRecord) -> String {
    if record.isDraw { return "流局" }
    let who = record.winner == 0 ? "你和牌" : "对手和牌"
    let fans = record.awardFans.prefix(4).compactMap { Fan(rawValue: $0)?.name }.joined(separator: " ")
    return "\(who) \(record.fanPoints)番 \(fans)"
  }
}

struct ReplayPage: View {
  @ObservedObject var model: PrototypeGame
  let recordID: UUID
  @State private var index = 0
  @State private var reveal = false
  @State private var frames: [ReplayFrame] = []
  @State private var notes: [ReplayNote] = []
  @State private var failure: String?
  @State private var difficulty = AIDifficulty.normal
  @State private var dealer = 0
  @State private var roundReplay = false
  @State private var playing = false
  @State private var stopAtChecks = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button("返回牌谱") {
          playing = false
          model.route = .replays
        }
        Spacer()
        Toggle("全牌揭示", isOn: $reveal)
          .toggleStyle(.button)
          .font(.caption)
      }
      if let failure {
        Text(failure).foregroundStyle(.orange)
        Spacer()
      } else if frames.isEmpty {
        ProgressView()
        Spacer()
      } else {
        replayBody
      }
    }
    .padding(12)
    .onAppear(perform: load)
    .onDisappear { playing = false }
    .task(id: playing) { await autoplay() }
  }

  private var replayBody: some View {
    let frame = frames[min(index, frames.count - 1)]
    let advice = HandReplay.advice(
      state: frame.state, difficulty: difficulty, scores: [0, 0, 0, 0])
    return VStack(alignment: .leading, spacing: 6) {
      Text("第 \(index)/\(frames.count - 1) 步 · \(phaseText(frame.state.phase))")
        .font(.headline)
      if reveal {
        Text("全牌揭示只用于结束后的分析。电脑当时不知道这些暗牌。")
          .font(.caption2)
          .foregroundStyle(.orange)
      }
      ForEach(1..<4, id: \.self) { seat in
        Text(seatLine(seat, state: frame.state))
          .font(.caption2)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 3) {
          ForEach(frame.state.players[0].concealed.sorted(by: { $0.kind < $1.kind }), id: \.self) {
            tile in
            GraphicTileFace(kind: tile.kind, selected: false, miniature: false)
              .frame(width: 28, height: 40)
          }
        }
      }
      .frame(height: 44)
      if !advice.isEmpty, case .awaitingDiscard(seat: 0) = frame.state.phase {
        Text(
          "当时可见信息的前三个选择："
            + advice.map {
              "\($0.tile.displayName) 效\($0.efficiency) 危\($0.dangerLabel)"
            }.joined(separator: " · ")
        )
        .font(.caption2)
      }
      let here = notes.filter { $0.frameIndex == index }
      if !here.isEmpty {
        Text(here.map(\.text).joined(separator: " "))
          .font(.caption)
          .foregroundStyle(.yellow)
      }
      HStack {
        Button(playing ? "暂停" : "播放") { togglePlayback() }
          .accessibilityIdentifier("replay-play")
        Toggle("停在关键", isOn: $stopAtChecks)
          .toggleStyle(.button)
          .accessibilityIdentifier("replay-stop-checks")
        Button("下一关键") { jumpToCheckpoint() }
          .accessibilityIdentifier("replay-next-check")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      Text("自动按顺序播放。打开「停在关键」会停在点炮、放过的和、漏掉的暗杠。")
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack {
        Button("上一步") { step(by: -1) }
        Button("下一步") { step(by: 1) }
        Button("摸牌") { jump(.draw) }
        Button("鸣牌") { jump(.claim) }
        Button("和牌") { jump(.win) }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
  }

  private func togglePlayback() {
    if playing {
      playing = false
      return
    }
    if frames.isEmpty { return }
    if index >= frames.count - 1 { index = 0 }
    playing = true
  }

  private func step(by delta: Int) {
    playing = false
    index = min(max(0, index + delta), max(0, frames.count - 1))
  }

  private func jumpToCheckpoint() {
    playing = false
    let stops = HandReplay.checkpointIndexes(notes: notes)
    guard let next = stops.first(where: { $0 > index }) ?? stops.first else { return }
    index = next
  }

  private func autoplay() async {
    guard playing else { return }
    while !Task.isCancelled && playing {
      try? await Task.sleep(nanoseconds: 700_000_000)
      if Task.isCancelled || !playing { return }
      let step = HandReplay.advance(
        index: index,
        frameCount: frames.count,
        stopAtChecks: stopAtChecks,
        checkpoints: HandReplay.checkpointIndexes(notes: notes)
      )
      index = step.index
      playing = step.playing
    }
  }

  private func load() {
    playing = false
    guard let record = model.library.records.first(where: { $0.id == recordID }) else {
      failure = "找不到这局牌谱"
      return
    }
    guard record.canReplay else {
      failure = "这局没有完整步骤，不能逐步回放"
      return
    }
    do {
      dealer = record.dealerSeat ?? 0
      roundReplay = record.mode == .round
      let built = try HandReplay.frames(seed: record.seed, steps: record.steps, dealer: dealer)
      frames = built
      notes = HandReplay.notes(frames: built, dealer: dealer)
      difficulty = record.difficulty
      index = 0
    } catch {
      failure = "牌谱无法按原规则版本重放"
    }
  }

  private func jump(_ kind: HandReplay.Jump) {
    playing = false
    let indexes = HandReplay.jumpIndexes(frames: frames, kind: kind)
    guard let next = indexes.first(where: { $0 > index }) ?? indexes.first else { return }
    index = next
  }

  private func phaseText(_ phase: HandPhase) -> String {
    switch phase {
    case let .awaitingDraw(seat): return "\(replayName(seat))摸牌"
    case let .awaitingDiscard(seat): return "\(replayName(seat))出牌"
    case .awaitingResponses: return "等待响应"
    case .awaitingRobKong: return "抢杠"
    case .endedDraw: return "流局"
    case let .endedWin(seat): return "\(replayName(seat))和牌"
    }
  }

  private func replayName(_ seat: Int) -> String {
    guard roundReplay else { return PrototypeGame.playerNames[seat] }
    let bases = ["你", "阿岚", "静川", "墨衡"]
    let winds = ["东", "南", "西", "北"]
    let wind = EastRound.seatWind(seat: seat, dealer: dealer)
    let tag = seat == dealer ? "\(winds[wind.rawValue])庄" : winds[wind.rawValue]
    return "\(bases[seat])（\(tag)）"
  }

  private func seatLine(_ seat: Int, state: GameState) -> String {
    let name = replayName(seat)
    if reveal {
      let tiles = state.players[seat].concealed.map(\.kind.displayName).joined(separator: " ")
      return "\(name) 暗牌 \(tiles)"
    }
    return "\(name) 暗牌 \(state.players[seat].concealed.count) 张"
  }
}

struct RulesHelpPage: View {
  @ObservedObject var model: PrototypeGame

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        pageHeader("规则要点", model: model)
        Text("和牌、吃碰杠和计番都由规则引擎判定。这里只是入口说明。")
          .font(.caption)
          .foregroundStyle(.secondary)
        help("8 番起和", "花牌可以加最终分，但不能用来凑够 8 番。不够 8 番时不出现和按钮。")
        help("先后", "和牌优先于碰、杠、吃。吃只能吃上家。抢杠只针对补杠。")
        help("结算", "自摸三家都付底分加番分。点和时放铳者付底分加番分，另外两家付底分。")
        help("提示", "练习模式的推荐、危险度和未见张数只使用你的手牌和桌面公开牌。")
        Button("打开番种图鉴") {
          model.highlightedFan = nil
          model.route = .guides
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(14)
    }
  }

  private func help(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.headline)
      Text(body).font(.caption)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }
}

private func pageHeader(
  _ title: String,
  model: PrototypeGame,
  backTitle: String = "返回主页",
  back: (() -> Void)? = nil
) -> some View {
  HStack {
    Text(title).font(.title2.bold())
    Spacer()
    Button(backTitle) {
      if let back {
        back()
      } else {
        model.route = .home
      }
    }
    .buttonStyle(.bordered)
  }
}

private func starText(_ stars: Int) -> String {
  String(repeating: "★", count: stars) + String(repeating: "☆", count: max(0, 3 - stars))
}
