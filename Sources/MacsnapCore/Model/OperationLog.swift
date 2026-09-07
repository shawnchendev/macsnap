import Foundation
import CoreGraphics

public struct OperationLogState: Equatable, Sendable {
    public var crop: CGRect = .zero
    public var backgroundStyle: BackdropStyle = .none
    public var imageShadow: Bool = true
    public var canvasBoundary: CanvasBoundaryMode = .framed
    public var annotations: [Annotation] = []
    public var cuts: [CutOp] = []
    public var nextMarker: Int = 1

    public init() {}
}

public struct OperationLog: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var index: Int = 0
    public var nextId: UInt64 = 1
    public var nextMarker: Int = 1
    public var previewWidth: Int?
    public var previewHeight: Int?
    public var ops: [Operation] = []

    enum CodingKeys: String, CodingKey {
        case version
        case index
        case nextId
        case nextMarker
        case previewWidth
        case previewHeight
        case ops
    }

    public init(
        version: Int = 1,
        index: Int = 0,
        nextId: UInt64 = 1,
        nextMarker: Int = 1,
        previewWidth: Int? = nil,
        previewHeight: Int? = nil,
        ops: [Operation] = []
    ) {
        self.version = version
        self.index = index
        self.nextId = nextId
        self.nextMarker = nextMarker
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.ops = ops
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        self.index = (try? container.decode(Int.self, forKey: .index)) ?? 0

        if let stringId = try? container.decode(String.self, forKey: .nextId), let val = UInt64(stringId) {
            self.nextId = val
        } else if let uintVal = try? container.decode(UInt64.self, forKey: .nextId) {
            self.nextId = uintVal
        } else {
            self.nextId = 1
        }

        self.nextMarker = (try? container.decode(Int.self, forKey: .nextMarker)) ?? 1
        self.previewWidth = try? container.decode(Int.self, forKey: .previewWidth)
        self.previewHeight = try? container.decode(Int.self, forKey: .previewHeight)
        self.ops = (try? container.decode([Operation].self, forKey: .ops)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(index, forKey: .index)
        try container.encode(String(nextId), forKey: .nextId)
        try container.encode(nextMarker, forKey: .nextMarker)
        if let pw = previewWidth {
            try container.encode(pw, forKey: .previewWidth)
        }
        if let ph = previewHeight {
            try container.encode(ph, forKey: .previewHeight)
        }
        try container.encode(ops, forKey: .ops)
    }

    /// Reconstructs the visible state by replaying operations from 0 up to index.
    public func replay() -> OperationLogState {
        var state = OperationLogState()
        let count = min(index, ops.count)
        guard count > 0 else { return state }

        for i in 0..<count {
            let op = ops[i]
            switch op.type {
            case .crop:
                state.crop = op.crop
            case .background:
                state.backgroundStyle = op.background
                state.imageShadow = op.imageShadow
            case .canvasBoundary:
                state.canvasBoundary = op.canvasBoundary
            case .annotate:
                state.annotations.append(contentsOf: op.annotations)
                for ann in op.annotations where ann.kind == .marker {
                    state.nextMarker = max(state.nextMarker, ann.number + 1)
                }
            case .patch:
                for patched in op.annotations {
                    if let existingIdx = state.annotations.firstIndex(where: { $0.id == patched.id }) {
                        state.annotations[existingIdx] = patched
                    } else {
                        state.annotations.append(patched)
                    }
                }
            case .delete:
                let idSet = Set(op.ids)
                state.annotations.removeAll { idSet.contains($0.id) }
            case .cut:
                state.cuts.append(op.cut)
                for j in 0..<state.annotations.count {
                    CutEngine.shiftAnnotation(&state.annotations[j], for: op.cut)
                }
            }
        }
        return state
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> OperationLog {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(OperationLog.self, from: data)
    }
}
