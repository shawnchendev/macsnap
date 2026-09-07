import Foundation
import CoreGraphics

public enum BackdropStyle: String, Codable, Sendable, CaseIterable {
    case none
    case off
    case slate
    case aurora
    case sunset
    case lagoon
    case violet
    case custom
}

public enum CanvasBoundaryMode: String, Codable, Sendable {
    case framed
    case overflow
    case image
}

public enum OperationType: String, Codable, Sendable {
    case crop
    case background
    case canvasBoundary = "canvas-boundary"
    case annotate
    case patch
    case delete
    case cut
}

public struct Operation: Equatable, Sendable {
    public var type: OperationType
    public var crop: CGRect = .zero
    public var background: BackdropStyle = .none
    public var imageShadow: Bool = true
    public var canvasBoundary: CanvasBoundaryMode = .framed
    public var annotations: [Annotation] = []
    public var ids: [UInt64] = []
    public var cut: CutOp = CutOp()

    public init(
        type: OperationType,
        crop: CGRect = .zero,
        background: BackdropStyle = .none,
        imageShadow: Bool = true,
        canvasBoundary: CanvasBoundaryMode = .framed,
        annotations: [Annotation] = [],
        ids: [UInt64] = [],
        cut: CutOp = CutOp()
    ) {
        self.type = type
        self.crop = crop
        self.background = background
        self.imageShadow = imageShadow
        self.canvasBoundary = canvasBoundary
        self.annotations = annotations
        self.ids = ids
        self.cut = cut
    }
}

extension Operation: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case rect
        case style
        case shadow
        case mode
        case annotation
        case annotations
        case ids
        case orientation
        case sourceStart
        case sourceEnd
        case logicalStart
        case logicalEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeStr = try container.decode(String.self, forKey: .type)
        guard let opType = OperationType(rawValue: typeStr) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown operation type: \(typeStr)")
        }
        self.type = opType

        switch opType {
        case .crop:
            let arr = (try? container.decode([Double].self, forKey: .rect)) ?? [0, 0, 0, 0]
            self.crop = CGRect(
                x: arr.count > 0 ? arr[0] : 0,
                y: arr.count > 1 ? arr[1] : 0,
                width: arr.count > 2 ? arr[2] : 0,
                height: arr.count > 3 ? arr[3] : 0
            )
        case .background:
            let styleStr = try? container.decode(String.self, forKey: .style)
            self.background = styleStr.flatMap { BackdropStyle(rawValue: $0) } ?? .none
            self.imageShadow = (try? container.decode(Bool.self, forKey: .shadow)) ?? true
        case .canvasBoundary:
            let modeStr = try? container.decode(String.self, forKey: .mode)
            self.canvasBoundary = modeStr.flatMap { CanvasBoundaryMode(rawValue: $0) } ?? .framed
        case .annotate:
            if let single = try? container.decode(Annotation.self, forKey: .annotation) {
                self.annotations = [single]
            }
        case .patch:
            self.annotations = (try? container.decode([Annotation].self, forKey: .annotations)) ?? []
        case .delete:
            if let stringIds = try? container.decode([String].self, forKey: .ids) {
                self.ids = stringIds.compactMap { UInt64($0) }
            } else if let uintIds = try? container.decode([UInt64].self, forKey: .ids) {
                self.ids = uintIds
            }
        case .cut:
            let orientStr = try? container.decode(String.self, forKey: .orientation)
            let orient: CutOrientation = (orientStr == "vertical") ? .vertical : .horizontal
            let sStart = (try? container.decode(Int.self, forKey: .sourceStart)) ?? 0
            let sEnd = (try? container.decode(Int.self, forKey: .sourceEnd)) ?? 0
            let lStart = (try? container.decode(Int.self, forKey: .logicalStart)) ?? 0
            let lEnd = (try? container.decode(Int.self, forKey: .logicalEnd)) ?? 0
            self.cut = CutOp(orientation: orient, sourceStart: sStart, sourceEnd: sEnd, logicalStart: lStart, logicalEnd: lEnd)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .type)

        switch type {
        case .crop:
            try container.encode([crop.origin.x, crop.origin.y, crop.size.width, crop.size.height], forKey: .rect)
        case .background:
            try container.encode(background.rawValue, forKey: .style)
            try container.encode(imageShadow, forKey: .shadow)
        case .canvasBoundary:
            try container.encode(canvasBoundary.rawValue, forKey: .mode)
        case .annotate:
            if let first = annotations.first {
                try container.encode(first, forKey: .annotation)
            }
        case .patch:
            try container.encode(annotations, forKey: .annotations)
        case .delete:
            try container.encode(ids.map { String($0) }, forKey: .ids)
        case .cut:
            try container.encode(cut.orientation == .vertical ? "vertical" : "horizontal", forKey: .orientation)
            try container.encode(cut.sourceStart, forKey: .sourceStart)
            try container.encode(cut.sourceEnd, forKey: .sourceEnd)
            try container.encode(cut.logicalStart, forKey: .logicalStart)
            try container.encode(cut.logicalEnd, forKey: .logicalEnd)
        }
    }
}
