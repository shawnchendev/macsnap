import Foundation
import CoreGraphics

public enum AnnotationKind: String, Codable, Sendable, CaseIterable {
    case arrow
    case line
    case freehand
    case highlighter
    case marker
    case rectangle
    case ellipse
    case text
    case redaction
    case spotlight
}

public enum RedactionStyle: String, Codable, Sendable {
    case solid
    case pixelate
}

public enum TextBackground: String, Codable, Sendable {
    case pill
    case outline
    case plain
}

public enum TextFont: String, Codable, Sendable {
    case system = "system"
    case neucha = "neucha"
    case jetbrainsMono = "jetbrains-mono"
    case interDisplay = "inter-display"

    public var displayName: String {
        switch self {
        case .system: return "System (San Francisco)"
        case .neucha: return "Neucha"
        case .jetbrainsMono: return "JetBrains Mono"
        case .interDisplay: return "Inter Display"
        }
    }
}

public enum SpotlightShape: String, Codable, Sendable {
    case ellipse
    case rectangle
    case rounded
}

public struct Annotation: Identifiable, Equatable, Sendable {
    public var id: UInt64
    public var kind: AnnotationKind
    public var start: CGPoint
    public var end: CGPoint
    public var text: String
    public var colorHex: String
    public var size: Double
    public var number: Int
    public var points: [CGPoint]
    public var filled: Bool
    public var cornerRadius: Double
    public var redactionStyle: RedactionStyle
    public var redactionSeed: UInt32
    public var magnification: Double
    public var spotlightShape: SpotlightShape
    public var textBackground: TextBackground
    public var textFont: TextFont

    public init(
        id: UInt64 = 0,
        kind: AnnotationKind = .arrow,
        start: CGPoint = .zero,
        end: CGPoint = .zero,
        text: String = "",
        colorHex: String = "#ff375f",
        size: Double = 4.0,
        number: Int = 0,
        points: [CGPoint] = [],
        filled: Bool = false,
        cornerRadius: Double = 0.0,
        redactionStyle: RedactionStyle = .pixelate,
        redactionSeed: UInt32 = 0,
        magnification: Double = 2.0,
        spotlightShape: SpotlightShape = .ellipse,
        textBackground: TextBackground = .plain,
        textFont: TextFont = .system
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.text = text
        self.colorHex = colorHex
        self.size = size
        self.number = number
        self.points = points
        self.filled = filled
        self.cornerRadius = cornerRadius
        self.redactionStyle = redactionStyle
        self.redactionSeed = redactionSeed
        self.magnification = magnification
        self.spotlightShape = spotlightShape
        self.textBackground = textBackground
        self.textFont = textFont
    }

