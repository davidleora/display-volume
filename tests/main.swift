import CoreAudio
import Foundation

var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    guard !condition() else { return }
    failures += 1
    print("FAIL line \(line): \(message)")
}

func data1(code: Int, down: Bool, repeating: Bool = false) -> Int {
    (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (repeating ? 1 : 0)
}

expect(mediaKeyEvent(subtype: 8, data1: data1(code: 0, down: true)) == MediaKeyEvent(key: .volumeUp, isDown: true), "volume up down-event")
expect(mediaKeyEvent(subtype: 8, data1: data1(code: 1, down: false)) == MediaKeyEvent(key: .volumeDown, isDown: false), "volume down up-event")
expect(mediaKeyEvent(subtype: 8, data1: data1(code: 7, down: true, repeating: true)) == MediaKeyEvent(key: .mute, isDown: true), "mute repeat")
expect(mediaKeyEvent(subtype: 8, data1: data1(code: 16, down: true)) == nil, "play key is ignored")
expect(mediaKeyEvent(subtype: 7, data1: data1(code: 0, down: true)) == nil, "other subtype is ignored")

var state = VolumeState(level: 0.5, muted: false)
state.press(.volumeUp, fine: false)
expect(state.level == 0.5625 && state.percent == 56, "one step up is 1/16")
state.press(.volumeDown, fine: true)
expect(state.level == 0.546875, "fine step is 1/64")
state = VolumeState(level: 0.97, muted: false)
state.press(.volumeUp, fine: false)
expect(state.level == 1, "up stops at 100%")
state = VolumeState(level: 0.03, muted: false)
state.press(.volumeDown, fine: false)
expect(state.level == 0 && state.gain == 0, "down stops at 0% and is silent")
state = VolumeState(level: 0.5, muted: false)
state.press(.mute, fine: false)
expect(state.muted && state.gain == 0, "mute silences")
state.press(.volumeDown, fine: false)
expect(state.muted, "volume down keeps mute")
state.press(.volumeUp, fine: false)
expect(!state.muted && state.level == 0.5, "volume up unmutes")
expect(VolumeState(level: 0.5, muted: false).gain == 0.25, "gain is level squared")
state.set(percent: 140)
expect(state.level == 1, "slider percent is clamped")

func bufferList(_ buffers: [[Float]], channels: [Int]) -> UnsafeMutableAudioBufferListPointer {
    let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
    for (index, samples) in buffers.enumerated() {
        let memory = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        memory.initialize(from: samples, count: samples.count)
        list[index] = AudioBuffer(mNumberChannels: UInt32(channels[index]), mDataByteSize: UInt32(samples.count * 4), mData: memory)
    }
    return list
}

func samples(_ list: UnsafeMutableAudioBufferListPointer, _ index: Int) -> [Float] {
    let buffer = list[index]
    return Array(UnsafeBufferPointer(start: buffer.mData!.assumingMemoryBound(to: Float.self), count: Int(buffer.mDataByteSize) / 4))
}

let stereoIn = bufferList([[1, -1, 0.5, -0.5]], channels: [2])
let stereoOut = bufferList([[9, 9, 9, 9]], channels: [2])
copyWithGain(from: stereoIn, to: stereoOut, from: 0.5, to: 0.5)
expect(samples(stereoOut, 0) == [0.5, -0.5, 0.25, -0.25], "interleaved stereo copy with gain")

copyWithGain(from: stereoIn, to: stereoOut, from: 0, to: 1)
expect(samples(stereoOut, 0) == [0, 0, 0.25, -0.25], "gain ramps across the buffer")

let splitOut = bufferList([[9, 9], [9, 9]], channels: [1, 1])
copyWithGain(from: stereoIn, to: splitOut, from: 1, to: 1)
expect(samples(splitOut, 0) == [1, 0.5] && samples(splitOut, 1) == [-1, -0.5], "interleaved input to split output")

let monoIn = bufferList([[0.2, 0.4]], channels: [1])
copyWithGain(from: monoIn, to: stereoOut, from: 1, to: 1)
expect(samples(stereoOut, 0) == [0.2, 0.2, 0.4, 0.4], "mono input fills both channels")

let shortIn = bufferList([[1, 1]], channels: [2])
copyWithGain(from: shortIn, to: stereoOut, from: 1, to: 1)
expect(samples(stereoOut, 0) == [1, 1, 0, 0], "missing input frames become silence")

let emptyIn = bufferList([[]], channels: [0])
copyWithGain(from: emptyIn, to: stereoOut, from: 1, to: 1)
expect(samples(stereoOut, 0) == [0, 0, 0, 0], "no input gives silence")

if failures > 0 {
    print("\(failures) failed")
    exit(1)
}
print("all core tests passed")
