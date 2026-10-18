import AppKit

func speakerSymbol(_ state: VolumeState) -> String {
    if state.muted || state.level == 0 { return "speaker.slash.fill" }
    if state.level < 0.34 { return "speaker.wave.1.fill" }
    if state.level < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}

final class LevelBar: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard value > 0 else { return }
        var fill = bounds
        fill.size.width = max(bounds.height, bounds.width * value)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}

final class HUD {
    private let panel: NSPanel
    private let icon = NSImageView()
    private let bar = LevelBar()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        panel.contentView = background

        icon.frame = NSRect(x: 16, y: 16, width: 24, height: 24)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .medium)
        bar.frame = NSRect(x: 52, y: 24, width: 180, height: 8)
        label.frame = NSRect(x: 240, y: 18, width: 48, height: 20)
        label.alignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        [icon, bar, label].forEach(background.addSubview)
    }

    func show(_ state: VolumeState) {
        icon.image = NSImage(systemSymbolName: speakerSymbol(state), accessibilityDescription: "Volume")
        bar.value = state.muted ? 0 : state.level
        label.stringValue = state.muted ? "Muted" : "\(state.percent)%"
        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.maxY - size.height - 12))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }, completionHandler: { if panel.alphaValue == 0 { panel.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
