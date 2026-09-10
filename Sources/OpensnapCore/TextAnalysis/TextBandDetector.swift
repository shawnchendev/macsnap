import Foundation
import CoreGraphics

public struct TextBand: Equatable, Sendable {
    public var top: Double
    public var bottom: Double

    public var height: Double {
        bottom - top
    }

    public var centerY: Double {
        (top + bottom) / 2.0
    }

    public init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }
}

public enum TextBandDetector {
    private static let kHorizontalRadius: Double = 96.0
    private static let kSnapDistance: Double = 20.0
    private static let kMaximumTextHeight: Double = 64.0
    private static let kMinimumTextHeight: Double = 5.0
    private static let kVerticalMergeGap: Double = 6.0
    private static let kEdgeDensity: Double = 0.035

    private static func colorDistance(_ c1: UInt32, _ c2: UInt32) -> Int {
        // RGBA components
        let r1 = Int((c1 >> 24) & 0xff)
        let g1 = Int((c1 >> 16) & 0xff)
        let b1 = Int((c1 >> 8) & 0xff)

        let r2 = Int((c2 >> 24) & 0xff)
        let g2 = Int((c2 >> 16) & 0xff)
        let b2 = Int((c2 >> 8) & 0xff)

        return max(abs(r1 - r2), max(abs(g1 - g2), abs(b1 - b2)))
    }

    /// Detects text band around sourcePoint in source image pixels
    public static func detectTextBand(
        source: CGImage,
        sourcePoint: CGPoint,
        scale: Double = 1.0
    ) -> TextBand? {
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }
        guard CGRect(x: 0, y: 0, width: width, height: height).contains(sourcePoint) else { return nil }

        let s = max(scale, 0.01)
        let edgeReach = max(1, Int(round(2.0 * s)))
        let columnStep = max(1, Int(round(2.0 * s)))
        let halfWidth = max(1, Int(round(kHorizontalRadius * s)))
        let snapRows = max(1, Int(round(kSnapDistance * s)))
        let minBandHeight = max(1, Int(round(kMinimumTextHeight * s)))
        let maxBandHeight = max(1, Int(round(kMaximumTextHeight * s)))
        let mergeGap = max(1, Int(round(kVerticalMergeGap * s)))
        let halfHeight = snapRows + maxBandHeight

        let centerX = min(max(0, Int(round(sourcePoint.x))), width - 1)
        let centerY = min(max(0, Int(round(sourcePoint.y))), height - 1)

        let x0 = max(0, centerX - halfWidth)
        let x1 = min(width - 1 - edgeReach, centerX + halfWidth)
        let y0 = max(0, centerY - halfHeight)
        let y1 = min(height - 1, centerY + halfHeight)
        if x1 < x0 || y1 < y0 { return nil }

        var columns: [Int] = []
        for x in stride(from: x0, through: x1, by: columnStep) {
            columns.append(x)
        }
        if columns.count < 8 { return nil }

        // Render region into pixel buffer
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let pixelData = context.data else { return nil }

        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = pixelData.bindMemory(to: UInt32.self, capacity: width * height)

        let rowCount = y1 - y0 + 1
        var textRows = [Bool](repeating: false, count: rowCount)
        var deltas = [Int](repeating: 0, count: columns.count)
        let minEdges = max(3, Int(ceil(Double(columns.count) * kEdgeDensity)))

        for y in y0...y1 {
            // Note: CGContext origin is bottom-left, so row in memory is (height - 1 - y)
            let memY = height - 1 - y
            let rowOffset = memY * width

            for (idx, x) in columns.enumerated() {
                let p1 = pixels[rowOffset + x]
                let p2 = pixels[rowOffset + x + edgeReach]
                deltas[idx] = colorDistance(p1, p2)
            }

            // Estimate noise floor from median edge
            let sortedDeltas = deltas.sorted()
            let median = sortedDeltas[sortedDeltas.count / 2]
            let threshold = min(max(median + 10, 12), 24)
            let edgeCount = deltas.filter { $0 >= threshold }.count
            textRows[y - y0] = edgeCount >= minEdges
        }

        let centerIdx = centerY - y0
        var anchor: Int?
        if textRows[centerIdx] {
            anchor = centerIdx
        } else {
            for dist in 1...snapRows {
                let above = centerIdx - dist
                let below = centerIdx + dist
                if above >= 0 && textRows[above] {
                    anchor = above
                    break
                }
                if below < textRows.count && textRows[below] {
                    anchor = below
                    break
                }
            }
        }
        guard let anchorRow = anchor else { return nil }

        var top = anchorRow
        var gap = 0
        while top > 0 {
            let next = top - 1
            if textRows[next] {
                top = next
                gap = 0
            } else if gap < mergeGap {
                top = next
                gap += 1
            } else {
                break
            }
        }
        while top < textRows.count && !textRows[top] {
            top += 1
        }

        var bottom = anchorRow
        gap = 0
        while bottom + 1 < textRows.count {
            let next = bottom + 1
            if textRows[next] {
                bottom = next
                gap = 0
            } else if gap < mergeGap {
                bottom = next
                gap += 1
            } else {
                break
            }
        }
        while bottom >= 0 && !textRows[bottom] {
            bottom -= 1
        }

        let bandH = bottom - top + 1
        if bandH < minBandHeight || bandH > maxBandHeight {
            return nil
        }

        return TextBand(top: Double(y0 + top), bottom: Double(y0 + bottom + 1))
    }
}
