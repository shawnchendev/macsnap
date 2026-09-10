import Foundation
import CoreGraphics
import Cocoa

/// Background capture loop for scrolling-region capture.
///
/// The main overlay is hidden while this runs, so the page underneath stays
/// scrollable and the overlay never appears in its own screenshots. Frames of
/// the fixed region are grabbed with `CGWindowListCreateImage` and fed to the
/// pure `Stitcher`. All shared state is lock-guarded; the UI polls
/// `snapshot()` from a main-thread timer — no cross-thread UI callbacks.
public final class ScrollCaptureWorker: @unchecked Sendable {

    public enum Mode: Sendable {
        case manual
        case auto
    }

    /// Thread-safe UI snapshot polled from the main thread.
    public struct Snapshot: Sendable {
        public var keptFrames: Int = 0
        public var totalDelta: Int = 0
        public var statusText: String = ""
        public var statusWarning: Bool = false
        public var stalled: Bool = false
        public var ended: Bool = false
        public var full: Bool = false
        public var fellBackToManual: Bool = false
        public var failed: Bool = false
    }

    private enum LoopExit {
        case stopped
        case stalledEnd
        case stalledAlignment
        case stalledUnavailable
        case full
    }

    private let regionQuartz: CGRect
    private let axis: StitchAxis
    private let mode: Mode
    private let stitcher: Stitcher
    private let lock = NSLock()

    private var stopRequested = false
    private var exited = false

    private var keptFrames = 0
    private var cachedDelta = 0
    private var statusText = ""
    private var statusWarning = false
    private var stalled = false
    private var ended = false
    private var full = false
    private var fellBackToManual = false
    private var failed = false
    private var lastWarnAt: Date = .distantPast

    private var queue: DispatchQueue?
    private let done = DispatchGroup()

    // Longest edge most image software reliably opens.
    private static let kWidelyOpenableEdge = 32767
    // Hard memory budget for the finished stitch (RGBA bytes).
    private static let kMaxStitchedBytes: Int = 512 * 1024 * 1024

    public init(regionQuartz: CGRect, axis: StitchAxis, mode: Mode) {
        self.regionQuartz = regionQuartz.standardized
        self.axis = axis
        self.mode = mode
        self.stitcher = Stitcher(axis: axis)
    }

    // MARK: - Main-thread control

    public func start() {
        done.enter()
        let q = DispatchQueue(label: "com.opensnap.scrollcapture", qos: .userInitiated)
        self.queue = q
        q.async { [weak self] in
            self?.run()
        }
    }

    public func requestStop() {
        lock.lock(); stopRequested = true; lock.unlock()
    }

    /// Blocks the caller until the loop exits. Never call from the loop itself.
    public func waitForExit() {
        done.wait()
    }

    public var didExit: Bool {
        lock.lock(); defer { lock.unlock() }; return exited
    }

    /// Resume an auto capture that stalled (Continue button). Restarts the loop
    /// keeping every verified band.
    public func resume() {
        lock.lock()
        stalled = false
        ended = false
        stopRequested = false
        lock.unlock()
        done.enter()
        queue?.async { [weak self] in
            self?.runLoopResumed()
        }
    }

