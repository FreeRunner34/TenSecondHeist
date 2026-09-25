import Foundation

struct Tile: Codable, Hashable, Equatable {
    var x: Int
    var y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    var point: Point { Point(x: Double(x), y: Double(y)) }
    func adjacent(to other: Tile) -> Bool { abs(x - other.x) + abs(y - other.y) == 1 }
}

struct Point: Equatable {
    var x: Double
    var y: Double
    static func +(lhs: Point, rhs: Point) -> Point { Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func -(lhs: Point, rhs: Point) -> Point { Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func *(lhs: Point, rhs: Double) -> Point { Point(x: lhs.x * rhs, y: lhs.y * rhs) }
    var length: Double { (x * x + y * y).squareRoot() }
    func distance(to other: Point) -> Double { (self - other).length }
    var tile: Tile { Tile(Int(x.rounded()), Int(y.rounded())) }
}

enum Role: String, Codable, CaseIterable, Identifiable {
    case thief, hacker, decoy
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .thief: "figure.run"; case .hacker: "laptopcomputer"; case .decoy: "theatermasks.fill" }
    }
    var shortName: String {
        switch self { case .thief: "T"; case .hacker: "H"; case .decoy: "D" }
    }
}

enum Heading: String, Codable {
    case north, east, south, west
    var vector: Point {
        switch self {
        case .north: Point(x: 0, y: -1)
        case .east: Point(x: 1, y: 0)
        case .south: Point(x: 0, y: 1)
        case .west: Point(x: -1, y: 0)
        }
    }
    static func toward(_ from: Point, _ to: Point) -> Heading {
        let delta = to - from
        return abs(delta.x) > abs(delta.y) ? (delta.x >= 0 ? .east : .west) : (delta.y >= 0 ? .south : .north)
    }
}

struct Fixture: Codable, Identifiable {
    var id: String
    var at: Tile
}

struct Guard: Codable, Identifiable {
    var id: String
    var route: [Tile]
    var facing: Heading
    var range: Double
}

struct Camera: Codable, Identifiable {
    var id: String
    var at: Tile
    var sweep: [Heading]
    var range: Double
    var terminal: String?
}

struct Terminal: Codable, Identifiable {
    var id: String
    var at: Tile
    var disables: [String]
    var durationTicks: Int
}

enum ActionKind: String, Codable { case move, wait, take, hack, distract }

struct PlannedAction: Codable, Equatable {
    var kind: ActionKind
    var at: Tile?
    var target: String?
    var ticks: Int?
    static func move(_ tile: Tile) -> PlannedAction { .init(kind: .move, at: tile) }
    static func wait(_ ticks: Int = 4) -> PlannedAction { .init(kind: .wait, ticks: ticks) }
    static func take(_ id: String) -> PlannedAction { .init(kind: .take, target: id) }
    static func hack(_ id: String) -> PlannedAction { .init(kind: .hack, target: id) }
    static let distract = PlannedAction(kind: .distract)
    init(kind: ActionKind, at: Tile? = nil, target: String? = nil, ticks: Int? = nil) {
        self.kind = kind; self.at = at; self.target = target; self.ticks = ticks
    }
    var duration: Int {
        switch kind { case .move, .take, .distract: 2; case .hack: 4; case .wait: max(1, min(40, ticks ?? 4)) }
    }
}

struct Plan: Codable, Equatable {
    var actions: [String: [PlannedAction]] = [:]
    subscript(_ role: Role) -> [PlannedAction] {
        get { actions[role.rawValue] ?? [] }
        set { actions[role.rawValue] = newValue }
    }
    var actionCount: Int { actions.values.reduce(0) { $0 + $1.count } }
}

struct LevelDefinition: Codable, Identifiable {
    var id: String
    var title: String
    var site: String
    var difficulty: Int
    var briefing: String
    var map: [String]
    var starts: [String: Tile]
    var escape: Tile
    var loot: [Fixture]
    var guards: [Guard]
    var cameras: [Camera]
    var terminals: [Terminal]
    var hint: String
    var actionTarget: Int
    var reference: Plan
    var width: Int { map.first?.count ?? 0 }
    var height: Int { map.count }
    var roles: [Role] { Role.allCases.filter { starts[$0.rawValue] != nil } }
    func start(_ role: Role) -> Tile? { starts[role.rawValue] }
    func isWalkable(_ tile: Tile) -> Bool {
        guard tile.y >= 0, tile.y < height, tile.x >= 0, tile.x < width else { return false }
        let row = Array(map[tile.y]); return row[tile.x] != "#"
    }
    func isDoor(_ tile: Tile) -> Bool {
        guard isWalkable(tile) else { return false }
        return Array(map[tile.y])[tile.x] == "+"
    }
    func path(from start: Tile, to goal: Tile) -> [Tile]? {
        guard isWalkable(start), isWalkable(goal) else { return nil }
        if start == goal { return [] }
        var queue = [start], head = 0, previous: [Tile: Tile] = [:], seen: Set<Tile> = [start]
        while head < queue.count {
            let current = queue[head]; head += 1
            for next in [Tile(current.x + 1, current.y), Tile(current.x, current.y + 1), Tile(current.x - 1, current.y), Tile(current.x, current.y - 1)] {
                guard isWalkable(next), seen.insert(next).inserted else { continue }
                previous[next] = current
                if next == goal {
                    var result = [goal], cursor = goal
                    while let prior = previous[cursor], prior != start { result.append(prior); cursor = prior }
                    return result.reversed()
                }
                queue.append(next)
            }
        }
        return nil
    }
}

enum LevelCatalog {
    static func load(from bundle: Bundle = .main) throws -> [LevelDefinition] {
        guard let url = bundle.url(forResource: "levels", withExtension: "json") else {
            throw NSError(domain: "TenSecondHeist", code: 1, userInfo: [NSLocalizedDescriptionKey: "Campaign data is missing."])
        }
        let levels = try JSONDecoder().decode([LevelDefinition].self, from: Data(contentsOf: url))
        guard Set(levels.map(\.id)).count == levels.count else {
            throw NSError(domain: "TenSecondHeist", code: 2, userInfo: [NSLocalizedDescriptionKey: "Duplicate level identifiers."])
        }
        return levels
    }
}
