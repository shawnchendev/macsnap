import Foundation
import CoreGraphics
import Cocoa

/// Floating control panel shown while a scroll capture runs.
///
/// The main overlay is hidden during capture (so the page underneath stays
/// scrollable and the overlay never appears in its own screenshots, mirroring
/// omasnap's input-hole approach). This small panel is the only chrome, and it
/// is always placed fully outside the capture region so it is never stitched
/// into the result. During capture the keyboard belongs to the page, so — as
/// in omasnap — the on-screen buttons are the controls; no keys are promised.
public final class ScrollHUDPanel: NSPanel {
    public var onDone: (() -> Void)?
    public var onBack: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onContinue: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let doneButton = NSButton(title: "Done · stitch", target: nil, action: nil)
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let continueButton = NSButton(title: "Continue", target: nil, action: nil)

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 118),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        self.title = "Scrolling capture"
        self.isMovable = false
        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.becomesKeyOnlyIfNeeded = false

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor

        for b in [doneButton, backButton, cancelButton, continueButton] {
            b.bezelStyle = .rounded
            b.setButtonType(.momentaryPushIn)
            b.target = self
        }
        doneButton.action = #selector(didTapDone(_:))
        doneButton.keyEquivalent = "\r"
        backButton.action = #selector(didTapBack(_:))
        cancelButton.action = #selector(didTapCancel(_:))
        continueButton.action = #selector(didTapContinue(_:))
        continueButton.isHidden = true

        let buttons = NSStackView(views: [doneButton, backButton, cancelButton, continueButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let stack = NSStackView(views: [statusLabel, detailLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let content = self.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.topAnchor.constraint(equalTo: content.topAnchor),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
    }

    @objc private func didTapDone(_ sender: Any?) { onDone?() }
    @objc private func didTapBack(_ sender: Any?) { onBack?() }
    @objc private func didTapCancel(_ sender: Any?) { onCancel?() }
    @objc private func didTapContinue(_ sender: Any?) { onContinue?() }

    /// Main-thread status update.
    public func setStatus(_ text: String, detail: String = "", warning: Bool = false) {
        statusLabel.stringValue = text
        detailLabel.stringValue = detail
        statusLabel.textColor = warning ? .systemOrange : .labelColor
    }

    /// Shows the Continue button when an auto capture stalls short of the end.
    public func setStalled(_ stalled: Bool) {
        continueButton.isHidden = !stalled
    }

    public func setBusy(_ busy: Bool) {
        // Disable Done while stitching so double-clicks can't re-enter finish.
        doneButton.isEnabled = !busy
        backButton.isEnabled = !busy
        cancelButton.isEnabled = !busy
        continueButton.isEnabled = !busy
    }

    /// Frame for the panel in Cocoa screen coords: just below the capture
    /// region, above it when there is no room, never overlapping it, clamped
    /// to the screen. Mirrors omasnap's `scrollOverlayPillRect`.
    public static func frameOutside(regionCocoa: CGRect, screenCocoa: CGRect, panelSize: CGSize) -> CGRect {
        var x = regionCocoa.midX - panelSize.width / 2.0
        x = min(max(x, screenCocoa.minX + 12), max(screenCocoa.minX + 12, screenCocoa.maxX - panelSize.width - 12))
        var y = regionCocoa.minY - panelSize.height - 18 // below region (Cocoa y-down is minY)
        if y < screenCocoa.minY + 12 {
            y = regionCocoa.maxY + 18 // above region
        }
        if y + panelSize.height > screenCocoa.maxY - 12 {
            y = max(screenCocoa.minY + 12, screenCocoa.maxY - panelSize.height - 12)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }
}
