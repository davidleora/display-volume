import AppKit
import ApplicationServices

final class KeyTap {
    private let handler: (MediaKeyEvent, Bool) -> Bool
    private var port: CFMachPort?

    init(handler: @escaping (MediaKeyEvent, Bool) -> Bool) {
        self.handler = handler
    }

    var isRunning: Bool { port != nil }

    static func isAllowed(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary)
    }

    func start() -> Bool {
        guard port == nil else { return true }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue),
            callback: { _, type, event, refcon in
                let tap = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, let key = mediaKeyEvent(subtype: ns.subtype.rawValue, data1: ns.data1) else {
            return Unmanaged.passUnretained(event)
        }
        let fine = ns.modifierFlags.contains([.shift, .option])
        return handler(key, fine) ? nil : Unmanaged.passUnretained(event)
    }
}
