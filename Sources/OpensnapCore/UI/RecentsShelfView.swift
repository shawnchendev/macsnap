import Foundation
import CoreGraphics
import Cocoa

public struct RecentItem: Sendable {
    public var imageURL: URL
    public var logURL: URL
    public var date: Date
    public var thumbnail: CGImage?

    public init(imageURL: URL, logURL: URL, date: Date, thumbnail: CGImage? = nil) {
        self.imageURL = imageURL
        self.logURL = logURL
        self.date = date
        self.thumbnail = thumbnail
    }
}

public final class RecentsShelfView: @unchecked Sendable {
    public private(set) var items: [RecentItem] = []
    public var fanProgress: CGFloat = 0.0 // 0 = stacked, 1 = fanned out
    public var hoveredIndex: Int? = nil

    public init() {
        reloadRecents()
    }

    public func reloadRecents() {
        let dir = AppConfig.load().resolvedRecentDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        let pngs = files.filter { $0.pathExtension.lowercased() == "png" }
            .sorted { (u1, u2) -> Bool in
                let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return d1 > d2
            }

        var loaded: [RecentItem] = []
        for png in pngs.prefix(5) {
            let log = png.appendingPathExtension("json")
            let date = (try? png.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let thumb = ScreenCaptureEngine.loadImage(from: png)
            loaded.append(RecentItem(imageURL: png, logURL: log, date: date, thumbnail: thumb))
        }
        self.items = loaded
    }

    public func saveToRecent(image: CGImage, log: OperationLog) {
        let dir = AppConfig.load().resolvedRecentDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let name = "snap-\(formatter.string(from: Date()))"

        let imgURL = dir.appendingPathComponent("\(name).png")
        let logURL = dir.appendingPathComponent("\(name).png.json")

        _ = ScreenCaptureEngine.savePNG(image: image, to: imgURL)
        try? log.save(to: logURL)

        reloadRecents()
    }

    public func hotZoneRect(screenBounds: CGRect) -> CGRect {
        // Hot zone on right edge
        let width: CGFloat = 160.0
        let height: CGFloat = min(400.0, screenBounds.height * 0.6)
        return CGRect(
            x: screenBounds.maxX - width,
            y: screenBounds.midY - height / 2.0,
            width: width,
            height: height
        )
    }

    public func cardRects(screenBounds: CGRect) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        let cardW: CGFloat = 110.0
        let cardH: CGFloat = 72.0
        let baseX = screenBounds.maxX - cardW - 20
        let baseY = screenBounds.midY - (CGFloat(items.count) * (cardH + 12)) / 2.0

        var rects: [CGRect] = []
        for (i, _) in items.enumerated() {
            if fanProgress > 0.05 {
                // Fanned out vertically
                let y = baseY + CGFloat(i) * (cardH + 12) * fanProgress
                let x = baseX - (CGFloat(i) * 6.0 * (1.0 - fanProgress))
                rects.append(CGRect(x: x, y: y, width: cardW, height: cardH))
            } else {
                // Stacked
                let offset = CGFloat(i) * 3.0
                rects.append(CGRect(x: baseX + offset, y: baseY + offset, width: cardW, height: cardH))
            }
        }
        return rects
    }

    public func draw(in context: CGContext, screenBounds: CGRect) {
        guard !items.isEmpty else { return }
        let rects = cardRects(screenBounds: screenBounds)

        for (i, item) in items.enumerated() {
            guard i < rects.count else { break }
            let rect = rects[i]
            let isHovered = (hoveredIndex == i)

            context.saveGState()

            // Drop shadow
            context.setShadow(
                offset: CGSize(width: 0, height: -4),
                blur: isHovered ? 14 : 8,
                color: NSColor(white: 0, alpha: isHovered ? 0.45 : 0.25).cgColor
            )

            // Card background
            let cardPath = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(cardPath)
            context.setFillColor(NSColor(calibratedWhite: 0.15, alpha: 0.95).cgColor)
            context.fillPath()

            // Thumbnail
            if let thumb = item.thumbnail {
                context.saveGState()
                context.addPath(cardPath)
                context.clip()
                context.draw(thumb, in: rect.insetBy(dx: 3, dy: 3))
                context.restoreGState()
            }

            // Border
            context.setStrokeColor(isHovered ? NSColor.systemBlue.cgColor : NSColor(white: 1.0, alpha: 0.2).cgColor)
            context.setLineWidth(isHovered ? 2.0 : 1.0)
            context.addPath(cardPath)
            context.strokePath()

            context.restoreGState()
        }
    }

    public func itemIndex(at point: CGPoint, screenBounds: CGRect) -> Int? {
        let rects = cardRects(screenBounds: screenBounds)
        for (i, r) in rects.enumerated().reversed() {
            if r.contains(point) {
                return i
            }
        }
        return nil
    }
}
