import SwiftUI

enum HeistStyle {
    static let ink = Color(red: 0.035, green: 0.075, blue: 0.12)
    static let panel = Color(red: 0.075, green: 0.13, blue: 0.18)
    static let raised = Color(red: 0.105, green: 0.18, blue: 0.23)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.85)
    static let muted = Color(red: 0.59, green: 0.70, blue: 0.72)
    static let gold = Color(red: 0.99, green: 0.76, blue: 0.38)
    static let teal = Color(red: 0.29, green: 0.89, blue: 0.76)
    static let warning = Color(red: 1, green: 0.40, blue: 0.40)
    static func role(_ role: Role) -> Color {
        switch role { case .thief: gold; case .hacker: teal; case .decoy: Color(red: 0.76, green: 0.60, blue: 1) }
    }
    static func site(_ name: String) -> Color {
        if name.contains("Archive") { return Color(red: 0.34, green: 0.73, blue: 0.84) }
        if name.contains("Penthouse") { return Color(red: 0.85, green: 0.57, blue: 0.78) }
        if name.contains("Vault") { return Color(red: 0.73, green: 0.85, blue: 0.52) }
        return gold
    }
}

struct HeistBackground: View {
    var body: some View {
        ZStack {
            HeistStyle.ink
            RadialGradient(colors: [HeistStyle.raised.opacity(0.7), .clear], center: .topLeading,
                           startRadius: 40, endRadius: 600)
            GeometryReader { geometry in
                Path { path in
                    stride(from: 0.0, through: geometry.size.width + geometry.size.height, by: 34).forEach { n in
                        path.move(to: CGPoint(x: n, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: n))
                    }
                }.stroke(.white.opacity(0.025), lineWidth: 1)
            }
        }.ignoresSafeArea()
    }
}

