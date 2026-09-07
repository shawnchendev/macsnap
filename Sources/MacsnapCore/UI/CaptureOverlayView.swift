import Foundation
import CoreGraphics
import Cocoa

public enum CaptureOverlayPhase {
    case select
    case edit
}

public enum CaptureKind: String, CaseIterable, Sendable {
    case region = "Region"
    case window = "Window"
    case scroll = "Scrolling Region"
    case fullscreen = "Fullscreen"
}

public enum EditorTool: Equatable, Sendable {
    case select
    case arrow
    case line
    case freehand
    case highlighter
    case spotlight
    case marker
    case rectangle
    case ellipse
    case redact
    case cut
    case text
    case ocr
    case eyedropper
}

public enum HighlighterMode {
    case snap
    case normal
}

public final class CaptureOverlayView: NSView, NSTextFieldDelegate {
    // Data
    public var captureData: ScreenCaptureData
    public var pristineSource: CGImage
    public var appConfig: AppConfig

    // Phase & Modes
    public var phase: CaptureOverlayPhase = .select
    public var captureKind: CaptureKind = .region
    public var tool: EditorTool = .select
    public var highlighterMode: HighlighterMode = .snap

    // Selection in select phase
    public var selection: CGRect = .zero
    public var lastDrawnRegion: CGRect = .zero
    public var hoveredWindow: WindowTarget? = nil
    public var quickOutputMode: QuickOutputMode = .none

    // Recents Shelf
    public let recentsShelf = RecentsShelfView()

    // Toolbar
    public let toolbar = ToolbarView()

    // Operation Log & State
    public var opLog = OperationLog()
    public var activeAnnotations: [Annotation] = []
    public var activeCuts: [CutOp] = []
    public var activeCrop: CGRect = .zero
    public var backdropStyle: BackdropStyle = .none
    public var imageShadow: Bool = true
    public var canvasBoundaryMode: CanvasBoundaryMode = .image
    public var selectedAnnotationIndices: Set<Int> = []
    public var nextMarker: Int = 1

    // Colors & Styles
    public var activeColorHex: String = "#ff375f"
    public var strokeSize: Double = 4.0
    public var shapeFilled: Bool = false
    public var cornerRadius: Double = 0.0
    public var redactionStyle: RedactionStyle = .pixelate
    public var spotlightShape: SpotlightShape = .ellipse
    public var spotlightZoom: Double = 2.0
    public var textFont: TextFont = .system
    public var textBackground: TextBackground = .plain

    // Dragging & Interaction State
    private var isMouseDown: Bool = false
    private var dragStart: CGPoint = .zero
    private var currentMousePoint: CGPoint = .zero
    private var activeFreehandPoints: [CGPoint] = []
    private var activeSnapLock: TextBand? = nil
    private var liveCutBand: (orientation: CutOrientation, start: Double, end: Double)? = nil
    private var activeHandle: InteractionHandle? = nil
    public var initialCaptureSelection: CGRect = .zero
    private var hoveredCropHandleIndex: Int? = nil
    private var cropDragStartMouse: CGPoint = .zero
    private var initialSelectionBeforeCrop: CGRect = .zero
    private var initialAnnotationsBeforeCrop: [Annotation] = []
    private var cropScaleFactor: CGFloat = 1.0

    // Annotation Drag & Move
    private var isDraggingAnnotation: Bool = false
    private var dragAnnotationStartMouse: CGPoint = .zero
    private var dragAnnotationInitialStates: [(index: Int, annotation: Annotation)] = []

    // View Pan & Zoom
    public var viewZoom: CGFloat = 1.0
    public var viewOffset: CGPoint = .zero
    private var isPanning: Bool = false
    private var panStart: CGPoint = .zero

    // Inline text editing
    public var editingTextAnnotationIndex: Int? = nil
    private var activeInlineTextField: NSTextField? = nil

    // OCR overlay feedback
    public var ocrTextResult: String? = nil
    public var isScanningOCR: Bool = false
    public var ocrStatusMessage: String? = nil
    private var ocrCardRect: CGRect? = nil
    private var ocrCloseButtonRect: CGRect? = nil
    private var ocrCopyButtonRect: CGRect? = nil
    private var ocrDismissButtonRect: CGRect? = nil

    // Scrolling capture state
    public var isScrollingCaptureActive: Bool = false
    public var stitcher: Stitcher? = nil
    private var scrollTimer: Timer? = nil

    public enum InteractionHandle: Equatable {
        case move
        case resizeStart
        case resizeEnd
        case boxResize(Int) // 0..7 clockwise
        case cropHandle(Int) // 0..7
    }

    public init(captureData: ScreenCaptureData, appConfig: AppConfig = AppConfig.load()) {
        self.captureData = captureData
        self.pristineSource = captureData.image
        self.appConfig = appConfig
        self.backdropStyle = appConfig.defaultBackdropStyle
        self.canvasBoundaryMode = (appConfig.defaultBackdropStyle == .none || appConfig.defaultBackdropStyle == .off) ? .image : .framed
        super.init(frame: NSRect(origin: .zero, size: captureData.screenBounds.size))

        self.wantsLayer = true
        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTracking() {
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]
        let ta = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(ta)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSafeArea()
    }

    public func updateSafeArea() {
        let screen = self.window?.screen ?? NSScreen.main
        if let screen = screen {
            let inset = screen.safeAreaInsets.top
            if inset > 0 {
                toolbar.safeAreaTop = inset
            } else if screen.auxiliaryTopLeftArea != nil {
                toolbar.safeAreaTop = 32.0
            } else {
                toolbar.safeAreaTop = 0.0
            }
        }
    }

    // MARK: - Geometry mapping

    public override var isFlipped: Bool {
        return true
    }

    public var effectiveScale: CGFloat {
        captureData.scaleFactor
    }

    public func currentCanvasRect() -> CGRect {
        let baseSize = selection.isEmpty ? self.bounds.size : selection.size
        return RenderPipeline.computeCanvasRect(
            baseSize: baseSize,
            annotations: activeAnnotations,
            boundaryMode: canvasBoundaryMode,
            backdropStyle: backdropStyle
        )
    }

    public func imageRectOnScreen() -> CGRect {
        if phase == .select {
            return self.bounds
        }
        // In Edit phase, fit canvas into screen with margins
        let canvas = currentCanvasRect()
        let marginX: CGFloat = 80.0
        let barBottom = toolbar.toolbarRect(screenBounds: self.bounds).maxY
        let topMargin: CGFloat = max(70.0, barBottom + 24.0) // space for floating top toolbar and hover tooltips
        let bottomMargin: CGFloat = 30.0
        let availW = self.bounds.width - marginX * 2
        let availH = self.bounds.height - (topMargin + bottomMargin)

        let scale = min(availW / max(1, canvas.width), availH / max(1, canvas.height), 1.0) * viewZoom
        let drawW = canvas.width * scale
        let drawH = canvas.height * scale
        let drawX = (self.bounds.width - drawW) / 2.0 + viewOffset.x
        let drawY = topMargin + (availH - drawH) / 2.0 + viewOffset.y
        return CGRect(x: drawX, y: drawY, width: drawW, height: drawH)
    }

    public func toAnnotationPoint(_ screenPoint: CGPoint) -> CGPoint {
        let imgRect = imageRectOnScreen()
        let canvas = currentCanvasRect()
        guard imgRect.width > 0, imgRect.height > 0 else { return screenPoint }
        let relX = canvas.minX + (screenPoint.x - imgRect.minX) / (imgRect.width / max(1, canvas.width))
        let relY = canvas.minY + (screenPoint.y - imgRect.minY) / (imgRect.height / max(1, canvas.height))
        return CGPoint(x: relX, y: relY)
    }

    public func toScreenPoint(_ annPoint: CGPoint) -> CGPoint {
        let imgRect = imageRectOnScreen()
        let canvas = currentCanvasRect()
        let screenX = imgRect.minX + (annPoint.x - canvas.minX) * (imgRect.width / max(1, canvas.width))
        let screenY = imgRect.minY + (annPoint.y - canvas.minY) * (imgRect.height / max(1, canvas.height))
        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        updateSafeArea()
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if phase == .select {
            drawSelectPhase(in: context)
        } else {
            drawEditPhase(in: context)
        }
    }

