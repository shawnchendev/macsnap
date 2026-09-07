import Foundation

public struct AppConfig: Sendable {
    public var outputDirectory: String
    public var filenamePattern: String
    public var palette: PaletteConfig
    public var backgroundImagePath: String?
    public var defaultBackdropStyle: BackdropStyle
    public var recentDirectory: String

    public init(
        outputDirectory: String = "~/Pictures/Screenshots",
        filenamePattern: String = "screenshot-{date}_{time}-{app}",
        palette: PaletteConfig = PaletteConfig(),
        backgroundImagePath: String? = nil,
        defaultBackdropStyle: BackdropStyle = .none,
        recentDirectory: String = "~/.local/state/macsnap/recent"
    ) {
        self.outputDirectory = outputDirectory
        self.filenamePattern = filenamePattern
        self.palette = palette
        self.backgroundImagePath = backgroundImagePath
        self.defaultBackdropStyle = defaultBackdropStyle
        self.recentDirectory = recentDirectory
    }

    public static func load() -> AppConfig {
        var config = AppConfig()

        // Locate config file
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path

        let possibleConfigPaths = [
            "\(home)/.config/macsnap/macsnap.conf",
            "\(home)/.config/omasnap/omasnap.conf",
            "\(home)/Library/Application Support/macsnap/macsnap.conf"
        ]

        for path in possibleConfigPaths {
            if fileManager.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                config.parseINI(content)
                break
            }
        }

        // Environment overrides
        if let envDir = ProcessInfo.processInfo.environment["MACSNAP_SCREENSHOT_DIR"] ??
                        ProcessInfo.processInfo.environment["OMASNAP_SCREENSHOT_DIR"],
           !envDir.isEmpty {
            config.outputDirectory = envDir
        }

        if let envRecent = ProcessInfo.processInfo.environment["MACSNAP_RECENT_DIR"] ??
                          ProcessInfo.processInfo.environment["OMASNAP_RECENT_DIR"],
           !envRecent.isEmpty {
            config.recentDirectory = envRecent
        }

        return config
    }

    private mutating func parseINI(_ content: String) {
        var currentSection = ""
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).lowercased()
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]

            switch currentSection {
            case "output":
                if key == "directory" {
                    outputDirectory = value
                } else if key == "filename" {
                    filenamePattern = value
                }
            case "colors":
                if key == "palette" {
                    let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    palette.colors = items
                } else if key == "custom" {
                    palette.customColor = value
                }
            case "background":
                if key == "image" {
                    backgroundImagePath = value
                } else if key == "default" {
                    if let style = BackdropStyle(rawValue: value.lowercased()) {
                        defaultBackdropStyle = style
                    }
                }
            default:
                break
            }
        }
    }

    public func resolvedOutputDirectory() -> URL {
        let expanded = NSString(string: outputDirectory).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func resolvedRecentDirectory() -> URL {
        let expanded = NSString(string: recentDirectory).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func generateFilename(appSlug: String? = nil, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)

        formatter.dateFormat = "HH-mm-ss"
        let timeStr = formatter.string(from: date)

        var name = filenamePattern
        name = name.replacingOccurrences(of: "{date}", with: dateStr)
        name = name.replacingOccurrences(of: "{time}", with: timeStr)

        let cleanApp = appSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleanApp.isEmpty {
            // Remove leading or trailing hyphen/underscore around {app}
            name = name.replacingOccurrences(of: "-{app}", with: "")
            name = name.replacingOccurrences(of: "_{app}", with: "")
            name = name.replacingOccurrences(of: "{app}-", with: "")
            name = name.replacingOccurrences(of: "{app}_", with: "")
            name = name.replacingOccurrences(of: "{app}", with: "")
        } else {
            name = name.replacingOccurrences(of: "{app}", with: cleanApp)
        }

        let dir = resolvedOutputDirectory()
        var targetURL = dir.appendingPathComponent("\(name).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: targetURL.path) {
            targetURL = dir.appendingPathComponent("\(name)-\(counter).png")
            counter += 1
        }
        return targetURL.path
    }

    public static func slugifyApp(_ name: String) -> String {
        let lower = name.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let cleaned = lower.unicodeScalars.filter { allowed.contains($0) }
        var result = String(cleaned)
        if result.count > 24 {
            result = String(result.prefix(24))
        }
        return result
    }
}