struct BrandHeading: View {
    let overline: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(overline.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(3).foregroundStyle(HeistStyle.teal)
            Text(title).font(.system(size: 35, weight: .black, design: .rounded))
                .tracking(-1.2).foregroundStyle(HeistStyle.cream)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HeistButton: View {
    let text: String
    let symbol: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(text, systemImage: symbol)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(prominent ? HeistStyle.ink : HeistStyle.cream)
                .background(prominent ? HeistStyle.gold : HeistStyle.raised,
                            in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

struct BoardCanvas: View {
    let level: LevelDefinition
    let plan: Plan
    let frame: SimulationFrame
    let selectedRole: Role
    let editing: Bool
    let onTile: (Tile) -> Void
    @State private var lastDrag: Tile?

    var body: some View {
        Canvas { context, size in
            let step = min(size.width / CGFloat(level.width), size.height / CGFloat(level.height))
            let origin = CGPoint(x: (size.width - step * CGFloat(level.width)) / 2,
                                 y: (size.height - step * CGFloat(level.height)) / 2)
            func center(_ p: Point) -> CGPoint {
                CGPoint(x: origin.x + (CGFloat(p.x) + 0.5) * step,
                        y: origin.y + (CGFloat(p.y) + 0.5) * step)
            }
            let accent = HeistStyle.site(level.site)
            context.fill(Path(CGRect(origin: origin, size: CGSize(width: step * CGFloat(level.width),
                                                                  height: step * CGFloat(level.height)))),
                         with: .color(HeistStyle.ink))
            for y in 0..<level.height {
                for x in 0..<level.width {
                    let tile = Tile(x, y)
                    let rect = CGRect(x: origin.x + CGFloat(x) * step, y: origin.y + CGFloat(y) * step,
                                      width: step, height: step).insetBy(dx: 1, dy: 1)
                    if !level.isWalkable(tile) {
                        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(HeistStyle.raised))
                        let bevel = CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width - 4, height: 2)
                        context.fill(Path(bevel), with: .color(accent.opacity(0.22)))
                    } else {
                        context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                     with: .color((x + y).isMultiple(of: 2) ? HeistStyle.panel : HeistStyle.panel.opacity(0.77)))
                        if level.isDoor(tile) {
                            context.fill(Path(CGRect(x: rect.minX + 2, y: rect.midY - 2,
                                                     width: rect.width - 4, height: 4)), with: .color(accent))
                        }
                        if (x + y * 3).isMultiple(of: 7) {
                            let dot = CGRect(x: rect.midX - 1, y: rect.midY - 1, width: 2, height: 2)
                            context.fill(Path(ellipseIn: dot), with: .color(accent.opacity(0.16)))
                        }
                    }
                }
            }
            let exit = center(level.escape.point)
            let exitRect = CGRect(x: exit.x - step * 0.40, y: exit.y - step * 0.40,
                                  width: step * 0.8, height: step * 0.8)
            context.fill(Path(roundedRect: exitRect, cornerRadius: 7), with: .color(HeistStyle.teal.opacity(0.22)))
            context.stroke(Path(roundedRect: exitRect, cornerRadius: 7), with: .color(HeistStyle.teal), lineWidth: 2)
            label("EXIT", at: exit, size: max(9, step * 0.19), color: HeistStyle.teal, in: &context)

            for security in frame.guards + frame.cameras where security.active {
                var cone = Path(); cone.move(to: center(security.position))
                let base = atan2(security.heading.vector.y, security.heading.vector.x)
                for index in 0...12 {
                    let angle = base + (Double(index) / 12 * 2 - 1) * security.halfAngle * .pi / 180
                    let end = Point(x: security.position.x + cos(angle) * security.range,
                                    y: security.position.y + sin(angle) * security.range)
                    cone.addLine(to: center(end))
                }
                cone.closeSubpath()
                for y in 0..<level.height {
                    for x in 0..<level.width {
                        let tile = Tile(x, y)
                        guard level.isWalkable(tile), SimulationEngine.canSee(from: security.position,
                            heading: security.heading, target: tile.point, range: security.range,
                            halfAngle: security.halfAngle, level: level) else { continue }
                        var clipped = context
                        clipped.clip(to: Path(CGRect(x: origin.x + CGFloat(x) * step,
                                                     y: origin.y + CGFloat(y) * step, width: step, height: step)))
                        clipped.fill(cone, with: .color(HeistStyle.warning.opacity(0.24)))
                    }
                }
            }
            for role in level.roles {
                var path = Path()
                var position = level.start(role)!
                path.move(to: center(position.point))
                for action in plan[role] where action.kind == .move {
                    if let tile = action.at { position = tile; path.addLine(to: center(tile.point)) }
                }
                context.stroke(path, with: .color(HeistStyle.role(role).opacity(role == selectedRole ? 0.92 : 0.38)),
                               style: StrokeStyle(lineWidth: role == selectedRole ? 3 : 2,
                                                  lineCap: .round, dash: role == selectedRole ? [] : [4, 4]))
                var actionTile = level.start(role)!
                for action in plan[role] {
                    if action.kind == .move { actionTile = action.at ?? actionTile }
                    if action.kind == .wait || action.kind == .hack || action.kind == .distract {
                        let p = center(actionTile.point)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                                     with: .color(HeistStyle.role(role)))
                    }
                }
            }
            for loot in level.loot where !frame.collected.contains(loot.id) {
                let p = center(loot.at.point)
                var diamond = Path()
                diamond.move(to: CGPoint(x: p.x, y: p.y - step * 0.27))
                diamond.addLine(to: CGPoint(x: p.x + step * 0.20, y: p.y))
                diamond.addLine(to: CGPoint(x: p.x, y: p.y + step * 0.27))
                diamond.addLine(to: CGPoint(x: p.x - step * 0.20, y: p.y))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(HeistStyle.gold))
                context.stroke(diamond, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            }
            for terminal in level.terminals {
                let p = center(terminal.at.point)
                let rect = CGRect(x: p.x - step * 0.25, y: p.y - step * 0.20,
                                  width: step * 0.50, height: step * 0.4)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(HeistStyle.teal))
                label("⌘", at: p, size: max(13, step * 0.27), color: HeistStyle.ink, in: &context)
            }
            for guardUnit in frame.guards {
                let p = center(guardUnit.position)
                context.fill(Path(ellipseIn: CGRect(x: p.x - step * 0.18, y: p.y - step * 0.18,
                                                    width: step * 0.36, height: step * 0.36)),
                             with: .color(HeistStyle.warning))
                label("!", at: p, size: max(11, step * 0.22), color: .white, in: &context)
            }
            for camera in frame.cameras {
                let p = center(camera.position)
                let color = camera.active ? HeistStyle.warning : HeistStyle.teal
                context.fill(Path(roundedRect: CGRect(x: p.x - step * 0.17, y: p.y - step * 0.17,
                                                      width: step * 0.34, height: step * 0.34), cornerRadius: 3),
                             with: .color(color))
                label(camera.active ? "◉" : "×", at: p, size: max(11, step * 0.20), color: .white, in: &context)
            }
            for role in level.roles {
                guard let point = frame.actors[role] else { continue }
                let p = center(point), color = HeistStyle.role(role)
                let isSelected = role == selectedRole
                context.fill(Path(ellipseIn: CGRect(x: p.x - step * 0.31, y: p.y - step * 0.31,
                                                    width: step * 0.62, height: step * 0.62)),
                             with: .color(HeistStyle.ink))
                if isSelected {
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - step * 0.33, y: p.y - step * 0.33,
                                                          width: step * 0.66, height: step * 0.66)),
                                   with: .color(.white), lineWidth: 2)
                }
                var shape = Path()
                if role == .thief {
                    shape.addRoundedRect(in: CGRect(x: p.x - step * 0.18, y: p.y - step * 0.22,
                                                    width: step * 0.36, height: step * 0.44), cornerSize: CGSize(width: 7, height: 7))
                } else if role == .hacker {
                    shape.addRect(CGRect(x: p.x - step * 0.19, y: p.y - step * 0.19,
                                        width: step * 0.38, height: step * 0.38))
                } else {
                    shape.move(to: CGPoint(x: p.x, y: p.y - step * 0.23))
                    shape.addLine(to: CGPoint(x: p.x + step * 0.23, y: p.y))
                    shape.addLine(to: CGPoint(x: p.x, y: p.y + step * 0.23))
                    shape.addLine(to: CGPoint(x: p.x - step * 0.23, y: p.y))
                    shape.closeSubpath()
                }
                context.fill(shape, with: .color(color))
                label(role.shortName, at: p, size: max(10, step * 0.21), color: HeistStyle.ink, in: &context)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(HeistStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(HeistStyle.site(level.site).opacity(0.35), lineWidth: 1))
        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
            guard editing else { return }
            // The board occupies a square frame; the renderer uses the same nine-cell coordinate system.
            let available = gesture.location
            let viewSide = boardSide
            guard viewSide > 0 else { return }
            let x = Int(available.x / viewSide * CGFloat(level.width))
            let y = Int(available.y / viewSide * CGFloat(level.height))
            let tile = Tile(x, y)
            if tile != lastDrag, level.isWalkable(tile) { lastDrag = tile; onTile(tile) }
        }.onEnded { _ in lastDrag = nil })
        .background(GeometryReader { proxy in
            Color.clear.onAppear { boardSide = min(proxy.size.width, proxy.size.height) }
                .onChange(of: proxy.size) { _, size in boardSide = min(size.width, size.height) }
        })
        .accessibilityLabel("Floor plan. Drag to draw the selected crew member's route.")
    }

    @State private var boardSide: CGFloat = 0

    private func label(_ text: String, at point: CGPoint, size: CGFloat, color: Color,
                       in context: inout GraphicsContext) {
        context.draw(Text(text).font(.system(size: size, weight: .black, design: .rounded))
            .foregroundColor(color), at: point)
    }
}