    private func drawSelectPhase(in context: CGContext) {
        let bounds = self.bounds

        // 1. Draw frozen desktop background
        let nsImage = NSImage(cgImage: pristineSource, size: bounds.size)
        nsImage.draw(in: bounds)

        // 2. Dimmed scrim over unselected area
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.35).cgColor)
        context.fill(bounds)

        // 3. Highlight selected region or window
        var activeRect: CGRect? = nil
        if captureKind == .window, let win = hoveredWindow {
            // Window rect
            activeRect = win.rect
        } else if !selection.isEmpty {
            activeRect = selection
        }

        if let rect = activeRect {
            // Cut out the clear hole for the selected area
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            // Draw crisp border around selection
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.stroke(rect)
        }
        context.restoreGState()

        // 4. Capture Kind Tabs at top center
        drawCaptureTabs(in: context)

        // 5. Recents shelf along right edge
        recentsShelf.draw(in: context, screenBounds: bounds)

        // 6. Pointer Measurement Readout
        let readoutText: String
        if isMouseDown && !selection.isEmpty {
            let nativeW = Int(round(abs(selection.width) * effectiveScale))
            let nativeH = Int(round(abs(selection.height) * effectiveScale))
            readoutText = "\(nativeW) × \(nativeH) px"
        } else if captureKind == .window, let win = hoveredWindow {
            let nativeW = Int(round(win.rect.width * effectiveScale))
            let nativeH = Int(round(win.rect.height * effectiveScale))
            readoutText = "\(win.appName) · \(nativeW) × \(nativeH) px"
        } else {
            let pxX = Int(round(currentMousePoint.x * effectiveScale))
            let pxY = Int(round(currentMousePoint.y * effectiveScale))
            readoutText = "\(pxX), \(pxY)"
        }
        MeasurementReadout.drawReadout(in: context, at: currentMousePoint, text: readoutText, screenBounds: bounds)
    }

    private func drawCaptureTabs(in context: CGContext) {
        let kinds = CaptureKind.allCases
        let tabH: CGFloat = 32.0
        let tabW: CGFloat = 110.0
        let totalW = tabW * CGFloat(kinds.count)
        let barRect = CGRect(x: self.bounds.midX - totalW / 2.0, y: 16, width: totalW, height: tabH)

        context.saveGState()

        // Bar background
        let path = CGPath(roundedRect: barRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.92).cgColor)
        context.fillPath()
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        for (i, kind) in kinds.enumerated() {
            let rect = CGRect(x: barRect.minX + CGFloat(i) * tabW, y: barRect.minY, width: tabW, height: tabH)
            let isSelected = (kind == captureKind)

            if isSelected {
                let selPath = CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: 6, cornerHeight: 6, transform: nil)
                context.addPath(selPath)
                context.setFillColor(NSColor(white: 1.0, alpha: 0.2).cgColor)
                context.fillPath()
            }

            let font = NSFont.systemFont(ofSize: 11, weight: isSelected ? .bold : .medium)
            let color = isSelected ? NSColor.white : NSColor(white: 0.75, alpha: 1.0)
            let str = NSAttributedString(string: kind.rawValue, attributes: [
                .font: font,
                .foregroundColor: color
            ])
            let size = str.size()
            str.draw(at: CGPoint(x: rect.midX - size.width / 2.0, y: rect.midY - size.height / 2.0))
        }

        context.restoreGState()
    }

    private func drawEditPhase(in context: CGContext) {
        let bounds = self.bounds

        // 1. Dark translucent workspace scrim
        context.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 0.92).cgColor)
        context.fill(bounds)

        let targetRect = imageRectOnScreen()

        // 2. Render capture (card, background, redactions, spotlights, annotations)
        let visibleAnnotations: [Annotation]
        if let editIdx = editingTextAnnotationIndex, editIdx < activeAnnotations.count {
            var copy = activeAnnotations
            copy[editIdx].text = "" // Hide text while inline editing
            visibleAnnotations = copy
        } else {
            visibleAnnotations = activeAnnotations
        }

        if let rendered = RenderPipeline.renderCapture(
            source: pristineSource,
            selection: selection,
            annotations: visibleAnnotations,
            backdropStyle: backdropStyle,
            imageShadow: imageShadow,
            boundaryMode: canvasBoundaryMode,
            scale: effectiveScale
        ) {
            let nsRendered = NSImage(cgImage: rendered, size: targetRect.size)
            nsRendered.draw(in: targetRect)
        }

        // 3. Live drawing preview (arrows, lines, freehand, live cut band, highlighter, ocr box)
        drawLiveToolPreview(in: context, targetRect: targetRect)

        // 4. Draw 8 external recropping handles
        drawCropHandles(in: context, targetRect: targetRect)

        // 5. Draw selection boxes around selected annotations
        drawSelectedAnnotationChrome(in: context)

        // 6. Draw floating top toolbar
        toolbar.draw(in: context, screenBounds: bounds)

        // 7. OCR overlay if scanning or showing result
        if isScanningOCR {
            drawOCRScanning(in: context, targetRect: targetRect)
        } else if let result = ocrTextResult {
            drawOCRResultCard(in: context, targetRect: targetRect, text: result)
        }

        // 8. Status Toast (e.g. OCR copied feedback)
        if let msg = ocrStatusMessage {
            drawStatusToast(in: context, message: msg, screenBounds: bounds)
        }

        // 9. Measurement readout when dragging crop handle
        if case .cropHandle = activeHandle {
            let nativeW = Int(round(selection.width * effectiveScale))
            let nativeH = Int(round(selection.height * effectiveScale))
            MeasurementReadout.drawReadout(in: context, at: currentMousePoint, text: "\(nativeW) × \(nativeH) px", screenBounds: bounds)
        }
    }

    private func drawLiveToolPreview(in context: CGContext, targetRect: CGRect) {
        if isMouseDown && tool == .cut, let cut = liveCutBand {
            // Cut tool preview: shaded removal band + dashed seam line
            context.saveGState()
            context.setFillColor(NSColor(calibratedRed: 1.0, green: 0.2, blue: 0.2, alpha: 0.35).cgColor)
            let p1 = toScreenPoint(CGPoint(x: cut.start, y: cut.start))
            let p2 = toScreenPoint(CGPoint(x: cut.end, y: cut.end))

            let cutRect: CGRect
            if cut.orientation == .horizontal {
                cutRect = CGRect(x: targetRect.minX, y: min(p1.y, p2.y), width: targetRect.width, height: abs(p2.y - p1.y))
            } else {
                cutRect = CGRect(x: min(p1.x, p2.x), y: targetRect.minY, width: abs(p2.x - p1.x), height: targetRect.height)
            }
            context.fill(cutRect)

            // Dashed seam line
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.setLineWidth(1.5)
            if cut.orientation == .horizontal {
                context.move(to: CGPoint(x: targetRect.minX, y: cutRect.midY))
                context.addLine(to: CGPoint(x: targetRect.maxX, y: cutRect.midY))
            } else {
                context.move(to: CGPoint(x: cutRect.midX, y: targetRect.minY))
                context.addLine(to: CGPoint(x: cutRect.midX, y: targetRect.maxY))
            }
            context.strokePath()
            context.restoreGState()
        }

        if tool == .highlighter && highlighterMode == .snap, let lock = activeSnapLock {
            // Snap highlighter I-beam preview
            let topPt = toScreenPoint(CGPoint(x: 0, y: lock.top))
            let botPt = toScreenPoint(CGPoint(x: 0, y: lock.bottom))
            let h = abs(botPt.y - topPt.y)

            context.saveGState()
            context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(2.0)
            context.move(to: CGPoint(x: currentMousePoint.x - 8, y: currentMousePoint.y - h / 2.0))
            context.addLine(to: CGPoint(x: currentMousePoint.x + 8, y: currentMousePoint.y - h / 2.0))
            context.move(to: CGPoint(x: currentMousePoint.x, y: currentMousePoint.y - h / 2.0))
            context.addLine(to: CGPoint(x: currentMousePoint.x, y: currentMousePoint.y + h / 2.0))
            context.move(to: CGPoint(x: currentMousePoint.x - 8, y: currentMousePoint.y + h / 2.0))
            context.addLine(to: CGPoint(x: currentMousePoint.x + 8, y: currentMousePoint.y + h / 2.0))
            context.strokePath()
            context.restoreGState()
        }

        // Live rubber-band vector preview
        if isMouseDown && phase == .edit {
            let color = NSColor(hex: activeColorHex) ?? NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.37, alpha: 1.0)
            context.saveGState()
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            context.setLineWidth(strokeSize)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            switch tool {
            case .arrow:
                RenderPipeline.drawArrow(in: context, from: dragStart, to: currentMousePoint, width: strokeSize)

            case .line:
                context.move(to: dragStart)
                context.addLine(to: currentMousePoint)
                context.strokePath()

            case .rectangle:
                let r = CGRect(
                    x: min(dragStart.x, currentMousePoint.x),
                    y: min(dragStart.y, currentMousePoint.y),
                    width: abs(currentMousePoint.x - dragStart.x),
                    height: abs(currentMousePoint.y - dragStart.y)
                )
                if cornerRadius > 0 {
                    let path = CGPath(roundedRect: r, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                    context.addPath(path)
                } else {
                    context.addRect(r)
                }
                if shapeFilled {
                    context.fillPath()
                } else {
                    context.strokePath()
                }

            case .ellipse:
                let r = CGRect(
                    x: min(dragStart.x, currentMousePoint.x),
                    y: min(dragStart.y, currentMousePoint.y),
                    width: abs(currentMousePoint.x - dragStart.x),
                    height: abs(currentMousePoint.y - dragStart.y)
                )
                if shapeFilled {
                    context.fillEllipse(in: r)
                } else {
                    context.strokeEllipse(in: r)
                }

            case .freehand:
                if activeFreehandPoints.count > 1 {
                    let p0 = toScreenPoint(activeFreehandPoints[0])
                    context.move(to: p0)
                    for pt in activeFreehandPoints.dropFirst() {
                        context.addLine(to: toScreenPoint(pt))
                    }
                    context.strokePath()
                }

            case .highlighter:
                if highlighterMode == .normal {
                    let highColor = color.withAlphaComponent(0.38)
                    context.setStrokeColor(highColor.cgColor)
                    context.setLineWidth(strokeSize * 3.5)
                    context.setLineCap(.square)
                    if activeFreehandPoints.count > 1 {
                        let p0 = toScreenPoint(activeFreehandPoints[0])
                        context.move(to: p0)
                        for pt in activeFreehandPoints.dropFirst() {
                            context.addLine(to: toScreenPoint(pt))
                        }
                        context.strokePath()
                    } else {
                        context.move(to: dragStart)
                        context.addLine(to: currentMousePoint)
                        context.strokePath()
                    }
                }

            case .redact:
                let r = CGRect(
                    x: min(dragStart.x, currentMousePoint.x),
                    y: min(dragStart.y, currentMousePoint.y),
                    width: abs(currentMousePoint.x - dragStart.x),
                    height: abs(currentMousePoint.y - dragStart.y)
                )
                context.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.45).cgColor)
                context.fill(r)
                context.setStrokeColor(NSColor.white.cgColor)
                context.setLineDash(phase: 0, lengths: [4, 4])
                context.setLineWidth(1.5)
                context.stroke(r)

            case .spotlight:
                let r = CGRect(
                    x: min(dragStart.x, currentMousePoint.x),
                    y: min(dragStart.y, currentMousePoint.y),
                    width: abs(currentMousePoint.x - dragStart.x),
                    height: abs(currentMousePoint.y - dragStart.y)
                )
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(max(2.0, strokeSize))
                switch spotlightShape {
                case .ellipse:
                    context.strokeEllipse(in: r)
                case .rectangle:
                    context.stroke(r)
                case .rounded:
                    let path = CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)
                    context.addPath(path)
                    context.strokePath()
                }

            case .ocr:
                let r = CGRect(
                    x: min(dragStart.x, currentMousePoint.x),
                    y: min(dragStart.y, currentMousePoint.y),
                    width: abs(currentMousePoint.x - dragStart.x),
                    height: abs(currentMousePoint.y - dragStart.y)
                )
                context.setFillColor(NSColor(calibratedRed: 0.0, green: 0.8, blue: 1.0, alpha: 0.15).cgColor)
                context.fill(r)
                context.setStrokeColor(NSColor.systemCyan.cgColor)
                context.setLineWidth(1.5)
                context.setLineDash(phase: 0, lengths: [4, 4])
                context.stroke(r)
                let font = NSFont.systemFont(ofSize: 11, weight: .bold)
                let str = NSAttributedString(string: "Scan Text (OCR)", attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white
                ])
                str.draw(at: CGPoint(x: r.minX + 6, y: max(r.minY - 18, 16)))

            default:
                break
            }
            context.restoreGState()
        }
    }

    public func cropHandleRects() -> [CGRect] {
        let maxW = CGFloat(pristineSource.width) / effectiveScale
        let maxH = CGFloat(pristineSource.height) / effectiveScale
        let baseSize = selection.isEmpty ? CGSize(width: maxW, height: maxH) : selection.size
        let cardP1 = toScreenPoint(CGPoint(x: 0, y: 0))
        let cardP2 = toScreenPoint(CGPoint(x: baseSize.width, y: baseSize.height))
        let cardRect = CGRect(
            x: min(cardP1.x, cardP2.x),
            y: min(cardP1.y, cardP2.y),
            width: abs(cardP2.x - cardP1.x),
            height: abs(cardP2.y - cardP1.y)
        )

        let handleSize: CGFloat = 10.0
        let pts: [CGPoint] = [
            CGPoint(x: cardRect.minX, y: cardRect.minY), // 0: Top-Left
            CGPoint(x: cardRect.midX, y: cardRect.minY), // 1: Top-Mid
            CGPoint(x: cardRect.maxX, y: cardRect.minY), // 2: Top-Right
            CGPoint(x: cardRect.maxX, y: cardRect.midY), // 3: Mid-Right
            CGPoint(x: cardRect.maxX, y: cardRect.maxY), // 4: Bottom-Right
            CGPoint(x: cardRect.midX, y: cardRect.maxY), // 5: Bottom-Mid
            CGPoint(x: cardRect.minX, y: cardRect.maxY), // 6: Bottom-Left
            CGPoint(x: cardRect.minX, y: cardRect.midY)  // 7: Mid-Left
        ]

        return pts.map { pt in
            CGRect(x: pt.x - handleSize / 2.0, y: pt.y - handleSize / 2.0, width: handleSize, height: handleSize)
        }
    }

    public func cropHandleIndex(at point: CGPoint) -> Int? {
        let rects = cropHandleRects()
        for (i, r) in rects.enumerated() {
            if r.insetBy(dx: -6, dy: -6).contains(point) {
                return i
            }
        }
        return nil
    }

    public func cursorForCropHandle(_ index: Int) -> NSCursor {
        switch index {
        case 0, 4: // Top-left or bottom-right
            let sel = Selector(("_windowResizeNorthWestSouthEastCursor"))
            if NSCursor.responds(to: sel), let c = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
                return c
            }
            return .crosshair
        case 2, 6: // Top-right or bottom-left
            let sel = Selector(("_windowResizeNorthEastSouthWestCursor"))
            if NSCursor.responds(to: sel), let c = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
                return c
            }
            return .crosshair
        case 1, 5: // Top-mid or bottom-mid
            return .resizeUpDown
        case 3, 7: // Mid-right or mid-left
            return .resizeLeftRight
        default:
            return .arrow
        }
    }

    private func drawCropHandles(in context: CGContext, targetRect: CGRect) {
        let rects = cropHandleRects()

        context.saveGState()
        for (i, rect) in rects.enumerated() {
            let isHoveredOrActive = (i == hoveredCropHandleIndex) || (activeHandle == .cropHandle(i))

            context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor(white: 0, alpha: 0.45).cgColor)

            let path = CGPath(rect: rect, transform: nil)
            context.addPath(path)
            if isHoveredOrActive {
                context.setFillColor(NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1.0).cgColor)
            } else {
                context.setFillColor(NSColor.white.cgColor)
            }
            context.fillPath()

            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.addPath(path)
            context.setStrokeColor(NSColor(red: 0.05, green: 0.40, blue: 0.95, alpha: 1.0).cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func handleCropDrag(handleIndex: Int) {
        let initSel = initialSelectionBeforeCrop
        let maxW = CGFloat(pristineSource.width) / effectiveScale
        let maxH = CGFloat(pristineSource.height) / effectiveScale

        let deltaScreenX = currentMousePoint.x - cropDragStartMouse.x
        let deltaScreenY = currentMousePoint.y - cropDragStartMouse.y
        let deltaX = deltaScreenX * cropScaleFactor
        let deltaY = deltaScreenY * cropScaleFactor

        var newMinX = initSel.minX
        var newMaxX = initSel.maxX
        var newMinY = initSel.minY
        var newMaxY = initSel.maxY

        // Horizontal resizing
        switch handleIndex {
        case 0, 6, 7: // Left edge / corners
            let candidate = initSel.minX + deltaX
            newMinX = max(0.0, min(initSel.maxX - 20.0, candidate))
        case 2, 3, 4: // Right edge / corners
            let candidate = initSel.maxX + deltaX
            newMaxX = max(initSel.minX + 20.0, min(maxW, candidate))
        default:
            break
        }

        // Vertical resizing
        switch handleIndex {
        case 0, 1, 2: // Top edge / corners
            let candidate = initSel.minY + deltaY
            newMinY = max(0.0, min(initSel.maxY - 20.0, candidate))
        case 4, 5, 6: // Bottom edge / corners
            let candidate = initSel.maxY + deltaY
            newMaxY = max(initSel.minY + 20.0, min(maxH, candidate))
        default:
            break
        }

        let newSelection = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
        let shiftX = newMinX - initSel.minX
        let shiftY = newMinY - initSel.minY

        if shiftX != 0 || shiftY != 0 {
            self.activeAnnotations = initialAnnotationsBeforeCrop.map { ann in
                var updated = ann
                updated.start = CGPoint(x: ann.start.x - shiftX, y: ann.start.y - shiftY)
                updated.end = CGPoint(x: ann.end.x - shiftX, y: ann.end.y - shiftY)
                if !ann.points.isEmpty {
                    updated.points = ann.points.map { CGPoint(x: $0.x - shiftX, y: $0.y - shiftY) }
                }
                return updated
            }
        } else {
            self.activeAnnotations = initialAnnotationsBeforeCrop
        }
        self.selection = newSelection
        self.activeCrop = newSelection
    }

    private func drawSelectedAnnotationChrome(in context: CGContext) {
        guard !selectedAnnotationIndices.isEmpty else { return }

        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.setLineWidth(1.5)

        for idx in selectedAnnotationIndices {
            guard idx < activeAnnotations.count else { continue }
            let ann = activeAnnotations[idx]
            let bounds = ann.bounds
            let p1 = toScreenPoint(CGPoint(x: bounds.minX, y: bounds.minY))
            let p2 = toScreenPoint(CGPoint(x: bounds.maxX, y: bounds.maxY))
            let screenRect = CGRect(x: min(p1.x, p2.x) - 4, y: min(p1.y, p2.y) - 4, width: abs(p2.x - p1.x) + 8, height: abs(p2.y - p1.y) + 8)

            context.stroke(screenRect)

            // Draw handles at corners
            let handleSize: CGFloat = 6.0
            let corners = [
                CGPoint(x: screenRect.minX, y: screenRect.minY),
                CGPoint(x: screenRect.maxX, y: screenRect.minY),
                CGPoint(x: screenRect.maxX, y: screenRect.maxY),
                CGPoint(x: screenRect.minX, y: screenRect.maxY)
            ]
            for corner in corners {
                let hRect = CGRect(x: corner.x - handleSize / 2.0, y: corner.y - handleSize / 2.0, width: handleSize, height: handleSize)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(hRect)
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(1.0)
                context.stroke(hRect)
            }
        }
        context.restoreGState()
    }

    private func drawOCRScanning(in context: CGContext, targetRect: CGRect) {
        context.saveGState()

        // Shaded scanning overlay over targetRect
        context.setFillColor(NSColor(calibratedRed: 0.0, green: 0.8, blue: 1.0, alpha: 0.08).cgColor)
        context.fill(targetRect)

        // Glowing scanning beam
        context.setStrokeColor(NSColor.systemCyan.cgColor)
        context.setLineWidth(2.5)
        context.setShadow(offset: .zero, blur: 8, color: NSColor.systemCyan.cgColor)
        context.move(to: CGPoint(x: targetRect.minX, y: targetRect.midY))
        context.addLine(to: CGPoint(x: targetRect.maxX, y: targetRect.midY))
        context.strokePath()

        // Scanning pill HUD in center
        let hudW: CGFloat = 240.0
        let hudH: CGFloat = 34.0
        let hudRect = CGRect(x: targetRect.midX - hudW / 2.0, y: targetRect.midY - hudH / 2.0, width: hudW, height: hudH)
        let pillPath = CGPath(roundedRect: hudRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: NSColor(white: 0, alpha: 0.5).cgColor)
        context.addPath(pillPath)
        context.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.95).cgColor)
        context.fillPath()

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(pillPath)
        context.setStrokeColor(NSColor.systemCyan.cgColor)
        context.setLineWidth(1.2)
        context.strokePath()

        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let str = NSAttributedString(string: "Scanning text (Apple Vision)...", attributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ])
        let strSize = str.size()
        str.draw(at: CGPoint(x: hudRect.midX - strSize.width / 2.0, y: hudRect.midY - strSize.height / 2.0))

        context.restoreGState()
    }

    private func drawOCRResultCard(in context: CGContext, targetRect: CGRect, text: String) {
        let bounds = self.bounds
        let cardW: CGFloat = 340.0
        let cardH: CGFloat = min(400.0, max(220.0, targetRect.height))
        var cardX = targetRect.maxX + 16.0
        if cardX + cardW > bounds.maxX - 16.0 {
            cardX = max(16.0, bounds.maxX - cardW - 20.0)
        }
        let barBottom = toolbar.toolbarRect(screenBounds: bounds).maxY
        let cardY = max(barBottom + 12.0, min(bounds.maxY - cardH - 20.0, targetRect.minY))
        let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        self.ocrCardRect = cardRect
        self.ocrCloseButtonRect = CGRect(x: cardRect.maxX - 32, y: cardRect.minY + 6, width: 26, height: 26)
        self.ocrCopyButtonRect = CGRect(x: cardRect.minX + 12, y: cardRect.maxY - 30, width: 96, height: 22)
        self.ocrDismissButtonRect = CGRect(x: cardRect.maxX - 100, y: cardRect.maxY - 30, width: 88, height: 22)

        context.saveGState()

        // Drop shadow
        context.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: NSColor(white: 0, alpha: 0.55).cgColor)

        // Card background
        let path = CGPath(roundedRect: cardRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor)
        context.fillPath()

        // Card border
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(path)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.20).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        // Header: Title
        let headerFont = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        let isSuccess = !text.contains("No text detected")
        let titleColor = isSuccess ? NSColor.systemGreen : NSColor.systemOrange
        let titleStr = isSuccess ? "✓ Text Copied to Clipboard" : "Notice"
        let titleAttr = NSAttributedString(string: titleStr, attributes: [
            .font: headerFont,
            .foregroundColor: titleColor
        ])
        titleAttr.draw(at: CGPoint(x: cardRect.minX + 14, y: cardRect.minY + 12))

        // Close button [✕]
        let closeFont = NSFont.systemFont(ofSize: 13, weight: .bold)
        let closeAttr = NSAttributedString(string: "✕", attributes: [
            .font: closeFont,
            .foregroundColor: NSColor(white: 0.7, alpha: 1.0)
        ])
        closeAttr.draw(at: CGPoint(x: cardRect.maxX - 24, y: cardRect.minY + 12))

        // Divider
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: cardRect.minX + 12, y: cardRect.minY + 36))
        context.addLine(to: CGPoint(x: cardRect.maxX - 12, y: cardRect.minY + 36))
        context.strokePath()

        // Text content
        let textFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let contentAttr = NSAttributedString(string: text, attributes: [
            .font: textFont,
            .foregroundColor: NSColor(white: 0.94, alpha: 1.0),
            .paragraphStyle: para
        ])
        let textBounds = CGRect(
            x: cardRect.minX + 14,
            y: cardRect.minY + 44,
            width: cardW - 28,
            height: cardH - 80
        )
        contentAttr.draw(in: textBounds)

        // Footer buttons: "Copy Again" button pill
        let copyPill = CGPath(roundedRect: self.ocrCopyButtonRect!, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(copyPill)
        context.setFillColor(NSColor(calibratedRed: 0.0, green: 0.5, blue: 1.0, alpha: 0.25).cgColor)
        context.fillPath()
        context.addPath(copyPill)
        context.setStrokeColor(NSColor.systemCyan.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        let btnFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let copyAgain = NSAttributedString(string: "Copy Again", attributes: [
            .font: btnFont,
            .foregroundColor: NSColor.systemCyan
        ])
        copyAgain.draw(at: CGPoint(x: cardRect.minX + 26, y: cardRect.maxY - 26))

        // Dismiss button pill
        let dismissPill = CGPath(roundedRect: self.ocrDismissButtonRect!, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(dismissPill)
        context.setFillColor(NSColor(calibratedWhite: 0.2, alpha: 0.5).cgColor)
        context.fillPath()
        context.addPath(dismissPill)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        let dismissBtn = NSAttributedString(string: "Dismiss (Esc)", attributes: [
            .font: btnFont,
            .foregroundColor: NSColor(white: 0.75, alpha: 1.0)
        ])
        dismissBtn.draw(at: CGPoint(x: cardRect.maxX - 92, y: cardRect.maxY - 26))

        context.restoreGState()
    }

    private func drawStatusToast(in context: CGContext, message: String, screenBounds: CGRect) {
        context.saveGState()

        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attr = NSAttributedString(string: message, attributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ])
        let strSize = attr.size()
        let toastW = strSize.width + 24.0
        let toastH: CGFloat = 30.0
        let toastX = screenBounds.midX - toastW / 2.0
        let barBottom = toolbar.toolbarRect(screenBounds: screenBounds).maxY
        let toastY = barBottom + 12.0

        let toastRect = CGRect(x: toastX, y: toastY, width: toastW, height: toastH)
        let path = CGPath(roundedRect: toastRect, cornerWidth: 8, cornerHeight: 8, transform: nil)

        context.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: NSColor(white: 0, alpha: 0.4).cgColor)
        context.addPath(path)
        context.setFillColor(NSColor(calibratedWhite: 0.14, alpha: 0.96).cgColor)
        context.fillPath()

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(path)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        attr.draw(at: CGPoint(x: toastRect.minX + 12, y: toastRect.midY - strSize.height / 2.0))

        context.restoreGState()
    }

    // MARK: - Mouse & Key Events

    public override func mouseMoved(with event: NSEvent) {
        currentMousePoint = self.convert(event.locationInWindow, from: nil)

        if phase == .select {
            // Check recents hover
            if recentsShelf.hotZoneRect(screenBounds: self.bounds).contains(currentMousePoint) {
                recentsShelf.fanProgress = min(1.0, recentsShelf.fanProgress + 0.25)
                recentsShelf.hoveredIndex = recentsShelf.itemIndex(at: currentMousePoint, screenBounds: self.bounds)
            } else {
                recentsShelf.fanProgress = max(0.0, recentsShelf.fanProgress - 0.25)
                recentsShelf.hoveredIndex = nil
            }

            if captureKind == .window {
                hoveredWindow = WindowDiscovery.windowAt(point: currentMousePoint, in: captureData.windows)
            }
        } else {
            // Edit phase
            toolbar.hoveredAction = toolbar.action(at: currentMousePoint, screenBounds: self.bounds)
            if let act = toolbar.hoveredAction,
               let item = toolbar.items.first(where: { $0.action == act }) {
                self.toolTip = item.shortcut.isEmpty ? item.tooltip : "\(item.tooltip) (\(item.shortcut))"
            } else {
                self.toolTip = nil
            }

            // If highlighter in snap mode, probe text band
            if tool == .highlighter && highlighterMode == .snap {
                let annPt = toAnnotationPoint(currentMousePoint)
                activeSnapLock = TextBandDetector.detectTextBand(
                    source: pristineSource,
                    sourcePoint: CGPoint(x: annPt.x * effectiveScale, y: annPt.y * effectiveScale),
                    scale: effectiveScale
                )
            }

            // 1. Check if hovering over any crop handle
            if let handleIdx = cropHandleIndex(at: currentMousePoint) {
                hoveredCropHandleIndex = handleIdx
                cursorForCropHandle(handleIdx).set()
            } else {
                hoveredCropHandleIndex = nil
                // 2. Update cursor based on hover over annotations
                if tool == .select || tool == .text {
                    let annPt = toAnnotationPoint(currentMousePoint)
                    if activeAnnotations.contains(where: { $0.bounds.insetBy(dx: -4, dy: -4).contains(annPt) }) {
                        NSCursor.openHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        dragStart = self.convert(event.locationInWindow, from: nil)
        currentMousePoint = dragStart

        if phase == .select {
            // Check recents shelf click
            if let recentIdx = recentsShelf.itemIndex(at: dragStart, screenBounds: self.bounds) {
                let item = recentsShelf.items[recentIdx]
                reopenRecent(item: item)
                return
            }

            // Check capture tabs click
            if let kind = captureTab(at: dragStart) {
                activateCaptureKind(kind)
                return
            }

            if captureKind == .window, let win = hoveredWindow {
                self.selection = win.rect
                commitSelection()
                return
            }

            selection = CGRect(origin: dragStart, size: .zero)
        } else {
            // Edit phase
            // Check toolbar click
            if let action = toolbar.action(at: dragStart, screenBounds: self.bounds) {
                handleToolbarAction(action)
                return
            }

            // Check OCR card click
            if let resultText = ocrTextResult, let card = ocrCardRect, card.contains(dragStart) {
                if (ocrCloseButtonRect?.contains(dragStart) == true) || (ocrDismissButtonRect?.contains(dragStart) == true) {
                    ocrTextResult = nil
                    ocrCardRect = nil
                    needsDisplay = true
                    return
                }
                if ocrCopyButtonRect?.contains(dragStart) == true {
                    _ = ScreenCaptureEngine.copyTextToClipboard(resultText)
                    ocrStatusMessage = "Copied text to clipboard!"
                    needsDisplay = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                        self?.ocrStatusMessage = nil
                        self?.needsDisplay = true
                    }
                    return
                }
                // Absorb click within OCR card
                return
            }

            // Commit active inline text field if clicking outside
            if activeInlineTextField != nil {
                commitActiveTextEditing()
            }

            // Check Crop Handle click
            if let handleIdx = cropHandleIndex(at: dragStart) {
                activeHandle = .cropHandle(handleIdx)
                cropDragStartMouse = dragStart
                let maxW = CGFloat(pristineSource.width) / effectiveScale
                let maxH = CGFloat(pristineSource.height) / effectiveScale
                initialSelectionBeforeCrop = selection.isEmpty ? CGRect(x: 0, y: 0, width: maxW, height: maxH) : selection
                initialAnnotationsBeforeCrop = activeAnnotations
                let imgRect = imageRectOnScreen()
                let canvas = currentCanvasRect()
                cropScaleFactor = max(1.0, canvas.width) / max(1.0, imgRect.width)
                cursorForCropHandle(handleIdx).set()
                needsDisplay = true
                return
            }

            let annPt = toAnnotationPoint(dragStart)

            // Double-click to edit existing text annotation
            if event.clickCount >= 2 {
                if let hitIdx = activeAnnotations.indices.reversed().first(where: { activeAnnotations[$0].kind == .text && activeAnnotations[$0].bounds.contains(annPt) }) {
                    beginTextEditing(for: activeAnnotations[hitIdx], index: hitIdx)
                    return
                }
            }

            if tool == .select {
                // Check if clicking existing annotation
                if let hitIdx = activeAnnotations.indices.reversed().first(where: { activeAnnotations[$0].bounds.insetBy(dx: -6, dy: -6).contains(annPt) }) {
                    if event.modifierFlags.contains(.shift) {
                        if selectedAnnotationIndices.contains(hitIdx) {
                            selectedAnnotationIndices.remove(hitIdx)
                        } else {
                            selectedAnnotationIndices.insert(hitIdx)
                        }
                    } else {
                        if !selectedAnnotationIndices.contains(hitIdx) {
                            selectedAnnotationIndices = [hitIdx]
                        }
                    }
                    isDraggingAnnotation = true
                    dragAnnotationStartMouse = annPt
                    dragAnnotationInitialStates = selectedAnnotationIndices.compactMap { idx in
                        idx < activeAnnotations.count ? (index: idx, annotation: activeAnnotations[idx]) : nil
                    }
                    NSCursor.closedHand.set()
                } else {
                    selectedAnnotationIndices.removeAll()
                    isDraggingAnnotation = false
                    dragAnnotationInitialStates.removeAll()
                }
            } else if tool == .eyedropper {
                sampleEyedropperColor(at: annPt)
            } else if tool == .ocr {
                // OCR region drag initialized
            } else if tool == .marker {
                addMarker(at: annPt)
            } else if tool == .text {
                // If user clicked on an existing text annotation, select & prepare to move it
                if let hitIdx = activeAnnotations.indices.reversed().first(where: { activeAnnotations[$0].kind == .text && activeAnnotations[$0].bounds.insetBy(dx: -6, dy: -6).contains(annPt) }) {
                    selectedAnnotationIndices = [hitIdx]
                    isDraggingAnnotation = true
                    dragAnnotationStartMouse = annPt
                    dragAnnotationInitialStates = [(index: hitIdx, annotation: activeAnnotations[hitIdx])]
                    NSCursor.closedHand.set()
                } else {
                    createNewTextAnnotation(at: annPt)
                }
            } else if tool == .freehand || tool == .highlighter {
                activeFreehandPoints = [annPt]
            }
        }
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isMouseDown else { return }
        currentMousePoint = self.convert(event.locationInWindow, from: nil)

        if phase == .select {
            let minX = min(dragStart.x, currentMousePoint.x)
            let minY = min(dragStart.y, currentMousePoint.y)
            let maxX = max(dragStart.x, currentMousePoint.x)
            let maxY = max(dragStart.y, currentMousePoint.y)
            selection = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            // Check if dragging a crop handle
            if case .cropHandle(let handleIdx) = activeHandle {
                handleCropDrag(handleIndex: handleIdx)
                cursorForCropHandle(handleIdx).set()
                needsDisplay = true
                return
            }

            let annPt = toAnnotationPoint(currentMousePoint)

            if isDraggingAnnotation {
                let dx = annPt.x - dragAnnotationStartMouse.x
                let dy = annPt.y - dragAnnotationStartMouse.y
                for item in dragAnnotationInitialStates {
                    guard item.index < activeAnnotations.count else { continue }
                    var updated = item.annotation
                    updated.start = CGPoint(x: item.annotation.start.x + dx, y: item.annotation.start.y + dy)
                    updated.end = CGPoint(x: item.annotation.end.x + dx, y: item.annotation.end.y + dy)
                    if !item.annotation.points.isEmpty {
                        updated.points = item.annotation.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                    }
                    activeAnnotations[item.index] = updated
                }
                NSCursor.closedHand.set()
                needsDisplay = true
                return
            }

            if tool == .cut {
                let startPt = toAnnotationPoint(dragStart)
                let dx = abs(annPt.x - startPt.x)
                let dy = abs(annPt.y - startPt.y)
                let orient: CutOrientation = dx > dy ? .vertical : .horizontal
                liveCutBand = (orientation: orient, start: orient == .horizontal ? min(startPt.y, annPt.y) : min(startPt.x, annPt.x), end: orient == .horizontal ? max(startPt.y, annPt.y) : max(startPt.x, annPt.x))
            } else if tool == .freehand || (tool == .highlighter && highlighterMode == .normal) {
                activeFreehandPoints.append(annPt)
            }
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard isMouseDown else { return }
        isMouseDown = false
        currentMousePoint = self.convert(event.locationInWindow, from: nil)

        if phase == .select {
            if selection.width > 4 && selection.height > 4 {
                lastDrawnRegion = selection
                commitSelection()
            }
        } else {
            // Edit phase commit drag
            if case .cropHandle = activeHandle {
                activeHandle = nil
                hoveredCropHandleIndex = nil
                opLog.previewWidth = Int(selection.width)
                opLog.previewHeight = Int(selection.height)
                if selection != initialSelectionBeforeCrop {
                    recordOp(Operation(type: .crop, crop: selection))
                }
                needsDisplay = true
                return
            }

            if isDraggingAnnotation {
                isDraggingAnnotation = false
                let endAnn = toAnnotationPoint(currentMousePoint)
                let dist = hypot(endAnn.x - dragAnnotationStartMouse.x, endAnn.y - dragAnnotationStartMouse.y)
                if dist >= 2.0 {
                    let moved = dragAnnotationInitialStates.compactMap { item in
                        item.index < activeAnnotations.count ? activeAnnotations[item.index] : nil
                    }
                    recordOp(Operation(type: .annotate, annotations: moved))
                }
                dragAnnotationInitialStates.removeAll()
                needsDisplay = true
                return
            }

            let startAnn = toAnnotationPoint(dragStart)
            let endAnn = toAnnotationPoint(currentMousePoint)
            let dragDist = hypot(endAnn.x - startAnn.x, endAnn.y - startAnn.y)
            let dragDim = max(abs(endAnn.x - startAnn.x), abs(endAnn.y - startAnn.y))

            if tool == .cut, let cut = liveCutBand {
                applyCut(cut)
                liveCutBand = nil
            } else if tool == .arrow {
                if dragDist >= 3.0 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .arrow,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize
                    ))
                }
            } else if tool == .line {
                if dragDist >= 3.0 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .line,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize
                    ))
                }
            } else if tool == .freehand {
                if activeFreehandPoints.count > 1 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .freehand,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize,
                        points: activeFreehandPoints
                    ))
                }
                activeFreehandPoints.removeAll()
            } else if tool == .highlighter {
                if activeFreehandPoints.count > 1 || dragDist >= 3.0 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .highlighter,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize,
                        points: activeFreehandPoints
                    ))
                }
                activeFreehandPoints.removeAll()
            } else if tool == .rectangle {
                if dragDim >= 3.0 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .rectangle,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize,
                        filled: shapeFilled,
                        cornerRadius: cornerRadius
                    ))
                }
            } else if tool == .ellipse {
                if dragDim >= 3.0 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .ellipse,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize,
                        filled: shapeFilled
                    ))
                }
            } else if tool == .redact {
                if dragDim >= 3.0 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .redaction,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize,
                        redactionStyle: redactionStyle,
                        redactionSeed: UInt32.random(in: 0..<UInt32.max)
                    ))
                }
            } else if tool == .spotlight {
                if dragDim >= 3.0 {
                    commitAnnotation(Annotation(
                        id: opLog.nextId,
                        kind: .spotlight,
                        start: startAnn,
                        end: endAnn,
                        colorHex: activeColorHex,
                        size: strokeSize,
                        magnification: spotlightZoom,
                        spotlightShape: spotlightShape
                    ))
                }
            } else if tool == .ocr {
                if dragDim >= 10.0 {
                    let minX = min(startAnn.x, endAnn.x)
                    let minY = min(startAnn.y, endAnn.y)
                    let w = abs(endAnn.x - startAnn.x)
                    let h = abs(endAnn.y - startAnn.y)
                    runOCR(region: CGRect(x: minX, y: minY, width: w, height: h))
                } else {
                    runOCR(region: nil)
                }
            }
        }
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isCmd = event.modifierFlags.contains(.command)
        let isShift = event.modifierFlags.contains(.shift)

        // Esc key
        if event.keyCode == 53 {
            if activeInlineTextField != nil {
                cancelActiveTextEditing()
                return
            }
            if ocrTextResult != nil {
                ocrTextResult = nil
                ocrCardRect = nil
                needsDisplay = true
                return
            }
            dismissCapture()
            return
        }

        // Enter key
        if event.keyCode == 36 {
            if phase == .select {
                if let win = hoveredWindow {
                    self.selection = win.rect
                    commitSelection()
                } else if !selection.isEmpty {
                    commitSelection()
                }
            } else {
                // Copy + Save
                finish(outputMode: .both)
            }
            return
        }

        // Space key: cycle tabs in select phase
        if event.keyCode == 49 && phase == .select {
            cycleTabs()
            return
        }

        // Key shortcuts
        if isCmd {
            switch key {
            case "z":
                if isShift { redo() } else { undo() }
            case "c":
                finish(outputMode: .copy)
            case "s":
                finish(outputMode: .save)
            case "d":
                duplicateSelectedAnnotation()
            case "a":
                if phase == .select {
                    selection = self.bounds
                    commitSelection()
                }
            default:
                super.keyDown(with: event)
            }
            return
        }

        // Tool shortcuts
        switch key {
        case "v": setTool(.select)
        case "a": setTool(.arrow)
        case "l": setTool(.line)
        case "f": setTool(.freehand)
        case "h":
            if tool == .highlighter {
                highlighterMode = (highlighterMode == .snap) ? .normal : .snap
            } else {
                setTool(.highlighter)
            }
        case "s":
            if phase == .select {
                captureKind = .scroll
                needsDisplay = true
            } else {
                if tool == .spotlight {
                    cycleSpotlightShape()
                } else {
                    setTool(.spotlight)
                }
            }
        case "c": setTool(.marker)
        case "r":
            if phase == .select && !lastDrawnRegion.isEmpty {
                selection = lastDrawnRegion
                commitSelection()
            } else {
                setTool(.rectangle)
            }
        case "e": setTool(.ellipse)
        case "d":
            if tool == .redact {
                redactionStyle = (redactionStyle == .pixelate) ? .solid : .pixelate
            } else {
                setTool(.redact)
            }
        case "x": setTool(.cut)
        case "t":
            if isShift {
                cycleTextFont()
            } else {
                setTool(.text)
            }
        case "o":
            setTool(.ocr)
            runOCR(region: nil)
        case "i": setTool(.eyedropper)
        case "b":
            if isShift {
                imageShadow.toggle()
                recordOp(Operation(type: .background, background: backdropStyle, imageShadow: imageShadow))
            } else {
                cycleBackground()
            }
        case "g":
            cycleCanvasBoundary(reverse: isShift)
        case "p":
            pinCapture()
        case "1", "2", "3", "4", "5", "6", "7", "8":
            if let idx = Int(key), idx >= 1, idx <= toolbar.paletteColors.count {
                activeColorHex = toolbar.paletteColors[idx - 1]
                toolbar.activeColorHex = activeColorHex
                needsDisplay = true
            }
        default:
            // Arrow nudge keys
            if event.keyCode >= 123 && event.keyCode <= 126 {
                nudgeSelected(keyCode: event.keyCode, shift: isShift)
            } else if event.keyCode == 51 || event.keyCode == 117 { // Backspace / Delete
                deleteSelected()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: - Phase Transitions & Actions

    private func commitSelection() {
        if quickOutputMode != .none {
            finish(outputMode: quickOutputMode)
            return
        }
        phase = .edit
        initialCaptureSelection = selection
        opLog.previewWidth = Int(selection.width)
        opLog.previewHeight = Int(selection.height)
        needsDisplay = true
    }

    private func captureTab(at point: CGPoint) -> CaptureKind? {
        let kinds = CaptureKind.allCases
        let tabH: CGFloat = 32.0
        let tabW: CGFloat = 110.0
        let totalW = tabW * CGFloat(kinds.count)
        let barRect = CGRect(x: self.bounds.midX - totalW / 2.0, y: 16, width: totalW, height: tabH)
        guard barRect.contains(point) else { return nil }

        let relX = point.x - barRect.minX
        let idx = Int(relX / tabW)
        if idx >= 0 && idx < kinds.count {
            return kinds[idx]
        }
        return nil
    }

    private func activateCaptureKind(_ kind: CaptureKind) {
        self.captureKind = kind
        if kind == .fullscreen {
            self.selection = self.bounds
            commitSelection()
        } else if kind == .window {
            hoveredWindow = WindowDiscovery.windowAt(point: currentMousePoint, in: captureData.windows)
        }
        needsDisplay = true
    }

    private func cycleTabs() {
        let all = CaptureKind.allCases
        if let idx = all.firstIndex(of: captureKind) {
            let next = all[(idx + 1) % all.count]
            activateCaptureKind(next)
        }
    }

    public func setTool(_ t: EditorTool) {
        self.tool = t
        switch t {
        case .select: toolbar.activeToolAction = "tool-select"
        case .arrow: toolbar.activeToolAction = "tool-arrow"
        case .line: toolbar.activeToolAction = "tool-line"
        case .freehand: toolbar.activeToolAction = "tool-freehand"
        case .highlighter: toolbar.activeToolAction = "tool-highlighter"
        case .spotlight: toolbar.activeToolAction = "tool-spotlight"
        case .marker: toolbar.activeToolAction = "tool-marker"
        case .rectangle: toolbar.activeToolAction = "tool-rectangle"
        case .ellipse: toolbar.activeToolAction = "tool-ellipse"
        case .redact: toolbar.activeToolAction = "tool-redact"
        case .cut: toolbar.activeToolAction = "tool-cut"
        case .text: toolbar.activeToolAction = "tool-text"
        case .ocr: toolbar.activeToolAction = "tool-ocr"
        case .eyedropper: toolbar.activeToolAction = "tool-eyedropper"
        }
        needsDisplay = true
    }

    private func handleToolbarAction(_ action: String) {
        if action == "action-undo" { undo() }
        else if action == "action-redo" { redo() }
        else if action == "style-backdrop" { cycleBackground() }
        else if action == "style-canvas" { cycleCanvasBoundary(reverse: false) }
        else if action == "action-discard" { dismissCapture() }
        else if action == "action-copy" { finish(outputMode: .copy) }
        else if action == "action-save" { finish(outputMode: .save) }
        else if action == "action-pin" { pinCapture() }
        else if action == "action-finish" { finish(outputMode: .both) }
        else if action.hasPrefix("color-") {
            if let idx = Int(action.dropFirst(6)), idx >= 1, idx <= toolbar.paletteColors.count {
                activeColorHex = toolbar.paletteColors[idx - 1]
                toolbar.activeColorHex = activeColorHex
                needsDisplay = true
            }
        } else {
            // Tools
            toolbar.activeToolAction = action
            switch action {
            case "tool-select": tool = .select
            case "tool-arrow": tool = .arrow
            case "tool-line": tool = .line
            case "tool-freehand": tool = .freehand
            case "tool-highlighter": tool = .highlighter
            case "tool-spotlight": tool = .spotlight
            case "tool-marker": tool = .marker
            case "tool-rectangle": tool = .rectangle
            case "tool-ellipse": tool = .ellipse
            case "tool-redact": tool = .redact
            case "tool-cut": tool = .cut
            case "tool-text": tool = .text
            case "tool-ocr":
                tool = .ocr
                runOCR(region: nil)
            case "tool-eyedropper": tool = .eyedropper
            default: break
            }
            needsDisplay = true
        }
    }

    // MARK: - Annotation & Operations

    public func commitAnnotation(_ annotation: Annotation) {
        opLog.nextId += 1
        activeAnnotations.append(annotation)
        recordOp(Operation(type: .annotate, annotations: [annotation]))
    }

    public func addMarker(at point: CGPoint) {
        let marker = Annotation(
            id: opLog.nextId,
            kind: .marker,
            start: point,
            end: point,
            colorHex: activeColorHex,
            size: strokeSize,
            number: nextMarker
        )
        nextMarker += 1
        opLog.nextMarker = nextMarker
        commitAnnotation(marker)
    }

    // MARK: - Text Editing & Creation

    public func createNewTextAnnotation(at point: CGPoint) {
        let textAnn = Annotation(
            id: opLog.nextId,
            kind: .text,
            start: point,
            end: CGPoint(x: point.x + 140, y: point.y + 36),
            text: "",
            colorHex: activeColorHex,
            size: strokeSize,
            textBackground: textBackground,
            textFont: textFont
        )
        commitAnnotation(textAnn)
        let idx = activeAnnotations.count - 1
        beginTextEditing(for: textAnn, index: idx)
    }

    public func beginTextEntry(at point: CGPoint) {
        createNewTextAnnotation(at: point)
    }

    public func beginTextEditing(for annotation: Annotation, index: Int) {
        if activeInlineTextField != nil && editingTextAnnotationIndex != index {
            commitActiveTextEditing()
        }

        let startScreen = toScreenPoint(annotation.start)
        let fontSize = max(14.0, annotation.size * 4.0)
        let font = FontManager.shared.font(for: annotation.textFont, size: fontSize)

        let initialWidth: CGFloat
        if !annotation.text.isEmpty {
            let attr = NSAttributedString(string: annotation.text, attributes: [.font: font])
            initialWidth = max(160.0, attr.size().width + 30.0)
        } else {
            initialWidth = 160.0
        }

        let tfFrame = NSRect(
            x: max(10, startScreen.x - 6),
            y: max(10, startScreen.y - 6),
            width: initialWidth,
            height: max(32.0, fontSize + 16.0)
        )
        let tf = NSTextField(frame: tfFrame)
        tf.isBordered = false
        tf.drawsBackground = false
        tf.backgroundColor = .clear
        tf.textColor = NSColor(hex: annotation.colorHex) ?? .white
        tf.font = font
        tf.stringValue = annotation.text
        tf.placeholderString = "Type label text..."
        tf.focusRingType = .none
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 4.0
        tf.layer?.borderWidth = 1.0
        tf.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
        tf.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.25).cgColor
        tf.delegate = self
        tf.target = self
        tf.action = #selector(onInlineTextFieldAction(_:))

        self.addSubview(tf)
        self.window?.makeFirstResponder(tf)
        if !annotation.text.isEmpty {
            tf.currentEditor()?.selectAll(nil)
        }

        self.activeInlineTextField = tf
        self.editingTextAnnotationIndex = index
        self.needsDisplay = true
    }

    @objc private func onInlineTextFieldAction(_ sender: Any?) {
        commitActiveTextEditing()
    }

    public func commitActiveTextEditing() {
        guard let tf = activeInlineTextField, let idx = editingTextAnnotationIndex else { return }

        let rawText = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if idx < activeAnnotations.count {
            if rawText.isEmpty {
                let removedId = activeAnnotations[idx].id
                activeAnnotations.remove(at: idx)
                recordOp(Operation(type: .delete, ids: [removedId]))
                selectedAnnotationIndices.removeAll()
            } else {
                var ann = activeAnnotations[idx]
                ann.text = rawText
                let fontSize = max(14.0, ann.size * 4.0)
                let font = FontManager.shared.font(for: ann.textFont, size: fontSize)
                let strSize = (rawText as NSString).size(withAttributes: [.font: font])
                ann.end = CGPoint(x: ann.start.x + strSize.width + 16, y: ann.start.y + strSize.height + 16)
                activeAnnotations[idx] = ann
                recordOp(Operation(type: .annotate, annotations: [ann]))
                selectedAnnotationIndices = [idx]
                setTool(.select)
            }
        }

        tf.removeFromSuperview()
        self.activeInlineTextField = nil
        self.editingTextAnnotationIndex = nil
        self.window?.makeFirstResponder(self)
        self.needsDisplay = true
    }

    public func cancelActiveTextEditing() {
        guard let tf = activeInlineTextField, let idx = editingTextAnnotationIndex else { return }
        if idx < activeAnnotations.count && activeAnnotations[idx].text.isEmpty {
            let removedId = activeAnnotations[idx].id
            activeAnnotations.remove(at: idx)
            recordOp(Operation(type: .delete, ids: [removedId]))
        }
        tf.removeFromSuperview()
        self.activeInlineTextField = nil
        self.editingTextAnnotationIndex = nil
        self.window?.makeFirstResponder(self)
        self.needsDisplay = true
    }

    // MARK: - NSTextFieldDelegate
    public func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveTextEditing()
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let tf = activeInlineTextField, let idx = editingTextAnnotationIndex, idx < activeAnnotations.count else { return }
        let ann = activeAnnotations[idx]
        let fontSize = max(14.0, ann.size * 4.0)
        let font = FontManager.shared.font(for: ann.textFont, size: fontSize)
        let strSize = (tf.stringValue as NSString).size(withAttributes: [.font: font])
        let neededWidth = max(160.0, strSize.width + 30.0)
        if neededWidth > tf.frame.width {
            var f = tf.frame
            f.size.width = min(neededWidth, self.bounds.width - f.origin.x - 20)
            tf.frame = f
        }
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitActiveTextEditing()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelActiveTextEditing()
            return true
        }
        return false
    }

    public func applyCut(_ cut: (orientation: CutOrientation, start: Double, end: Double)) {
        let op = CutOp(
            orientation: cut.orientation,
            sourceStart: Int(cut.start * effectiveScale),
            sourceEnd: Int(cut.end * effectiveScale),
            logicalStart: Int(cut.start),
            logicalEnd: Int(cut.end)
        )
        activeCuts.append(op)
        // Shift annotations
        for i in 0..<activeAnnotations.count {
            CutEngine.shiftAnnotation(&activeAnnotations[i], for: op)
        }
        recordOp(Operation(type: .cut, cut: op))
    }

    private func recordOp(_ op: Operation) {
        if opLog.index < opLog.ops.count {
            opLog.ops.removeSubrange(opLog.index..<opLog.ops.count)
        }
        opLog.ops.append(op)
        opLog.index = opLog.ops.count
    }

    public func undo() {
        guard opLog.index > 0 else { return }
        opLog.index -= 1
        replayState()
    }

    public func redo() {
        guard opLog.index < opLog.ops.count else { return }
        opLog.index += 1
        replayState()
    }

    private func replayState() {
        let state = opLog.replay()
        if state.crop != .zero {
            self.selection = state.crop
            self.activeCrop = state.crop
        } else if initialCaptureSelection != .zero {
            self.selection = initialCaptureSelection
            self.activeCrop = initialCaptureSelection
        }
        self.activeAnnotations = state.annotations
        self.activeCuts = state.cuts
        self.backdropStyle = state.backgroundStyle
        self.imageShadow = state.imageShadow
        self.canvasBoundaryMode = state.canvasBoundary
        self.nextMarker = state.nextMarker
        needsDisplay = true
    }

    public func cycleBackground() {
        let styles = BackdropStyle.allCases
        if let idx = styles.firstIndex(of: backdropStyle) {
            backdropStyle = styles[(idx + 1) % styles.count]
            recordOp(Operation(type: .background, background: backdropStyle, imageShadow: imageShadow))
            needsDisplay = true
        }
    }

    public func cycleCanvasBoundary(reverse: Bool) {
        let modes: [CanvasBoundaryMode] = [.framed, .overflow, .image]
        if let idx = modes.firstIndex(of: canvasBoundaryMode) {
            let nextIdx = reverse ? (idx - 1 + modes.count) % modes.count : (idx + 1) % modes.count
            canvasBoundaryMode = modes[nextIdx]
            recordOp(Operation(type: .canvasBoundary, canvasBoundary: canvasBoundaryMode))
            needsDisplay = true
        }
    }

    public func cycleSpotlightShape() {
        switch spotlightShape {
        case .ellipse: spotlightShape = .rectangle
        case .rectangle: spotlightShape = .rounded
        case .rounded: spotlightShape = .ellipse
        }
    }

    public func cycleTextFont() {
        switch textFont {
        case .system: textFont = .jetbrainsMono
        case .jetbrainsMono: textFont = .interDisplay
        case .interDisplay: textFont = .neucha
        case .neucha: textFont = .system
        }
    }

    private func duplicateSelectedAnnotation() {
        guard let idx = selectedAnnotationIndices.first, idx < activeAnnotations.count else { return }
        var copy = activeAnnotations[idx]
        copy.id = opLog.nextId
        copy.start.x += 16
        copy.start.y += 16
        copy.end.x += 16
        copy.end.y += 16
        commitAnnotation(copy)
        selectedAnnotationIndices = [activeAnnotations.count - 1]
    }

    private func deleteSelected() {
        guard !selectedAnnotationIndices.isEmpty else { return }
        let ids = selectedAnnotationIndices.compactMap { $0 < activeAnnotations.count ? activeAnnotations[$0].id : nil }
        activeAnnotations.removeAll { ids.contains($0.id) }
        selectedAnnotationIndices.removeAll()
        recordOp(Operation(type: .delete, ids: ids))
        needsDisplay = true
    }

    private func nudgeSelected(keyCode: UInt16, shift: Bool) {
        let step: CGFloat = shift ? 10.0 : 1.0
        var dx: CGFloat = 0.0
        var dy: CGFloat = 0.0
        if keyCode == 123 { dx = -step } // Left
        if keyCode == 124 { dx = step }  // Right
        if keyCode == 125 { dy = step }  // Down
        if keyCode == 126 { dy = -step } // Up

        for idx in selectedAnnotationIndices {
            guard idx < activeAnnotations.count else { continue }
            activeAnnotations[idx].start.x += dx
            activeAnnotations[idx].start.y += dy
            activeAnnotations[idx].end.x += dx
            activeAnnotations[idx].end.y += dy
        }
        needsDisplay = true
    }

    private func sampleEyedropperColor(at point: CGPoint) {
        let pxX = min(max(0, Int(point.x * effectiveScale)), pristineSource.width - 1)
        let pxY = min(max(0, Int(point.y * effectiveScale)), pristineSource.height - 1)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }

        context.draw(pristineSource, in: CGRect(x: -pxX, y: -(pristineSource.height - 1 - pxY), width: pristineSource.width, height: pristineSource.height))
        if let data = context.data {
            let ptr = data.bindMemory(to: UInt8.self, capacity: 4)
            let r = ptr[0]
            let g = ptr[1]
            let b = ptr[2]
            let hex = String(format: "#%02x%02x%02x", r, g, b)
            self.activeColorHex = hex
            self.toolbar.activeColorHex = hex
            setTool(.select)
        }
    }

    public func runOCR(region: CGRect? = nil) {
        guard let fullRendered = RenderPipeline.renderCapture(
            source: pristineSource,
            selection: selection.isEmpty ? CGRect(origin: .zero, size: pristineSourceSize()) : selection,
            annotations: activeAnnotations,
            scale: effectiveScale
        ) else { return }

        let imageToScan: CGImage
        if let r = region, r.width > 5 && r.height > 5 {
            let cropX = max(0, r.minX * effectiveScale)
            let cropY = max(0, r.minY * effectiveScale)
            let cropW = min(CGFloat(fullRendered.width) - cropX, r.width * effectiveScale)
            let cropH = min(CGFloat(fullRendered.height) - cropY, r.height * effectiveScale)
            let cropRect = CGRect(x: cropX, y: cropY, width: max(1, cropW), height: max(1, cropH))
            imageToScan = fullRendered.cropping(to: cropRect) ?? fullRendered
        } else {
            imageToScan = fullRendered
        }

        isScanningOCR = true
        ocrTextResult = nil
        ocrStatusMessage = nil
        needsDisplay = true

        Task {
            let (text, _) = await OCRService.recognizeText(from: imageToScan)
            await MainActor.run {
                self.isScanningOCR = false
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    _ = ScreenCaptureEngine.copyTextToClipboard(trimmed)
                    self.ocrTextResult = trimmed
                    self.ocrStatusMessage = "Copied text to clipboard!"
                } else {
                    self.ocrTextResult = "No text detected in selected area."
                    self.ocrStatusMessage = "No text detected"
                }
                self.needsDisplay = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.ocrStatusMessage = nil
                    self?.needsDisplay = true
                }
            }
        }
    }

    public func reopenRecent(item: RecentItem) {
        guard let img = ScreenCaptureEngine.loadImage(from: item.imageURL) else { return }
        self.pristineSource = img
        if let loadedLog = try? OperationLog.load(from: item.logURL) {
            self.opLog = loadedLog
            self.replayState()
        }
        self.selection = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        self.phase = .edit
        needsDisplay = true
    }

    // MARK: - Finish & Outputs

    public func finish(outputMode: QuickOutputMode) {
        guard let rendered = RenderPipeline.renderCapture(
            source: pristineSource,
            selection: selection.isEmpty ? CGRect(origin: .zero, size: pristineSourceSize()) : selection,
            annotations: activeAnnotations,
            backdropStyle: backdropStyle,
            imageShadow: imageShadow,
            boundaryMode: canvasBoundaryMode,
            scale: effectiveScale
        ) else {
            self.window?.close()
            NSApplication.shared.terminate(nil)
            return
        }

        // Dominant app slug for naming
        let appSlug = WindowDiscovery.dominantAppClass(in: captureData.windows, selection: selection)

        if outputMode == .copy || outputMode == .both {
            _ = ScreenCaptureEngine.copyImageToClipboard(rendered)
        }

        if outputMode == .save || outputMode == .both {
            let path = appConfig.generateFilename(appSlug: appSlug)
            let fileURL = URL(fileURLWithPath: path)
            _ = ScreenCaptureEngine.savePNG(image: rendered, to: fileURL)

            // Save sidecar op-log JSON
            let logURL = fileURL.appendingPathExtension("json")
            try? opLog.save(to: logURL)

            // Shelve to recents
            recentsShelf.saveToRecent(image: rendered, log: opLog)
        }

        self.window?.close()
        NSApplication.shared.terminate(nil)
    }

    public func dismissCapture() {
        self.window?.close()
        NSApplication.shared.terminate(nil)
    }

    public func pinCapture() {
        guard let rendered = RenderPipeline.renderCapture(
            source: pristineSource,
            selection: selection.isEmpty ? CGRect(origin: .zero, size: pristineSourceSize()) : selection,
            annotations: activeAnnotations,
            backdropStyle: backdropStyle,
            imageShadow: imageShadow,
            boundaryMode: canvasBoundaryMode,
            scale: effectiveScale
        ) else { return }

        // Save temporary pin file
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let pinName = "pin-\(getpid())-\(Int.random(in: 1000...9999))"
        let pinImgURL = tmpDir.appendingPathComponent("\(pinName).png")
        let pinLogURL = tmpDir.appendingPathComponent("\(pinName).png.json")

        _ = ScreenCaptureEngine.savePNG(image: rendered, to: pinImgURL)
        try? opLog.save(to: pinLogURL)

        self.window?.close()

        let pinWin = PinnedWindow(imageURL: pinImgURL, logURL: pinLogURL, image: rendered)
        pinWin.makeKeyAndOrderFront(self)
    }

    private func pristineSourceSize() -> CGSize {
        CGSize(width: pristineSource.width, height: pristineSource.height)
    }
}

public enum QuickOutputMode {
    case none
    case copy
    case save
    case both
}
