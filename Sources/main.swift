import AppKit
import CoreAudio
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let bridge = AudioBridge()
    private let hud = HUD()
    private lazy var keys = KeyTap { [unowned self] event, fine in self.handle(event, fine: fine) }
    private var statusItem: NSStatusItem!
    private var state = VolumeState(level: 0.5, muted: false)
    private var enabled = true
    private var deviceName = ""
    private var problem: String?
    private var keyRetry: Timer?

    private let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let sliderLabel = NSTextField(labelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if defaults.object(forKey: "level") != nil {
            state = VolumeState(level: defaults.double(forKey: "level"), muted: defaults.bool(forKey: "muted"))
        }
        if defaults.object(forKey: "enabled") != nil {
            enabled = defaults.bool(forKey: "enabled")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true

        AudioSystem.onDefaultOutputChange { [weak self] in self?.refresh() }
        startKeys(prompt: true)
        apply()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.stop()
    }

    private var isActive: Bool { bridge.isRunning }

    private func refresh() {
        problem = nil
        do {
            let device = try AudioSystem.defaultOutputDevice()
            deviceName = AudioSystem.name(of: device)
            if !enabled || AudioSystem.hasOwnVolume(device) {
                bridge.stop()
            } else if bridge.device != device || !bridge.isRunning {
                try bridge.start(device: device)
            }
        } catch {
            bridge.stop()
            problem = error.localizedDescription
            NSLog("Display Volume: %@", problem!)
        }
        updateIcon()
    }

    private func startKeys(prompt: Bool) {
        guard !keys.isRunning else { return }
        if KeyTap.isAllowed(prompt: prompt), keys.start() {
            keyRetry?.invalidate()
            keyRetry = nil
            return
        }
        guard keyRetry == nil else { return }
        keyRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.startKeys(prompt: false) }
    }

    private func handle(_ event: MediaKeyEvent, fine: Bool) -> Bool {
        guard isActive else { return false }
        if event.isDown {
            state.press(event.key, fine: fine)
            apply()
            hud.show(state)
        }
        return true
    }

    private func apply() {
        bridge.gain.target = state.gain
        defaults.set(state.level, forKey: "level")
        defaults.set(state.muted, forKey: "muted")
        slider.integerValue = state.percent
        sliderLabel.stringValue = state.muted ? "Muted" : "\(state.percent)%"
        updateIcon()
    }

    private func updateIcon() {
        let symbol = problem != nil ? "exclamationmark.triangle.fill" : isActive ? speakerSymbol(state) : "speaker.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Display Volume")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.appearsDisabled = !isActive && problem == nil
    }

    @objc private func sliderMoved() {
        state.set(percent: slider.integerValue)
        apply()
    }

    @objc private func toggleMute() {
        state.press(.mute, fine: false)
        apply()
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        refresh()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            problem = "Open at login: \(error.localizedDescription)"
            updateIcon()
        }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
    }

    @objc private func retry() {
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        if let problem {
            status = "Error: \(problem)"
        } else if !enabled {
            status = "Off: \(deviceName) plays at full volume"
        } else if isActive {
            status = "Controlling \(deviceName)"
        } else {
            status = "\(deviceName) uses the normal macOS volume"
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")

        if isActive {
            let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
            slider.frame = NSRect(x: 18, y: 4, width: 180, height: 20)
            sliderLabel.frame = NSRect(x: 204, y: 6, width: 50, height: 16)
            sliderLabel.alignment = .right
            sliderLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            row.addSubview(slider)
            row.addSubview(sliderLabel)
            let sliderItem = NSMenuItem()
            sliderItem.view = row
            menu.addItem(sliderItem)
            let mute = menu.addItem(withTitle: "Mute", action: #selector(toggleMute), keyEquivalent: "")
            mute.state = state.muted ? .on : .off
        }
        if problem != nil {
            menu.addItem(withTitle: "Try Again", action: #selector(retry), keyEquivalent: "")
        }

        menu.addItem(.separator())
        let on = menu.addItem(withTitle: "Control Displays Without Volume", action: #selector(toggleEnabled), keyEquivalent: "")
        on.state = enabled ? .on : .off
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if !keys.isRunning {
            menu.addItem(withTitle: "Allow Volume Keys (Accessibility)…", action: #selector(openAccessibility), keyEquivalent: "")
        }
        menu.addItem(withTitle: "No Sound? Allow System Audio Recording…", action: #selector(openPrivacy), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Display Volume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
