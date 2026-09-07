import Foundation
import CoreText
import Cocoa

public final class FontManager: @unchecked Sendable {
    public static let shared = FontManager()
    private var registered = false

    private init() {
        registerBundledFonts()
    }

    public func registerBundledFonts() {
        guard !registered else { return }
        registered = true

        let fontNames = ["Neucha.ttf", "JetBrainsMono-Regular.ttf", "InterDisplay-SemiBold.ttf"]
        // Try locating in module bundle or app resources
        var urls: [URL] = []
        #if SWIFT_PACKAGE
        if let bundleURL = Bundle.module.resourceURL {
            for name in fontNames {
                let u = bundleURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: u.path) {
                    urls.append(u)
                }
            }
        }
        #endif

        if urls.isEmpty {
            // Check fallback asset directory relative to executable or home
            let assetPaths = [
                "/Users/shawnchen/github/macsnap/assets",
                "assets"
            ]
            for dir in assetPaths {
                for name in fontNames {
                    let u = URL(fileURLWithPath: "\(dir)/\(name)")
                    if FileManager.default.fileExists(atPath: u.path) {
                        urls.append(u)
                    }
                }
            }
        }

        for url in urls {
            if let dataProvider = CGDataProvider(url: url as CFURL),
               let font = CGFont(dataProvider) {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterGraphicsFont(font, &error)
            }
        }
    }

    public func font(for textFont: TextFont, size: CGFloat) -> NSFont {
        registerBundledFonts()
        switch textFont {
        case .neucha:
            if let f = NSFont(name: "Neucha", size: size) { return f }
            if let f = NSFont(name: "Caveat", size: size) { return f }
            return NSFont.systemFont(ofSize: size, weight: .regular)
        case .jetbrainsMono:
            if let f = NSFont(name: "JetBrainsMono-Regular", size: size) ?? NSFont(name: "JetBrains Mono", size: size) { return f }
            if let f = NSFont(name: "Menlo", size: size) { return f }
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .interDisplay:
            if let f = NSFont(name: "InterDisplay-SemiBold", size: size) ?? NSFont(name: "Inter Display", size: size) { return f }
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
    }
}
