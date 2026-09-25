import Foundation

enum AssistMode: Codable, Equatable {
    case tip
    case loop(camera: String)
}

struct TimedAction {
    let action: PlannedAction
    let begin: Int
    let end: Int
    let from: Tile
    let to: Tile
}

struct SecurityState {
    let id: String
    let position: Point
    let heading: Heading
    let range: Double
    let halfAngle: Double
    let active: Bool
}

struct SimulationFrame {
    let tick: Int
    let actors: [Role: Point]
    let guards: [SecurityState]
    let cameras: [SecurityState]
    let collected: Set<String>
    let disabledCameras: Set<String>
    var seconds: Double { Double(tick) / 4.0 }
}

enum HeistOutcome: Equatable {
    case victory(tick: Int)
    case spotted(role: Role, by: String, tick: Int)
    case timeout
    case invalid(String)
    var tick: Int {
        switch self { case .victory(let t), .spotted(_, _, let t): t; case .timeout: 40; case .invalid: 0 }
    }
    var explanation: String {
        switch self {
        case .victory(let t): String(format: "Clean getaway in %.2f seconds.", Double(t) / 4)
        case .spotted(let role, let sensor, let t): "\(role.name) spotted by \(sensor) at \(String(format: "%.2f", Double(t) / 4)) seconds."
        case .timeout: "The ten seconds ran out. Collect the valuables and reach the exit sooner."
        case .invalid(let reason): reason
        }
    }
}

struct SimulationResult {
    let frames: [SimulationFrame]
    let outcome: HeistOutcome
    let events: [(tick: Int, text: String)]
    func frame(at tick: Int) -> SimulationFrame { frames[max(0, min(tick, frames.count - 1))] }
}

enum SimulationEngine {
    static let ticksPerSecond = 4
    static let limit = 40

    static func validate(_ plan: Plan, level: LevelDefinition) -> String? {
        for role in Role.allCases {
            guard let start = level.start(role) else {
                if !plan[role].isEmpty { return "\(role.name) is not available in this level." }
                continue
            }
            var location = start
            for action in plan[role] {
                switch action.kind {
                case .move:
                    guard let target = action.at, level.isWalkable(target), location.adjacent(to: target) else {
                        return "\(role.name) has a route through a wall or a missing floor tile."
                    }
                    location = target
                case .wait:
                    guard let ticks = action.ticks, ticks > 0, ticks <= 40 else { return "Wait must be between 0.25 and 10 seconds." }
                case .take:
                    guard role == .thief, let target = action.target, level.loot.contains(where: { $0.id == target && $0.at == location }) else {
                        return "Thief must stand on the named valuable to take it."
                    }
                case .hack:
                    guard role == .hacker, let target = action.target,
                          level.terminals.contains(where: { $0.id == target && ($0.at == location || $0.at.adjacent(to: location)) }) else {
                        return "Hacker must be at or next to the named terminal."
                    }
                case .distract:
                    guard role == .decoy else { return "Only Decoy can cause a distraction." }
                }
            }
        }
        return nil
    }

    static func script(_ actions: [PlannedAction], start: Tile) -> [TimedAction] {
        var tile = start, clock = 0
        return actions.map { action in
            let next = action.kind == .move ? (action.at ?? tile) : tile
            let item = TimedAction(action: action, begin: clock, end: clock + action.duration, from: tile, to: next)
            clock = item.end; tile = next
            return item
        }
    }

    static func finalTile(_ script: [TimedAction], start: Tile, tick: Int) -> Tile {
        script.last(where: { $0.end <= tick })?.to ?? start
    }

    static func position(_ script: [TimedAction], start: Tile, tick: Int) -> Point {
        guard let current = script.first(where: { $0.begin <= tick && tick < $0.end }) else {
            return finalTile(script, start: start, tick: tick).point
        }
        guard current.action.kind == .move else { return current.from.point }
        let fraction = Double(tick - current.begin) / Double(current.end - current.begin)
        return current.from.point * (1 - fraction) + current.to.point * fraction
    }

    private static func patrol(_ guardUnit: Guard, at tick: Int) -> (Point, Heading) {
        guard guardUnit.route.count > 1 else { return (guardUnit.route[0].point, guardUnit.facing) }
        let segments = 2 * (guardUnit.route.count - 1)
        let segment = (tick / 4) % segments
        let fromIndex = segment < guardUnit.route.count - 1 ? segment : segments - segment
        let toIndex = segment < guardUnit.route.count - 1 ? fromIndex + 1 : fromIndex - 1
        let from = guardUnit.route[fromIndex].point, to = guardUnit.route[toIndex].point
        let portion = Double(tick % 4) / 4
        return (from * (1 - portion) + to * portion, Heading.toward(from, to))
    }

