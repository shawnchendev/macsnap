import Foundation
import CoreGraphics
import Cocoa

public enum MotionKind: Sendable {
    case stationary
    case forward
    case reverse
    case ambiguous
    case unmatchable
}

public struct Motion: Sendable {
    public var kind: MotionKind
    public var delta: Int

    public init(kind: MotionKind = .unmatchable, delta: Int = 0) {
        self.kind = kind
        self.delta = delta
    }
}

public final class Stitcher: @unchecked Sendable {
    public let axis: StitchAxis
    private var baseImage: CGImage?
    private var lastGray: GrayView?
    private var slices: [(image: CGImage, delta: Int)] = []
    public private(set) var totalDelta: Int = 0

    public init(axis: StitchAxis = .vertical) {
        self.axis = axis
    }

    /// Adds first frame as base
    public func start(initialFrame: CGImage) {
        self.baseImage = initialFrame
        self.lastGray = GrayView(image: initialFrame, axis: axis)
        self.slices = [(initialFrame, 0)]
        self.totalDelta = 0
    }

    /// Classifies motion and adds frame if forward motion is detected
    public func addFrame(_ frame: CGImage) -> Motion {
        guard let prev = lastGray else {
            start(initialFrame: frame)
            return Motion(kind: .forward, delta: 0)
        }

        let curr = GrayView(image: frame, axis: axis)
        let motion = estimateMotion(prev: prev, curr: curr)

        if motion.kind == .forward && motion.delta > 2 {
            slices.append((frame, motion.delta))
            totalDelta += motion.delta
            self.lastGray = curr
        }

        return motion
    }

    private func estimateMotion(prev: GrayView, curr: GrayView) -> Motion {
        let axisLen = prev.axisLen(axis: axis)
        let crossLen = prev.crossLen(axis: axis)

        // 1. Check if stationary (delta == 0)
        var statDiff: Double = 0
        let sampleStep = max(1, axisLen / 64)
        var sampleCount = 0

        for a in stride(from: 0, to: axisLen, by: sampleStep) {
            for c in stride(from: 0, to: crossLen, by: 4) {
                let p = (axis == .vertical) ? prev.pixel(x: c, y: a) : prev.pixel(x: a, y: c)
                let q = (axis == .vertical) ? curr.pixel(x: c, y: a) : curr.pixel(x: a, y: c)
                statDiff += abs(Double(p) - Double(q))
                sampleCount += 1
            }
        }
        let avgStatError = sampleCount > 0 ? (statDiff / Double(sampleCount)) : 0.0
        if avgStatError < 2.0 {
            return Motion(kind: .stationary, delta: 0)
        }

        // 2. Search for best forward shift (delta in 3 ..< axisLen * 0.75)
        let maxDelta = min(axisLen - 32, Int(Double(axisLen) * 0.85))
        var bestDelta = 0
        var bestError = Double.greatestFiniteMagnitude

        for d in stride(from: 3, through: maxDelta, by: 1) {
            let overlap = axisLen - d
            if overlap < 32 { break }

            var diff: Double = 0
            var count = 0
            let testStep = max(1, overlap / 32)

            for a in stride(from: 0, to: overlap, by: testStep) {
                // In curr, row is a; in prev, row is a + d
                for c in stride(from: 0, to: crossLen, by: 4) {
                    let p = (axis == .vertical) ? prev.pixel(x: c, y: a + d) : prev.pixel(x: a + d, y: c)
                    let q = (axis == .vertical) ? curr.pixel(x: c, y: a) : curr.pixel(x: a, y: c)
                    diff += abs(Double(p) - Double(q))
                    count += 1
                }
            }
            let err = count > 0 ? (diff / Double(count)) : Double.greatestFiniteMagnitude
            if err < bestError {
                bestError = err
                bestDelta = d
            }
        }

        if bestError < 16.0 && bestDelta > 2 {
            return Motion(kind: .forward, delta: bestDelta)
        }

        return Motion(kind: .unmatchable, delta: 0)
    }

    /// Assembles all slices into a single tall or wide CGImage
    public func finish() -> CGImage? {
        guard let base = baseImage, !slices.isEmpty else { return baseImage }
        if slices.count == 1 { return base }

        let width = base.width
        let height = base.height

        if axis == .vertical {
            let totalHeight = height + totalDelta
            guard let colorSpace = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: width,
                    height: totalHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return base }

            // Draw base frame at top
            // In CGContext, origin is bottom-left
            // Base frame is drawn at y = totalHeight - height
            context.draw(base, in: CGRect(x: 0, y: totalHeight - height, width: width, height: height))

            var currentY = totalHeight - height
            for i in 1..<slices.count {
                let slice = slices[i]
                currentY -= slice.delta

                // Draw new slice of height slice.delta from bottom of slice.image
                let sliceRect = CGRect(x: 0, y: 0, width: width, height: slice.delta)
                if let croppedSlice = slice.image.cropping(to: sliceRect) {
                    context.draw(croppedSlice, in: CGRect(x: 0, y: currentY, width: width, height: slice.delta))
                }
            }

            return context.makeImage()
        } else {
            let totalWidth = width + totalDelta
            guard let colorSpace = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: totalWidth,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: totalWidth * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return base }

            context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
            var currentX = width
            for i in 1..<slices.count {
                let slice = slices[i]
                let sliceRect = CGRect(x: slice.image.width - slice.delta, y: 0, width: slice.delta, height: height)
                if let cropped = slice.image.cropping(to: sliceRect) {
                    context.draw(cropped, in: CGRect(x: currentX, y: 0, width: slice.delta, height: height))
                }
                currentX += slice.delta
            }

            return context.makeImage()
        }
    }
}