    public var bounds: CGRect {
        switch kind {
        case .arrow, .line:
            let minX = min(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxX = max(start.x, end.x)
            let maxY = max(start.y, end.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .freehand, .highlighter:
            if points.isEmpty {
                return CGRect(origin: start, size: .zero)
            }
            var minX = points[0].x
            var minY = points[0].y
            var maxX = points[0].x
            var maxY = points[0].y
            for pt in points {
                minX = min(minX, pt.x)
                minY = min(minY, pt.y)
                maxX = max(maxX, pt.x)
                maxY = max(maxY, pt.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .marker:
            let radius = max(14.0, size * 3.5)
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
        case .rectangle, .ellipse, .redaction, .spotlight:
            let minX = min(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxX = max(start.x, end.x)
            let maxY = max(start.y, end.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text:
            let minX = min(start.x, end.x)
            let minY = min(start.y, end.y)
            let width = max(abs(end.x - start.x), 80.0)
            let height = max(abs(end.y - start.y), 32.0)
            return CGRect(x: minX, y: minY, width: width, height: height)
        }
    }
}

// MARK: - JSON Serialization
extension Annotation: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case tool
        case start
        case end
        case color
        case size
        case text
        case textFont
        case number
        case points
        case redactionStyle
        case seed
        case filled
        case cornerRadius
        case textBackground
        case magnification
        case spotlightShape
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let idString = try? container.decode(String.self, forKey: .id)
        let idVal = idString.flatMap { UInt64($0) } ?? (try? container.decode(UInt64.self, forKey: .id)) ?? 0

        let toolStr = try container.decode(String.self, forKey: .tool)
        let kind = AnnotationKind(rawValue: toolStr) ?? .arrow

        let startArr = (try? container.decode([Double].self, forKey: .start)) ?? [0, 0]
        let start = CGPoint(x: startArr.count > 0 ? startArr[0] : 0, y: startArr.count > 1 ? startArr[1] : 0)

        let endArr = (try? container.decode([Double].self, forKey: .end)) ?? [0, 0]
        let end = CGPoint(x: endArr.count > 0 ? endArr[0] : 0, y: endArr.count > 1 ? endArr[1] : 0)

        let color = (try? container.decode(String.self, forKey: .color)) ?? "#ff375f"
        let size = (try? container.decode(Double.self, forKey: .size)) ?? 4.0
        let text = (try? container.decode(String.self, forKey: .text)) ?? ""
        let textFont = (try? container.decode(TextFont.self, forKey: .textFont)) ?? .neucha
        let number = (try? container.decode(Int.self, forKey: .number)) ?? 0

        var points: [CGPoint] = []
        if let rawPoints = try? container.decode([[Double]].self, forKey: .points) {
            points = rawPoints.map { CGPoint(x: $0.count > 0 ? $0[0] : 0, y: $0.count > 1 ? $0[1] : 0) }
        }

        let redactionStyleStr = try? container.decode(String.self, forKey: .redactionStyle)
        let redactionStyle: RedactionStyle = (redactionStyleStr == "solid") ? .solid : .pixelate

        let seedStr = try? container.decode(String.self, forKey: .seed)
        let seed = seedStr.flatMap { UInt32($0) } ?? (try? container.decode(UInt32.self, forKey: .seed)) ?? 0

        let filled = (try? container.decode(Bool.self, forKey: .filled)) ?? false
        let cornerRadius = (try? container.decode(Double.self, forKey: .cornerRadius)) ?? 0.0

        let textBgStr = try? container.decode(String.self, forKey: .textBackground)
        let textBackground: TextBackground
        if textBgStr == "plain" { textBackground = .plain }
        else if textBgStr == "outline" { textBackground = .outline }
        else { textBackground = .pill }

        let magnification = (try? container.decode(Double.self, forKey: .magnification)) ?? 2.0
        let shapeStr = try? container.decode(String.self, forKey: .spotlightShape)
        let spotlightShape: SpotlightShape
        if shapeStr == "rectangle" { spotlightShape = .rectangle }
        else if shapeStr == "rounded" { spotlightShape = .rounded }
        else { spotlightShape = .ellipse }

        self.init(
            id: idVal,
            kind: kind,
            start: start,
            end: end,
            text: text,
            colorHex: color,
            size: size,
            number: number,
            points: points,
            filled: filled,
            cornerRadius: cornerRadius,
            redactionStyle: redactionStyle,
            redactionSeed: seed,
            magnification: magnification,
            spotlightShape: spotlightShape,
            textBackground: textBackground,
            textFont: textFont
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(id), forKey: .id)
        try container.encode(kind.rawValue, forKey: .tool)
        try container.encode([start.x, start.y], forKey: .start)
        try container.encode([end.x, end.y], forKey: .end)
        try container.encode(colorHex, forKey: .color)
        try container.encode(size, forKey: .size)

        if !text.isEmpty {
            try container.encode(text, forKey: .text)
        }
        if kind == .text {
            try container.encode(textFont.rawValue, forKey: .textFont)
        }
        if number > 0 {
            try container.encode(number, forKey: .number)
        }
        if !points.isEmpty {
            try container.encode(points.map { [$0.x, $0.y] }, forKey: .points)
        }
        if kind == .redaction {
            try container.encode(redactionStyle == .solid ? "solid" : "pixelate", forKey: .redactionStyle)
            try container.encode(String(redactionSeed), forKey: .seed)
        }
        if filled {
            try container.encode(true, forKey: .filled)
        }
        if cornerRadius > 0.0 {
            try container.encode(cornerRadius, forKey: .cornerRadius)
        }
        if textBackground == .plain {
            try container.encode("plain", forKey: .textBackground)
        } else if textBackground == .outline {
            try container.encode("outline", forKey: .textBackground)
        }
        if kind == .spotlight {
            try container.encode(magnification, forKey: .magnification)
            let shapeName = (spotlightShape == .rectangle ? "rectangle" : (spotlightShape == .rounded ? "rounded" : "ellipse"))
            try container.encode(shapeName, forKey: .spotlightShape)
        }
    }
}
