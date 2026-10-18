import CoreAudio
import Foundation

struct AudioError: LocalizedError {
    let step: String
    let status: OSStatus

    var errorDescription: String? { "\(step) failed (\(status))" }
}

private func check(_ status: OSStatus, _ step: String) throws {
    guard status == noErr else { throw AudioError(step: step, status: status) }
}

private func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) throws -> T {
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    var where_ = address(selector, scope)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &where_, 0, nil, &size, $0) }
    try check(status, "Reading property \(selector)")
    return value
}

private func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var where_ = address(selector)
    try check(AudioObjectGetPropertyData(object, &where_, 0, nil, &size, &value), "Reading property \(selector)")
    guard let value else { throw AudioError(step: "Reading property \(selector)", status: kAudioHardwareUnspecifiedError) }
    return value.takeRetainedValue() as String
}

enum AudioSystem {
    static func defaultOutputDevice() throws -> AudioObjectID {
        try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown))
    }

    static func name(of device: AudioObjectID) -> String {
        (try? readString(device, kAudioObjectPropertyName)) ?? "Unknown device"
    }

    static func uid(of device: AudioObjectID) throws -> String {
        try readString(device, kAudioDevicePropertyDeviceUID)
    }

    static func hasOwnVolume(_ device: AudioObjectID) -> Bool {
        [kAudioObjectPropertyElementMain, 1, 2].contains { element in
            var where_ = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, element)
            var settable: DarwinBoolean = false
            return AudioObjectHasProperty(device, &where_) && AudioObjectIsPropertySettable(device, &where_, &settable) == noErr && settable.boolValue
        }
    }

    static func ownProcessObject() throws -> AudioObjectID {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var where_ = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object), "Finding this app's audio process")
        guard object != kAudioObjectUnknown else { throw AudioError(step: "Finding this app's audio process", status: kAudioHardwareBadObjectError) }
        return object
    }

    static func onDefaultOutputChange(_ handler: @escaping () -> Void) {
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &where_, .main) { _, _ in handler() }
    }

    static func isFloat32(_ device: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Bool {
        var where_ = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &where_, 0, nil, &size), "Listing streams")
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &streams), "Listing streams")
        return try streams.allSatisfy { stream in
            let format = try read(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
            return format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        }
    }
}

final class GainControl {
    var target: Float = 0
}

final class AudioBridge {
    private(set) var device = AudioObjectID(kAudioObjectUnknown)
    let gain = GainControl()
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?

    var isRunning: Bool { proc != nil }

    func start(device: AudioObjectID) throws {
        stop()
        do {
            try open(device: device)
        } catch {
            stop()
            throw error
        }
    }

    private func open(device: AudioObjectID) throws {
        let outputUID = try AudioSystem.uid(of: device)
        let description = CATapDescription(excludingProcesses: [try AudioSystem.ownProcessObject()], deviceUID: outputUID, stream: 0)
        description.uuid = UUID()
        description.name = "Display Volume"
        description.isPrivate = true
        description.muteBehavior = .muted
        try check(AudioHardwareCreateProcessTap(description, &tap), "Creating the audio tap")

        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Display Volume",
            kAudioAggregateDeviceUIDKey: "com.davidleora.display-volume.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "Creating the output device")
        guard try AudioSystem.isFloat32(aggregate, scope: kAudioObjectPropertyScopeInput), try AudioSystem.isFloat32(aggregate, scope: kAudioObjectPropertyScopeOutput) else {
            throw AudioError(step: "Checking the audio format (not 32-bit float)", status: kAudioDeviceUnsupportedFormatError)
        }

        let gain = self.gain
        var current = gain.target
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, output, _ in
            let target = gain.target
            copyWithGain(from: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)), to: UnsafeMutableAudioBufferListPointer(output), from: current, to: target)
            current = target
        }, "Creating the audio callback")
        try check(AudioDeviceStart(aggregate, proc), "Starting audio")
        self.device = device
    }

    func stop() {
        if let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
            self.proc = nil
        }
        if aggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = AudioObjectID(kAudioObjectUnknown)
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = AudioObjectID(kAudioObjectUnknown)
        }
        device = AudioObjectID(kAudioObjectUnknown)
    }
}