    /// Assembles the result. Call only after the loop exited.
    public func finishImage() -> CGImage? {
        stitcher.finish()
    }

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(
            keptFrames: keptFrames,
            totalDelta: cachedDelta,
            statusText: statusText,
            statusWarning: statusWarning,
            stalled: stalled,
            ended: ended,
            full: full,
            fellBackToManual: fellBackToManual,
            failed: failed
        )
    }

    // MARK: - Private state helpers (any thread, locked)

    private func isStopped() -> Bool {
        lock.lock(); defer { lock.unlock() }; return stopRequested
    }

    private func setStatus(_ text: String, warning: Bool = false, force: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        // Throttle repetitive warnings unless forced.
        if warning && !force && text == statusText && statusWarning {
            return
        }
        statusText = text
        statusWarning = warning
    }

    private func setWarnThrottled(_ text: String) {
        lock.lock()
        let now = Date()
        let due = now.timeIntervalSince(lastWarnAt) > 3.0 || statusText != text
        if due { lastWarnAt = now }
        lock.unlock()
        if due { setStatus(text, warning: true) }
    }

    private func markKept() {
        lock.lock(); keptFrames += 1; cachedDelta = stitcher.totalDelta; lock.unlock()
    }

    // MARK: - Capture

    private func grab() -> CGImage? {
        let r = regionQuartz
        guard r.width > 4, r.height > 4 else { return nil }
        return CGWindowListCreateImage(r, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    }

    private func gray(of image: CGImage) -> GrayView {
        GrayView(image: image, axis: axis)
    }

    private func graysEqual(_ a: GrayView, _ b: GrayView) -> Bool {
        a.width == b.width && a.height == b.height && a.pixels == b.pixels
    }

    private func run() {
        defer {
            lock.lock(); exited = true; lock.unlock()
            done.leave()
        }
        guard !isStopped() else { return }
        guard let first = grab() else {
            lock.lock()
            failed = true
            statusText = "Screen capture is not delivering frames"
            statusWarning = true
            lock.unlock()
            return
        }
        stitcher.start(initialFrame: first)
        markKept()
        let extentPx = axis == .vertical ? first.height : first.width
        let crossPx = axis == .vertical ? first.width : first.height
        setStatus(mode == .manual
                  ? "Scroll the page · Done stitches it"
                  : "Auto-scrolling… · keep the pointer still · Done stitches it")
        if mode == .manual {
            manualLoop(crossPx: crossPx)
        } else {
            autoLoop(firstExtentPx: extentPx, crossPx: crossPx)
        }
    }

    private func runLoopResumed() {
        defer {
            lock.lock(); exited = true; lock.unlock()
            done.leave()
        }
        lock.lock()
        exited = false
        stopRequested = false
        lock.unlock()
        // Resume always continues in auto; manual never stalls.
        if let first = grab() {
            let extentPx = axis == .vertical ? first.height : first.width
            autoLoop(firstExtentPx: extentPx, crossPx: axis == .vertical ? first.width : first.height)
        }
    }

    private func noteProgress() {
        lock.lock()
        let kept = keptFrames
        let isFull = full
        lock.unlock()
        let frames = "\(kept) frame\(kept == 1 ? "" : "s")"
        if isFull {
            setStatus("Capture is as long as it can get · press Done to stitch it, or Cancel", warning: true, force: true)
        } else {
            setStatus("Capturing · \(frames) · Done when finished")
        }
    }

    private func checkBudget(crossPx: Int, axisBasePx: Int) -> Bool {
        // Estimated finished bytes if we keep growing.
        let axisNow = axisBasePx + stitcher.totalDelta
        let bytes = Int64(crossPx) * Int64(axisNow) * 4
        if bytes > Int64(Self.kMaxStitchedBytes) { return true }
        if axisNow > Self.kWidelyOpenableEdge {
            // Advisory only; surfaced via `full` hint.
            lock.lock(); full = true; lock.unlock()
        }
        return false
    }

    // MARK: - Manual loop: classify every poll

    private func manualLoop(crossPx: Int) {
        var failures = 0
        var axisBase = 0
        while !isStopped() {
            Thread.sleep(forTimeInterval: 0.12)
            if isStopped() { break }
            guard let frame = grab() else {
                failures += 1
                if failures == 40 {
                    setStatus("Screen capture is not delivering frames", warning: true, force: true)
                }
                continue
            }
            failures = 0
            if axisBase == 0 { axisBase = axis == .vertical ? frame.height : frame.width }
            let motion = stitcher.addFrame(frame)
            switch motion.kind {
            case .forward where motion.delta > 2:
                markKept()
                if checkBudget(crossPx: crossPx, axisBasePx: axisBase) {
                    setStatus("Capture is as long as it can get · press Done to stitch it, or Cancel", warning: true, force: true)
                    lock.lock(); full = true; lock.unlock()
                    return
                }
                noteProgress()
            case .stationary:
                break
            case .ambiguous:
                setWarnThrottled("Repeated content · keep scrolling to a distinctive part")
            case .unmatchable:
                setWarnThrottled("Can't align · scroll back a little; moving content (video) can't be captured")
            case .reverse:
                setWarnThrottled("Scroll the other way to continue this capture (or Done to stitch what you have)")
            case .forward:
                break
            }
        }
    }

    // MARK: - Auto loop: inject → settle → feed

    private func regionCenterQuartz() -> CGPoint {
        CGPoint(x: regionQuartz.midX, y: regionQuartz.midY)
    }

    private func autoLoop(firstExtentPx: Int, crossPx: Int) {
        // Pixels to scroll per tick: ~45% of the region so frames overlap
        // generously at any scroll speed.
        let stepPx = max(60, min(600, Int(Double(firstExtentPx) * 0.45)))
        var sign: Int32 = -1 // assume negative scrolls down/right; flipped on stall
        var stationaryStreak = 0
        var unmatchStreak = 0
        var ticksWithoutCommit = 0
        var flippedSign = false
        let axisBase = firstExtentPx
        while !isStopped() {
            let at = regionCenterQuartz()
            if axis == .vertical {
                ScrollInjector.injectScroll(deltaY: sign * Int32(stepPx), at: at)
            } else {
                ScrollInjector.injectScroll(deltaY: 0, deltaX: sign * Int32(stepPx), at: at)
            }
            ticksWithoutCommit += 1

            // Wait for motion to start.
            guard let pre = grab() else { Thread.sleep(forTimeInterval: 0.1); continue }
            let preGray = gray(of: pre)
            var movedGray: GrayView? = nil
            var movedImage: CGImage? = nil
            let motionDeadline = Date().addingTimeInterval(0.7)
            while Date() < motionDeadline && !isStopped() {
                Thread.sleep(forTimeInterval: 0.08)
                guard let g = grab() else { continue }
                let gg = gray(of: g)
                if !graysEqual(gg, preGray) {
                    movedGray = gg; movedImage = g
                    break
                }
            }
            guard let _ = movedGray, movedImage != nil else {
                // Genuinely stationary (page end, or wheel went elsewhere).
                stationaryStreak += 1
                if stationaryStreak >= 2 && keptFramesSnapshot() >= 1 {
                    stallEnded()
                    return
                }
                if ticksWithoutCommit >= 8 && keptFramesSnapshot() <= 1 && !flippedSign {
                    flippedSign = true
                    sign = -sign
                    ticksWithoutCommit = 0
                    stationaryStreak = 0
                    setStatus("Trying the other direction…", warning: true, force: true)
                    continue
                }
                if ticksWithoutCommit >= 16 {
                    stallUnavailable()
                    return
                }
                continue
            }

            // Settle: two consecutive identical grabs, cap 2s.
            var settled = movedImage!
            var last = movedGray!
            let settleDeadline = Date().addingTimeInterval(2.0)
            while Date() < settleDeadline && !isStopped() {
                Thread.sleep(forTimeInterval: 0.08)
                guard let g = grab() else { continue }
                let gg = gray(of: g)
                if graysEqual(gg, last) {
                    settled = g
                    break
                }
                last = gg
                settled = g
            }

            let motion = stitcher.addFrame(settled)
            switch motion.kind {
            case .forward where motion.delta > 2:
                markKept()
                stationaryStreak = 0
                unmatchStreak = 0
                ticksWithoutCommit = 0
                if checkBudget(crossPx: crossPx, axisBasePx: axisBase) {
                    setStatus("Capture is as long as it can get · press Done to stitch it, or Cancel", warning: true, force: true)
                    lock.lock(); full = true; lock.unlock()
                    return
                }
                noteProgress()
                // Steps command pixels directly, so the 45% overlap holds by
                // construction; no notch fitting needed.
            case .stationary:
                stationaryStreak += 1
                if stationaryStreak >= 3 && keptFramesSnapshot() >= 1 {
                    stallEnded()
                    return
                }
            case .unmatchable, .ambiguous:
                unmatchStreak += 1
                if unmatchStreak == 1 {
                    setWarnThrottled("Verifying scroll alignment…")
                }
                if unmatchStreak >= 10 {
                    stallAlignment()
                    return
                }
            case .reverse:
                setWarnThrottled("Scroll the other way to continue this capture (or Done to stitch what you have)")
                stallAlignment()
                return
            case .forward:
                break
            }
        }
    }

    private func keptFramesSnapshot() -> Int {
        lock.lock(); defer { lock.unlock() }; return keptFrames
    }

    private func stallEnded() {
        lock.lock()
        stalled = true
        ended = true
        statusText = "End reached · Continue carries on, Done stitches it"
        statusWarning = false
        lock.unlock()
    }

    private func stallAlignment() {
        lock.lock()
        stalled = true
        statusText = "Auto-scroll paused: capture lost alignment · Continue tries again, Done stitches what was verified"
        statusWarning = true
        lock.unlock()
    }

    private func stallUnavailable() {
        // Injector almost certainly lacks Accessibility trust: keep verified
        // frames and fall back to manual on the same session.
        lock.lock()
        fellBackToManual = true
        statusText = "Auto-scroll unavailable · scroll manually · Done stitches"
        statusWarning = true
        lock.unlock()
        manualLoop(crossPx: 0)
    }
}
