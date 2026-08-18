import AppKit

enum HUDStyle: Equatable {
    case success
    case informational
    case error

    var tintColor: NSColor {
        switch self {
        case .success:
            .systemGreen
        case .informational:
            .controlAccentColor
        case .error:
            .systemRed
        }
    }

    var displayDuration: TimeInterval {
        self == .error ? 4.0 : 2.2
    }

    func displayDuration(voiceOverEnabled: Bool) -> TimeInterval {
        voiceOverEnabled ? max(displayDuration, 8.0) : displayDuration
    }
}

@MainActor
enum HUDLayout {
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 480
    static let horizontalContentWidth: CGFloat = 80
    static let minimumHeight: CGFloat = 64
    static let maximumLines = 3

    static func panelSize(for message: String) -> NSSize {
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let naturalWidth = ceil((message as NSString).size(withAttributes: attributes).width)
        let width = min(
            maximumWidth,
            max(minimumWidth, naturalWidth + horizontalContentWidth)
        )
        let textWidth = width - horizontalContentWidth
        let measuredText = (message as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textHeight = min(ceil(measuredText.height), lineHeight * CGFloat(maximumLines))
        return NSSize(width: width, height: max(minimumHeight, textHeight + 32))
    }

    static func panelOrigin(panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let bottomInset = min(160, max(96, visibleFrame.height * 0.16))
        return NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.minY + bottomInset
        )
    }
}

@MainActor
final class HUDController {
    typealias AnnouncementHandler = (String, NSAccessibilityPriorityLevel) -> Void

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private let isVoiceOverEnabled: () -> Bool
    private let announce: AnnouncementHandler

    init(
        isVoiceOverEnabled: @escaping () -> Bool = {
            NSWorkspace.shared.isVoiceOverEnabled
        },
        announce: @escaping AnnouncementHandler = { _, _ in }
    ) {
        self.isVoiceOverEnabled = isVoiceOverEnabled
        self.announce = announce
    }

    func show(
        _ message: String,
        symbol: String,
        style: HUDStyle = .success,
        announces: Bool = true,
        accessibilityAnnouncement: String? = nil
    ) {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let announcement = accessibilityAnnouncement ?? message
        let priority: NSAccessibilityPriorityLevel = style == .error ? .high : .medium
        let voiceOverEnabled = isVoiceOverEnabled()
        // VoiceOver ignores explicit announcements from an inactive menu-bar
        // app unless they are backed by visible UI. Let it read the HUD itself,
        // using a single uninterrupted sentence and enough time to finish.
        let displayedMessage = voiceOverEnabled ? announcement : message
        // Callers that suppress this HUD's announcement provide their own
        // accessible status update. Do not expose a second transient window.
        if voiceOverEnabled && !announces {
            return
        }

        let panelSize = HUDLayout.panelSize(for: displayedMessage)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.setAccessibilityHidden(!voiceOverEnabled)

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.setAccessibilityHidden(!voiceOverEnabled)

        let icon = NSImageView(image: NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = style.tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityHidden(true)

        let label = NSTextField(labelWithString: displayedMessage)
        label.textColor = .labelColor
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = HUDLayout.maximumLines
        label.cell?.usesSingleLineMode = false
        label.cell?.wraps = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityHidden(!voiceOverEnabled)

        effect.addSubview(icon)
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
        panel.contentView = effect

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(HUDLayout.panelOrigin(
                panelSize: panelSize,
                visibleFrame: frame
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        if announces && !voiceOverEnabled {
            announce(announcement, priority)
        }

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + style.displayDuration(voiceOverEnabled: voiceOverEnabled),
            execute: workItem
        )
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
    }

#if DEBUG
    var visualPanelIsHiddenFromAccessibilityForTesting: Bool {
        guard let panel else { return false }
        return panel.isAccessibilityHidden()
            && panel.contentView?.isAccessibilityHidden() == true
    }

    var hasVisualPanelForTesting: Bool {
        panel != nil
    }

    var visualMessageForTesting: String? {
        guard let effect = panel?.contentView else { return nil }
        return effect.subviews
            .compactMap { $0 as? NSTextField }
            .first?
            .stringValue
    }
#endif
}
