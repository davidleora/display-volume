import CoreAudio

enum MediaKey: Equatable {
    case volumeUp, volumeDown, mute
}

struct MediaKeyEvent: Equatable {
    let key: MediaKey
    let isDown: Bool
}

func mediaKeyEvent(subtype: Int16, data1: Int) -> MediaKeyEvent? {
    guard subtype == 8 else { return nil }
    let key: MediaKey
    switch (data1 & 0xFFFF_0000) >> 16 {
    case 0: key = .volumeUp
    case 1: key = .volumeDown
    case 7: key = .mute
    default: return nil
    }
    return MediaKeyEvent(key: key, isDown: (data1 & 0xFF00) >> 8 == 0x0A)
}

struct VolumeState: Equatable {
    static let step = 1.0 / 16
    static let fineStep = 1.0 / 64

    var level: Double
    var muted: Bool

    var percent: Int { Int((level * 100).rounded()) }
    var gain: Float { muted ? 0 : Float(level * level) }

    mutating func press(_ key: MediaKey, fine: Bool) {
        let step = fine ? Self.fineStep : Self.step
        switch key {
        case .mute:
            muted.toggle()
        case .volumeUp:
            muted = false
            level = Self.snap(level + step, to: step)
        case .volumeDown:
            level = Self.snap(level - step, to: step)
        }
    }

    mutating func set(percent: Int) {
        level = Double(min(max(percent, 0), 100)) / 100
        muted = false
    }

    private static func snap(_ value: Double, to step: Double) -> Double {
        min(max((value / step).rounded() * step, 0), 1)
    }
}

func copyWithGain(from input: UnsafeMutableAudioBufferListPointer, to output: UnsafeMutableAudioBufferListPointer, from startGain: Float, to endGain: Float) {
    let inputChannels = input.reduce(0) { $0 + Int($1.mNumberChannels) }
    var outputChannel = 0
    for buffer in output {
        let channels = Int(buffer.mNumberChannels)
        guard channels > 0, let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let frames = Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size)
        let ramp = frames > 0 ? (endGain - startGain) / Float(frames) : 0
        for channel in 0..<channels {
            var copied = 0
            if inputChannels > 0, let source = locate(channel: (outputChannel + channel) % inputChannels, in: input) {
                copied = min(frames, source.frames)
                for frame in 0..<copied {
                    out[frame * channels + channel] = source.base[frame * source.stride] * (startGain + ramp * Float(frame))
                }
            }
            for frame in copied..<frames {
                out[frame * channels + channel] = 0
            }
        }
        outputChannel += channels
    }
}

private func locate(channel: Int, in list: UnsafeMutableAudioBufferListPointer) -> (base: UnsafeMutablePointer<Float>, stride: Int, frames: Int)? {
    var first = 0
    for buffer in list {
        let channels = Int(buffer.mNumberChannels)
        if channel < first + channels {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            return (data + (channel - first), channels, Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size))
        }
        first += channels
    }
    return nil
}
