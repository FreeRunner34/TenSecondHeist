import AVFoundation
import AVKit
import SwiftUI
import UIKit
import VideoToolbox

struct ReplayURL: Identifiable { let url: URL; var id: URL { url } }

struct ReplayPreview: View {
    let url: URL
    var body: some View {
        VStack(spacing: 16) {
            Text("YOUR REPLAY").font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(HeistStyle.cream)
            VideoPlayer(player: AVPlayer(url: url)).aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            ShareLink(item: url, preview: SharePreview("Ten Second Heist replay")) {
                Label("SHARE VIDEO", systemImage: "square.and.arrow.up")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(HeistStyle.ink)
                    .background(HeistStyle.gold, in: RoundedRectangle(cornerRadius: 14))
            }
        }.padding(22).background(HeistBackground())
    }
}

@MainActor enum ReplayExporter {
    static func export(level: LevelDefinition, plan: Plan, simulation: SimulationResult) async throws -> URL {
        let width = 540, height = 960, fps: Int32 = 15
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("heist-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_300_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw ExportError.encoderUnavailable }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.encoderUnavailable }
        writer.startSession(atSourceTime: .zero)
        let frameCount = max(Int(fps) * 2, simulation.outcome.tick * Int(fps) / 4 + Int(fps))
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.encoderUnavailable }
            var optional: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optional) == kCVReturnSuccess,
                  let buffer = optional else { throw ExportError.encoderUnavailable }
            let tick = min(simulation.outcome.tick, index * 4 / Int(fps))
            let image = render(level: level, plan: plan, frame: simulation.frame(at: tick),
                               outcome: simulation.outcome, size: CGSize(width: width, height: height))
            CVPixelBufferLockBaseAddress(buffer, [])
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let options = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            guard let target = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                         space: colorSpace, bitmapInfo: options), let source = image.cgImage else {
                CVPixelBufferUnlockBaseAddress(buffer, []); throw ExportError.encoderUnavailable
            }
            target.translateBy(x: 0, y: CGFloat(height))
            target.scaleBy(x: 1, y: -1)
            target.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: fps)) else {
                throw writer.error ?? ExportError.encoderUnavailable
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? ExportError.encoderUnavailable }
        return url
    }

    private static func render(level: LevelDefinition, plan: Plan, frame: SimulationFrame,
                               outcome: HeistOutcome, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            UIColor(red: 0.035, green: 0.075, blue: 0.12, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawText("TEN SECOND", x: 25, y: 62, size: 39, color: .white)
            drawText("HEIST", x: 25, y: 105, size: 55, color: UIColor(red: 0.99, green: 0.76, blue: 0.38, alpha: 1))
            drawText(level.title.uppercased(), x: 26, y: 180, size: 18, color: .white)
            let tileSize: CGFloat = 54
            let ox: CGFloat = 27, oy: CGFloat = 255
            for y in 0..<level.height {
                for x in 0..<level.width {
                    let rect = CGRect(x: ox + CGFloat(x) * tileSize + 1, y: oy + CGFloat(y) * tileSize + 1,
                                      width: tileSize - 2, height: tileSize - 2)
                    (level.isWalkable(Tile(x, y)) ? UIColor(red: 0.08, green: 0.15, blue: 0.19, alpha: 1) :
                        UIColor(red: 0.14, green: 0.25, blue: 0.30, alpha: 1)).setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()
                }
            }
            func center(_ point: Point) -> CGPoint {
                CGPoint(x: ox + (point.x + 0.5) * tileSize, y: oy + (point.y + 0.5) * tileSize)
            }
            for role in level.roles {
                guard let start = level.start(role) else { continue }
                let route = UIBezierPath()
                route.move(to: center(start.point))
                for action in plan[role] where action.kind == .move {
                    if let destination = action.at { route.addLine(to: center(destination.point)) }
                }
                route.lineWidth = 3; route.lineCapStyle = .round
                let routeColor: UIColor = role == .thief ? .systemYellow : role == .hacker ? .systemMint : .systemPurple
                routeColor.withAlphaComponent(0.5).setStroke()
                route.stroke()
            }
            let escape = center(level.escape.point)
            UIColor.systemMint.setStroke()
            let exit = UIBezierPath(roundedRect: CGRect(x: escape.x - 20, y: escape.y - 20,
                                                         width: 40, height: 40), cornerRadius: 6)
            exit.lineWidth = 3; exit.stroke()
            for loot in level.loot where !frame.collected.contains(loot.id) {
                let p = center(loot.at.point)
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: p.x, y: p.y - 15))
                diamond.addLine(to: CGPoint(x: p.x + 12, y: p.y))
                diamond.addLine(to: CGPoint(x: p.x, y: p.y + 15))
                diamond.addLine(to: CGPoint(x: p.x - 12, y: p.y))
                diamond.close()
                UIColor.systemYellow.setFill(); diamond.fill()
            }
            for security in frame.guards + frame.cameras {
                let p = center(security.position)
                (security.active ? UIColor.systemRed : UIColor.systemMint).setFill()
                UIBezierPath(ovalIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)).fill()
            }
            for role in Role.allCases {
                guard let position = frame.actors[role] else { continue }
                let p = center(position)
                let color: UIColor = role == .thief ? .systemYellow : role == .hacker ? .systemMint : .systemPurple
                color.setFill()
                UIBezierPath(roundedRect: CGRect(x: p.x - 16, y: p.y - 16,
                                                width: 32, height: 32), cornerRadius: role == .hacker ? 3 : 12).fill()
                drawText(role.shortName, x: p.x - 6, y: p.y - 11, size: 21, color: .black)
            }
            drawText(String(format: "%04.2f / 10.00", frame.seconds), x: 27, y: 777, size: 27,
                     color: UIColor(red: 0.99, green: 0.76, blue: 0.38, alpha: 1))
            let summary = frame.tick >= outcome.tick ? outcome.explanation : "The plan is unfolding…"
            (summary as NSString).draw(in: CGRect(x: 27, y: 836, width: 486, height: 54), withAttributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.white
            ])
            drawText("TEN SECOND HEIST  ·  REV POINT STUDIOS", x: 27, y: 907, size: 11,
                     color: UIColor(red: 0.55, green: 0.70, blue: 0.72, alpha: 1))
        }
    }

    private static func drawText(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: UIColor) {
        (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: color
        ])
    }

    enum ExportError: LocalizedError {
        case encoderUnavailable
        var errorDescription: String? { "The device could not encode this replay." }
    }
}
