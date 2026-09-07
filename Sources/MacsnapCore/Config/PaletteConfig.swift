import Foundation

public struct PaletteConfig: Equatable, Sendable {
    public var colors: [String]
    public var customColor: String

    public static let defaultColors = [
        "#ff375f", // Pink / Red
        "#ff9f0a", // Orange
        "#ffd60a", // Yellow
        "#30d158", // Green
        "#0a84ff", // Blue
        "#bf5af2", // Purple
        "#000000", // Black
        "#ffffff"  // White
    ]

    public init(colors: [String] = defaultColors, customColor: String = "#ff375f") {
        self.colors = colors.isEmpty ? Self.defaultColors : colors
        self.customColor = customColor
    }
}
