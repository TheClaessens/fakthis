@preconcurrency import AVFoundation
import Foundation

public actor MicrophoneTakeCapture: TakeCapture {
    private var engine: AVAudioEngine?
    private var samples: [Float] = []

    public init() {}

    public func begin() async {
        samples = []
        stopEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: hardware, to: target)
        else { return }
        self.engine = engine
        installTap(on: input, hardware: hardware, target: target, converter: converter)
        do {
            try engine.start()
        } catch {
            stopEngine()
        }
    }

    // AVFAudio calls the tap block on its own realtime thread. Written inline in an
    // actor-isolated method the block would inherit this actor's isolation, and the very
    // first buffer aborts the process on Swift's executor check, so it is installed from
    // nonisolated code and hands each chunk back over `append`.
    private nonisolated func installTap(
        on input: AVAudioInputNode,
        hardware: AVAudioFormat,
        target: AVAudioFormat,
        converter: AVAudioConverter
    ) {
        input.installTap(onBus: 0, bufferSize: 4096, format: hardware) { buffer, _ in
            let ratio = target.sampleRate / hardware.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
            else { return }
            var error: NSError?
            let first = FirstInput()
            converter.convert(to: converted, error: &error) { _, status in
                guard first.consume() else {
                    status.pointee = .noDataNow
                    return nil
                }
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = converted.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            Task { await self.append(chunk) }
        }
    }

    public func finish() async throws -> [Float] {
        stopEngine()
        let take = samples
        samples = []
        return take
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func append(_ chunk: [Float]) async {
        samples.append(contentsOf: chunk)
    }
}

private final class FirstInput: @unchecked Sendable {
    private var consumed = false

    func consume() -> Bool {
        if consumed { return false }
        consumed = true
        return true
    }
}
