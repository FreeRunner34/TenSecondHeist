import SwiftUI

struct HeistScreen: View {
    let level: LevelDefinition
    @EnvironmentObject private var game: GameContext
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var plan = Plan()
    @State private var simulation: SimulationResult?
    @State private var selected: Role = .thief
    @State private var tick = 0
    @State private var playing = false
    @State private var slow = false
    @State private var halfBeat = false
    @State private var attempted = false
    @State private var recorded = false
    @State private var discardedPlan: Plan?
    @State private var confirmReset = false
    @State private var showHelp = false
    @State private var exportError: String?
    @State private var exporting = false
    @State private var previewURL: ReplayURL?
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var frame: SimulationFrame {
        (simulation ?? SimulationEngine.run(plan, level: level)).frame(at: tick)
    }
    private var nextLevel: LevelDefinition? {
        guard let index = game.levels.firstIndex(where: { $0.id == level.id }),
              index + 1 < game.levels.count else { return nil }
        return game.levels[index + 1]
    }
    private var nextLevelIndex: Int? {
        guard let index = game.levels.firstIndex(where: { $0.id == level.id }),
              index + 1 < game.levels.count else { return nil }
        return index + 1
    }
    private var currentPosition: Tile {
        plan[selected].compactMap { $0.kind == .move ? $0.at : nil }.last ?? level.start(selected) ?? Tile(0, 0)
    }
    private var trainingNote: String? {
        switch level.id {
        case "heist-01": "Tap Thief. Draw to the gold diamond, tap TAKE, then draw to EXIT. Press GO when ready."
        case "heist-02": "The guard repeats the same route. Scrub the timeline to watch its position before you plan."
        case "heist-03": "Camera B turns every two seconds. Add a WAIT to let its view pass before crossing."
        case "heist-04": "Crew plans run at the same time. Select Hacker to reach the terminal, then time the Thief's route."
        case "heist-05": "Select Decoy and tap DISTRACT to turn a nearby guard toward the signal for three seconds."
        default: nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(level.site.uppercased()).font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(2).foregroundStyle(HeistStyle.site(level.site))
                        Text(level.title).font(.system(size: 27, weight: .black, design: .rounded))
                            .foregroundStyle(HeistStyle.cream)
                    }
                    Spacer()
                    Text(String(format: "%04.2f", Double(tick) / 4))
                        .font(.system(size: 25, weight: .black, design: .monospaced))
                        .foregroundStyle(tick >= 36 ? HeistStyle.warning : HeistStyle.gold)
                    Text("/ 10").font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(HeistStyle.muted).padding(.top, 10)
                }
                Text(level.briefing).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HeistStyle.muted).fixedSize(horizontal: false, vertical: true)
                if let trainingNote {
                    Label(trainingNote, systemImage: "lightbulb.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HeistStyle.cream)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(HeistStyle.raised, in: RoundedRectangle(cornerRadius: 11))
                }
                HStack(spacing: 8) {
                    objective("\(level.loot.count) TO TAKE", symbol: "diamond.fill")
                    objective("EXIT BY 10s", symbol: "door.left.hand.open")
                    objective("PERFECT ≤\(level.actionTarget)", symbol: "sparkles")
                }
                BoardCanvas(level: level, plan: plan, frame: frame, selectedRole: selected,
                            editing: !playing, onTile: route(to:))
                    .accessibilityHint("Select a crew member, then drag along floor tiles to plan a route.")
                HStack(spacing: 8) {
                    ForEach(level.roles) { role in
                        Button { selected = role; playing = false } label: {
                            HStack(spacing: 5) {
                                Image(systemName: role.symbol)
                                Text(role.name)
                            }.font(.system(size: 12, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 43)
                                .foregroundStyle(selected == role ? HeistStyle.ink : HeistStyle.role(role))
                                .background(selected == role ? HeistStyle.role(role) : HeistStyle.panel,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                Text("Draw a route for \(selected.name). Add an action at the last tile. Every move takes 0.5s.")
                    .font(.system(size: 11)).foregroundStyle(HeistStyle.muted)
                actionControls
                timeline
                HStack(spacing: 9) {
                    HeistButton(text: playing ? "PAUSE" : attempted && tick > 0 ? "RESUME" : "GO",
                                symbol: playing ? "pause.fill" : "play.fill", prominent: true) {
                        startOrPause()
                    }
                    HeistButton(text: "REWIND", symbol: "backward.end.fill") {
                        playing = false; tick = 0
                    }
                }
                HStack(spacing: 9) {
                    HeistButton(text: slow ? "1× SPEED" : "0.5× SPEED", symbol: "tortoise.fill") { slow.toggle() }
                    HeistButton(text: "RETRY PLAN", symbol: "arrow.clockwise") {
                        playing = false; attempted = false; recorded = false; tick = 0
                    }
                }
                if attempted, let simulation, tick >= simulation.outcome.tick {
                    resultCard(simulation)
                }
                if let exportError { Text(exportError).font(.footnote).foregroundStyle(HeistStyle.warning) }
                if (progress.save.failures[level.id] ?? 0) >= 3 {
                    Button("Need an edge? Optional Inside Help") { showHelp = true }
                        .font(.footnote).foregroundStyle(HeistStyle.teal).padding(.vertical, 8)
                }
            }.padding(.horizontal, 16).padding(.vertical, 14)
        }
        .background(HeistBackground())
        .navigationTitle(String(format: "HEIST %02d", (game.levels.firstIndex(where: { $0.id == level.id }) ?? 0) + 1))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showHelp = true } label: { Image(systemName: "lightbulb") }.accessibilityLabel("Inside Help")
                Button { confirmReset = true } label: { Image(systemName: "trash") }.accessibilityLabel("Reset plan")
            }
        }
        .confirmationDialog("Erase this plan?", isPresented: $confirmReset) {
            Button("Reset plan", role: .destructive) {
                discardedPlan = plan; change(Plan())
            }
        } message: { Text("You can undo the reset immediately.") }
        .sheet(isPresented: $showHelp) {
            AssistanceScreen(level: level).presentationDetents([.medium, .large])
                .onDisappear { recompute() }
        }
        .sheet(item: $previewURL) { file in ReplayPreview(url: file.url) }
        .onAppear {
            plan = progress.plan(for: level)
            selected = level.roles.first ?? .thief
            recompute()
        }
        .onReceive(clock) { _ in
            guard playing else { return }
            if slow { halfBeat.toggle(); if halfBeat { return } }
            tick = min(40, tick + 1)
            if let simulation, tick >= simulation.outcome.tick { playing = false; record(simulation) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
    }

    private var actionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("STEP").font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(HeistStyle.muted).frame(width: 44, alignment: .leading)
                ForEach([Heading.north, .west, .south, .east], id: \.rawValue) { direction in
                    let destination = Tile(currentPosition.x + Int(direction.vector.x),
                                           currentPosition.y + Int(direction.vector.y))
                    Button { route(to: destination) } label: {
                        Image(systemName: arrow(direction))
                            .font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(HeistStyle.raised, in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).foregroundStyle(HeistStyle.role(selected))
                        .disabled(!level.isWalkable(destination))
                        .accessibilityLabel("Add one step \(direction.rawValue) for \(selected.name)")
                }
            }
            HStack(spacing: 8) {
                actionButton("WAIT .5s", icon: "hourglass") { append(.wait(2)) }
                actionButton("WAIT 1s", icon: "clock") { append(.wait(4)) }
                if selected == .thief,
                   let loot = level.loot.first(where: { $0.at == currentPosition && !plan[.thief].contains(.take($0.id)) }) {
                    actionButton("TAKE", icon: "diamond.fill") { append(.take(loot.id)) }
                }
                if selected == .hacker,
                   let terminal = level.terminals.first(where: { $0.at == currentPosition || $0.at.adjacent(to: currentPosition) }) {
                    actionButton("HACK", icon: "power") { append(.hack(terminal.id)) }
                }
                if selected == .decoy { actionButton("DISTRACT", icon: "speaker.wave.2.fill") { append(.distract) } }
            }
            HStack(spacing: 10) {
                Button { var altered = plan; if !altered[selected].isEmpty { altered[selected].removeLast(); change(altered) } } label: {
                    Label("Undo last action", systemImage: "arrow.uturn.backward")
                }.disabled(plan[selected].isEmpty)
                if let discardedPlan {
                    Button("Undo reset") { change(discardedPlan); self.discardedPlan = nil }
                }
            }.font(.system(size: 12, weight: .semibold)).foregroundStyle(HeistStyle.teal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(plan[selected].indices, id: \.self) { index in
                        let action = plan[selected][index]
                        Button { var altered = plan; altered[selected].removeSubrange(index...); change(altered) } label: {
                            Text(actionLabel(action)).font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .foregroundStyle(HeistStyle.role(selected))
                                .background(HeistStyle.raised, in: Capsule())
                        }.accessibilityLabel("\(actionLabel(action)), tap to remove this and later actions")
                    }
                }
            }.frame(minHeight: 30)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("TIMELINE").tracking(2)
                Spacer()
                Text("SCRUB TO INSPECT")
            }.font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(HeistStyle.muted)
            Slider(value: Binding(get: { Double(tick) }, set: { tick = Int($0.rounded()); playing = false }),
                   in: 0...40, step: 1)
                .tint(HeistStyle.gold).accessibilityLabel("Heist timeline")
                .accessibilityValue(String(format: "%.2f seconds", Double(tick) / 4))
            HStack {
                ForEach(0...10, id: \.self) { number in
                    Text("\(number)")
                    if number < 10 { Spacer(minLength: 0) }
                }
            }.font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(HeistStyle.muted)
            ForEach(level.roles) { role in
                let schedule = SimulationEngine.script(plan[role], start: level.start(role)!)
                HStack(spacing: 8) {
                    Text(role.shortName).font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(HeistStyle.role(role)).frame(width: 16)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(HeistStyle.raised)
                            HStack(spacing: 0) {
                                ForEach(schedule.indices, id: \.self) { index in
                                    let action = schedule[index]
                                    Rectangle().fill(HeistStyle.role(role).opacity(action.action.kind == .wait ? 0.30 :
                                        action.action.kind == .move ? 0.67 : 1))
                                        .frame(width: geometry.size.width * CGFloat(max(0, min(40, action.end) - min(40, action.begin))) / 40)
                                }
                            }.clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }.frame(height: 10)
                }.accessibilityLabel("\(role.name) has \(plan[role].count) scheduled actions")
            }
            if let hackerStart = level.start(.hacker) {
                let hackerActions = SimulationEngine.script(plan[.hacker], start: hackerStart)
                ForEach(level.cameras) { camera in
                    if let terminal = level.terminals.first(where: { $0.disables.contains(camera.id) }) {
                        let hacks = hackerActions.filter { $0.action.kind == .hack &&
                            $0.action.target == terminal.id && $0.end < SimulationEngine.limit }
                        ForEach(hacks.indices, id: \.self) { index in
                            shutdownRow(camera: camera, from: hacks[index].end,
                                        duration: terminal.durationTicks,
                                        looped: progress.save.activeAssists[level.id] == .loop(camera: camera.id))
                        }
                    }
                }
            }
            if let simulation {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(simulation.events.indices, id: \.self) { index in
                            let event = simulation.events[index]
                            Button { playing = false; tick = event.tick } label: {
                                Text(String(format: "%.2fs  %@", Double(event.tick) / 4, event.text))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(HeistStyle.cream).padding(8)
                                    .background(HeistStyle.raised, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            if let assist = progress.save.activeAssists[level.id] {
                Text(assist == .tip ? "INSIDE TIP ACTIVE" : "CAMERA LOOP ACTIVE · +2s shutdown")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(HeistStyle.teal)
            }
        }.padding(13).background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 15))
    }

    private func actionButton(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon).font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(HeistStyle.cream)
                .background(HeistStyle.raised, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    private func actionLabel(_ action: PlannedAction) -> String {
        switch action.kind {
        case .move: "→ \(action.at?.x ?? 0),\(action.at?.y ?? 0)"
        case .wait: "WAIT \(Double(action.duration) / 4)s"
        case .take: "TAKE"
        case .hack: "HACK"
        case .distract: "SIGNAL"
        }
    }
    private func arrow(_ direction: Heading) -> String {
        switch direction { case .north: "arrow.up"; case .east: "arrow.right"; case .south: "arrow.down"; case .west: "arrow.left" }
    }
    private func route(to tile: Tile) {
        guard !playing, let origin = level.start(selected) else { return }
        let last = plan[selected].compactMap { $0.kind == .move ? $0.at : nil }.last ?? origin
        guard let path = level.path(from: last, to: tile), !path.isEmpty else { return }
        var changed = plan; changed[selected].append(contentsOf: path.map(PlannedAction.move))
        change(changed)
    }
    private func append(_ action: PlannedAction) {
        var changed = plan; changed[selected].append(action); change(changed)
    }
    private func change(_ newPlan: Plan) {
        playing = false; attempted = false; recorded = false; tick = 0
        plan = newPlan
        progress.storePlan(newPlan, for: level)
        recompute()
    }
    private func recompute() {
        simulation = SimulationEngine.run(plan, level: level, assist: progress.save.activeAssists[level.id])
    }
    private func startOrPause() {
        guard let simulation else { return }
        if case .invalid(let reason) = simulation.outcome { exportError = reason; return }
        exportError = nil
        if playing { playing = false; return }
        if !attempted || tick >= simulation.outcome.tick { tick = 0; recorded = false }
        Soundscape.shared.cue("go")
        attempted = true; playing = true
    }
    private func record(_ simulation: SimulationResult) {
        guard !recorded else { return }
        recorded = true
        switch simulation.outcome {
        case .victory:
            Soundscape.shared.cue("success")
            progress.complete(level, plan: plan, assisted: progress.save.activeAssists[level.id] != nil)
        case .spotted, .timeout:
            Soundscape.shared.cue("caught")
            progress.failed(level)
        case .invalid: break
        }
    }
    private func resultCard(_ result: SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            let won: Bool = { if case .victory = result.outcome { return true }; return false }()
            Text(won ? "THE GETAWAY" : "PLAN INTERRUPTED")
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(2)
                .foregroundStyle(won ? HeistStyle.teal : HeistStyle.warning)
            Text(result.outcome.explanation).font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(HeistStyle.cream)
            if won {
                Text(progress.save.perfect.contains(level.id) ? "✦ PERFECT HEIST" : "Operation cleared")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(HeistStyle.gold)
                if !progress.save.perfect.contains(level.id) {
                    Text("Perfect: finish unassisted with at most \(level.actionTarget) actions. This plan uses \(plan.actionCount).")
                        .font(.footnote).foregroundStyle(HeistStyle.muted)
                }
            } else {
                Button("Jump to the mistake") { tick = result.outcome.tick }
                    .font(.footnote.bold()).foregroundStyle(HeistStyle.teal)
            }
            HStack(spacing: 8) {
                HeistButton(text: "RETRY", symbol: "arrow.counterclockwise") {
                    tick = 0; attempted = false; recorded = false
                }
                if won, let nextLevel, let nextLevelIndex {
                    if CampaignAccess.canPlay(nextLevelIndex, levels: game.levels,
                                              completed: progress.save.completed,
                                              campaignUnlocked: purchases.campaignUnlocked) {
                        NavigationLink(destination: HeistScreen(level: nextLevel)) { nextButton("NEXT") }
                    } else if nextLevelIndex >= 8 && !purchases.campaignUnlocked {
                        NavigationLink(destination: StoreScreen()) { nextButton("UNLOCK NEXT") }
                    }
                }
            }
            HeistButton(text: exporting ? "RENDERING REPLAY…" : "EXPORT REPLAY", symbol: "square.and.arrow.up") {
                guard !exporting else { return }
                exporting = true
                exportError = nil
                Task {
                    do { previewURL = ReplayURL(url: try await ReplayExporter.export(level: level, plan: plan,
                         simulation: result)) }
                    catch { exportError = "Replay export failed: \(error.localizedDescription)" }
                    exporting = false
                }
            }.disabled(exporting)
            if exporting { ProgressView().tint(HeistStyle.gold).accessibilityLabel("Rendering replay video") }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 20))
    }
    private func nextButton(_ title: String) -> some View {
        Label(title, systemImage: "arrow.right")
            .font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(HeistStyle.ink)
            .background(HeistStyle.gold, in: RoundedRectangle(cornerRadius: 16))
    }
    private func objective(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .lineLimit(1).minimumScaleFactor(0.75)
            .foregroundStyle(HeistStyle.cream)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 8))
    }
    private func shutdownRow(camera: Camera, from start: Int, duration: Int, looped: Bool) -> some View {
        let baseEnd = min(40, start + duration)
        let assistedEnd = min(40, start + duration + (looped ? 8 : 0))
        return HStack(spacing: 8) {
            Text(camera.id).font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1).frame(width: 65, alignment: .leading)
                .foregroundStyle(HeistStyle.teal)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(HeistStyle.raised)
                    if start < 40 {
                        RoundedRectangle(cornerRadius: 4).fill(HeistStyle.teal)
                            .frame(width: geometry.size.width * CGFloat(max(0, baseEnd - start)) / 40)
                            .offset(x: geometry.size.width * CGFloat(start) / 40)
                        if assistedEnd > baseEnd {
                            RoundedRectangle(cornerRadius: 4).fill(HeistStyle.gold)
                                .frame(width: geometry.size.width * CGFloat(assistedEnd - baseEnd) / 40)
                                .offset(x: geometry.size.width * CGFloat(baseEnd) / 40)
                        }
                    }
                }
            }.frame(height: 9)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(camera.id) disabled from \(Double(start) / 4) to \(Double(assistedEnd) / 4) seconds\(looped ? ", including two seconds of Camera Loop" : "")")
    }
}