    static func canSee(from source: Point, heading: Heading, target: Point, range: Double,
                       halfAngle: Double, level: LevelDefinition) -> Bool {
        let difference = target - source
        let length = difference.length
        guard length > 0.18, length <= range else { return false }
        let forward = heading.vector
        let dot = difference.x * forward.x + difference.y * forward.y
        guard dot / length >= cos(halfAngle * .pi / 180) else { return false }
        let samples = max(2, Int(ceil(length * 16)))
        for index in 1..<samples {
            let portion = Double(index) / Double(samples)
            if !level.isWalkable((source + difference * portion).tile) { return false }
        }
        return true
    }

    static func run(_ plan: Plan, level: LevelDefinition, assist: AssistMode? = nil) -> SimulationResult {
        if let problem = validate(plan, level: level) {
            return SimulationResult(frames: [initialFrame(level)], outcome: .invalid(problem), events: [])
        }
        let scripts = Dictionary(uniqueKeysWithValues: level.roles.map { ($0, script(plan[$0], start: level.start($0)!)) })
        let allActions = scripts.flatMap { role, actions in actions.map { (role, $0) } }
        var frames: [SimulationFrame] = []
        var events: [(tick: Int, text: String)] = []
        var finished: HeistOutcome?

        for tick in 0...limit {
            if let finished, tick > finished.tick {
                frames.append(frames[finished.tick]); continue
            }
            let actors = Dictionary(uniqueKeysWithValues: level.roles.map { role in
                (role, position(scripts[role]!, start: level.start(role)!, tick: tick))
            })
            let completed = allActions.filter { $0.1.end == tick && $0.1.end <= limit }
            for (role, action) in completed {
                switch action.action.kind {
                case .take: events.append((tick, "\(role.name) secured \(action.action.target ?? "valuables")"))
                case .hack: events.append((tick, "Security disabled by Hacker"))
                case .distract: events.append((tick, "Decoy drew the guards' attention"))
                default: break
                }
            }
            let collected = Set(allActions.compactMap { role, action -> String? in
                role == .thief && action.action.kind == .take && action.end <= tick ? action.action.target : nil
            })
            let hacks = allActions.filter { $0.0 == .hacker && $0.1.action.kind == .hack && $0.1.end <= tick }
            let signals = allActions.filter { $0.0 == .decoy && $0.1.action.kind == .distract && $0.1.end <= tick && tick < $0.1.end + 12 }
            let disabled = Set(level.cameras.filter { camera in
                hacks.contains { _, hack in
                    guard let terminal = level.terminals.first(where: { $0.id == hack.action.target }), terminal.disables.contains(camera.id) else { return false }
                    let bonus = assist == .loop(camera: camera.id) ? 8 : 0
                    return tick < hack.end + terminal.durationTicks + bonus
                }
            }.map(\.id))
            let guards = level.guards.map { unit -> SecurityState in
                if let signal = signals.last(where: { _, action in
                    let origin = patrol(unit, at: action.end).0
                    return origin.distance(to: action.to.point) <= 6
                }) {
                    let stopped = patrol(unit, at: signal.1.end).0
                    return SecurityState(id: unit.id, position: stopped,
                                         heading: Heading.toward(stopped, signal.1.to.point),
                                         range: unit.range, halfAngle: 32, active: true)
                }
                let (pos, facing) = patrol(unit, at: tick)
                return SecurityState(id: unit.id, position: pos, heading: facing,
                                     range: unit.range, halfAngle: 32, active: true)
            }
            let cameras = level.cameras.map { camera in
                SecurityState(id: camera.id, position: camera.at.point,
                              heading: camera.sweep[(tick / 8) % camera.sweep.count],
                              range: camera.range, halfAngle: 24, active: !disabled.contains(camera.id))
            }
            let frame = SimulationFrame(tick: tick, actors: actors, guards: guards, cameras: cameras,
                                        collected: collected, disabledCameras: disabled)
            frames.append(frame)
            for role in [Role.thief, .hacker] where level.start(role) != nil {
                guard let actor = actors[role] else { continue }
                if let sensor = (guards + cameras).first(where: { $0.active && canSee(from: $0.position,
                    heading: $0.heading, target: actor, range: $0.range,
                    halfAngle: $0.halfAngle, level: level) }) {
                    finished = .spotted(role: role, by: sensor.id, tick: tick)
                    events.append((tick, finished!.explanation)); break
                }
            }
            if finished == nil, collected.count == level.loot.count,
               let thiefStart = level.start(.thief),
               finalTile(scripts[.thief] ?? [], start: thiefStart, tick: tick) == level.escape {
                finished = .victory(tick: tick)
                events.append((tick, finished!.explanation))
            }
        }
        return SimulationResult(frames: frames, outcome: finished ?? .timeout, events: events)
    }

    private static func initialFrame(_ level: LevelDefinition) -> SimulationFrame {
        SimulationFrame(tick: 0, actors: Dictionary(uniqueKeysWithValues: level.roles.compactMap {
            role in level.start(role).map { (role, $0.point) }
        }), guards: [], cameras: [],
                        collected: [], disabledCameras: [])
    }
}
