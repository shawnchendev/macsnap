import Foundation
import CoreGraphics

public enum CutOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

public struct CutOp: Codable, Equatable, Sendable {
    public var orientation: CutOrientation
    public var sourceStart: Int
    public var sourceEnd: Int
    public var logicalStart: Int
    public var logicalEnd: Int

    public init(
        orientation: CutOrientation = .horizontal,
        sourceStart: Int = 0,
        sourceEnd: Int = 0,
        logicalStart: Int = 0,
        logicalEnd: Int = 0
    ) {
        self.orientation = orientation
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.logicalStart = logicalStart
        self.logicalEnd = logicalEnd
    }
}

public enum CutEngine {
    /// Removes a band [start, end) along orientation from image.
    public static func removeBand(from image: CGImage, orientation: CutOrientation, start: Int, end: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let s = max(0, min(start, end))
        let e = max(0, max(start, end))

        if orientation == .horizontal {
            if s >= height || e <= 0 || s == e { return image }
            let clampedStart = min(s, height)
            let clampedEnd = min(e, height)
            let bandHeight = clampedEnd - clampedStart
            let newHeight = height - bandHeight
            if newHeight <= 0 { return image }

            guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: width,
                    height: newHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return image }

            // CGContext origin is bottom-left
            // Top portion: rows [0 ..< clampedStart]
            // Bottom portion: rows [clampedEnd ..< height]
            // In image coordinates (top-down):
            // Top part in context: height - clampedStart, at y = newHeight - clampedStart
            if clampedStart > 0 {
                let topRect = CGRect(x: 0, y: height - clampedStart, width: width, height: clampedStart)
                if let topPart = image.cropping(to: topRect) {
                    context.draw(topPart, in: CGRect(x: 0, y: newHeight - clampedStart, width: width, height: clampedStart))
                }
            }
            let bottomCount = height - clampedEnd
            if bottomCount > 0 {
                let bottomRect = CGRect(x: 0, y: 0, width: width, height: bottomCount)
                if let bottomPart = image.cropping(to: bottomRect) {
                    context.draw(bottomPart, in: CGRect(x: 0, y: 0, width: width, height: bottomCount))
                }
            }
            return context.makeImage() ?? image
        } else {
            // Vertical band
            if s >= width || e <= 0 || s == e { return image }
            let clampedStart = min(s, width)
            let clampedEnd = min(e, width)
            let bandWidth = clampedEnd - clampedStart
            let newWidth = width - bandWidth
            if newWidth <= 0 { return image }

            guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: newWidth,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: newWidth * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return image }

            if clampedStart > 0 {
                let leftRect = CGRect(x: 0, y: 0, width: clampedStart, height: height)
                if let leftPart = image.cropping(to: leftRect) {
                    context.draw(leftPart, in: CGRect(x: 0, y: 0, width: clampedStart, height: height))
                }
            }
            let rightCount = width - clampedEnd
            if rightCount > 0 {
                let rightRect = CGRect(x: clampedEnd, y: 0, width: rightCount, height: height)
                if let rightPart = image.cropping(to: rightRect) {
                    context.draw(rightPart, in: CGRect(x: clampedStart, y: 0, width: rightCount, height: height))
                }
            }
            return context.makeImage() ?? image
        }
    }

    /// Replays cuts in order over pristine image
    public static func composeCuts(pristine: CGImage, cuts: [CutOp]) -> CGImage {
        var current = pristine
        for cut in cuts {
            current = removeBand(from: current, orientation: cut.orientation, start: cut.sourceStart, end: cut.sourceEnd)
        }
        return current
    }

    /// Shifts a 1D coordinate value across a removed band [start, end)
    public static func shiftForCut(value: Double, start: Double, end: Double) -> Double {
        let s = min(start, end)
        let e = max(start, end)
        if value < s {
            return value
        } else if value < e {
            return s
        } else {
            return value - (e - s)
        }
    }

    /// Shifts an entire annotation across a cut
    public static func shiftAnnotation(_ annotation: inout Annotation, for cut: CutOp) {
        let s = Double(cut.logicalStart)
        let e = Double(cut.logicalEnd)

        if cut.orientation == .horizontal {
            annotation.start.y = shiftForCut(value: annotation.start.y, start: s, end: e)
            annotation.end.y = shiftForCut(value: annotation.end.y, start: s, end: e)
            for i in 0..<annotation.points.count {
                annotation.points[i].y = shiftForCut(value: annotation.points[i].y, start: s, end: e)
            }
        } else {
            annotation.start.x = shiftForCut(value: annotation.start.x, start: s, end: e)
            annotation.end.x = shiftForCut(value: annotation.end.x, start: s, end: e)
            for i in 0..<annotation.points.count {
                annotation.points[i].x = shiftForCut(value: annotation.points[i].x, start: s, end: e)
            }
        }
    }
}
