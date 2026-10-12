//
//  BalancedEmitter.swift
//  FlowDown
//
//  Created by qaq on 9/12/2025.
//

import Foundation

actor BalancedEmitter {
    private var buffer: String = ""
    private var isRunning: Bool = false
    private var continuation: CheckedContinuation<Void, Never>?

    private let onEmit: @Sendable (String) -> Void
    private var duration: Double
    private var frequency: Int
    private var batchSize: Int = 1

    init(
        duration: Double = 1,
        frequency: Int = 30,
        onEmit: @escaping @Sendable (String) -> Void,
    ) {
        self.duration = duration
        self.frequency = frequency
        self.onEmit = onEmit
    }

    func update(duration: Double? = nil, frequency: Int? = nil) {
        if let duration, duration > 0 {
            self.duration = duration
        }
        if let frequency, frequency > 0 {
            self.frequency = frequency
        }
        batchSize = max(1, Int(ceil(Double(buffer.count) / Double(self.frequency))))
    }

    func add(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        buffer += chunk
        batchSize = max(1, Int(ceil(Double(buffer.count) / Double(frequency))))
        dispatchLoopIfRequired()
    }

    func wait() async {
        if buffer.isEmpty, !isRunning { return }
        await withCheckedContinuation { cont in
            // resolve any previous waiter before installing a new one
            clean()
            dispatchLoopIfRequired()

            // if the emitter has already drained by the time we get here,
            // resume immediately to avoid stalling the caller
            if buffer.isEmpty, !isRunning {
                cont.resume()
            } else {
                continuation = cont
            }
        }
    }

    private func dispatchLoopIfRequired() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            let stepDelay = (duration * 1000) / Double(frequency)
            while !buffer.isEmpty {
                let len = min(batchSize, buffer.count)
                let emitText = String(buffer.prefix(len))
                buffer.removeFirst(emitText.count)
                onEmit(emitText)
                await MainActor.run { SoundEffectPlayer.shared.play() }
                if buffer.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(Int(stepDelay)))
            }
            isRunning = false
            clean()
        }
    }

    @inline(__always)
    private func clean() {
        continuation?.resume()
        continuation = nil
    }

    func cancel() {
        buffer = ""
        clean()
    }
}