struct AssistanceScreen: View {
    let level: LevelDefinition
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AssistMode = .tip
    private var loopable: [Camera] { level.cameras.filter { camera in level.terminals.contains { $0.disables.contains(camera.id) } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                BrandHeading(overline: "Optional assistance", title: "Inside Help")
                Text("\(progress.save.tokenBalance) INCLUDED · \(purchases.paidBalance) PAID TOKENS")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(HeistStyle.gold)
                Text("All levels are solvable without help. Rewinds and retries are always free. Only one assistance type is active per attempt.")
                    .font(.footnote).foregroundStyle(HeistStyle.muted)
                Button {
                    selection = .tip
                } label: {
                    option("INSIDE TIP", detail: "A clue about this level's route, interaction, or timing.",
                           selected: selection == .tip)
                }
                if progress.save.hints.contains(level.id) {
                    Text(level.hint).foregroundStyle(HeistStyle.cream).padding(12)
                        .background(HeistStyle.raised, in: RoundedRectangle(cornerRadius: 10))
                }
                ForEach(loopable) { camera in
                    Button { selection = .loop(camera: camera.id) } label: {
                        option("CAMERA LOOP · \(camera.id)", detail: "Preview: +2 seconds to this camera's hacked shutdown.",
                               selected: selection == .loop(camera: camera.id))
                    }
                }
                HeistButton(text: progress.isUnlocked(selection, level: level) ? "ACTIVATE AGAIN · FREE" :
                            progress.save.tokenBalance > 0 ? "USE 1 INCLUDED TOKEN" : "USE 1 PAID TOKEN",
                            symbol: "checkmark", prominent: true) {
                    if progress.isUnlocked(selection, level: level) || progress.save.tokenBalance > 0 {
                        if progress.activate(selection, level: level) { dismiss() }
                    } else {
                        Task { if await purchases.activatePaid(selection, level: level) { dismiss() } }
                    }
                }.disabled(!progress.isUnlocked(selection, level: level) && progress.save.tokenBalance == 0 &&
                           (!purchases.walletReady || purchases.paidBalance == 0 || purchases.busy))
                if let message = purchases.message { Text(message).font(.footnote).foregroundStyle(HeistStyle.muted) }
                if progress.save.activeAssists[level.id] != nil {
                    HeistButton(text: "SWITCH OFF FOR UNASSISTED RUN", symbol: "power") {
                        progress.deactivate(level: level); dismiss()
                    }
                }
                Text("Clues and camera loops already unlocked remain available after retries and relaunch. Paid unlocks and the paid balance sync with the same iCloud account. Free retries never spend tokens.")
                    .font(.footnote).foregroundStyle(HeistStyle.muted)
            }.padding(20)
        }.background(HeistBackground())
    }
    private func option(_ title: String, detail: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .heavy, design: .monospaced))
            Text(detail).font(.footnote).multilineTextAlignment(.leading)
        }.foregroundStyle(selected ? HeistStyle.ink : HeistStyle.cream)
            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(selected ? HeistStyle.teal : HeistStyle.raised, in: RoundedRectangle(cornerRadius: 12))
    }
}
