import AVFoundation
import Foundation

final class ToneGenerator {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 44100.0

    // Frequency: smooth interpolation to avoid clicks
    private var targetFrequency: Double = 220.0
    private var smoothFrequency: Double = 220.0

    // Envelope
    private var envelope: Float = 0.0
    private var noteIsOn: Bool = false
    private var noteOnTime: Double = 0.0
    private var noteOffTime: Double = 0.0
    private var volume: Float = 0.45

    // Synthesis
    private var phases = [Double](repeating: 0.0, count: 8)
    private var vibratoPhase: Double = 0.0
    private var sampleTime: Double = 0.0

    // DC blocker state
    private var dcX: Double = 0.0
    private var dcY: Double = 0.0

    init() {
        setupAudio()
    }

    private func setupAudio() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)

            for i in 0..<Int(frameCount) {
                frames[i] = self.renderSample()
            }
            return noErr
        }

        guard let sourceNode = sourceNode else { return }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        do { try engine.start() }
        catch { print("Audio engine failed: \(error)") }
    }

    private func renderSample() -> Float {
        sampleTime += 1.0 / sampleRate

        // Smooth frequency (~3ms glide)
        smoothFrequency += (targetFrequency - smoothFrequency) * (150.0 / sampleRate)

        // Envelope
        updateEnvelope()
        guard envelope > 0.0005 else { return 0.0 }

        let timeSinceOn = max(0, sampleTime - noteOnTime)

        // Vibrato: gentle, delayed
        var vibrato = 0.0
        if timeSinceOn > 0.3 {
            let amount = min((timeSinceOn - 0.3) / 0.5, 1.0)
            vibratoPhase += 5.0 / sampleRate
            if vibratoPhase > 1.0 { vibratoPhase -= 1.0 }
            vibrato = sin(vibratoPhase * 2.0 * .pi) * 0.003 * amount
        }

        let freq = smoothFrequency * (1.0 + vibrato)

        // Additive synthesis: 8 harmonics (conservative)
        var sample = 0.0
        for n in 0..<8 {
            let h = Double(n + 1)
            // Steeper rolloff = mellower sound
            let amp = 1.0 / pow(h, 1.2)

            // Staggered onset during attack
            var hEnv = 1.0
            if timeSinceOn < 0.08 {
                let delay = Double(n) * 0.008
                let t = max(0, timeSinceOn - delay)
                hEnv = min(1.0, t / 0.04)
                hEnv = 0.5 * (1.0 - cos(hEnv * .pi))
            }

            phases[n] += h * freq / sampleRate
            // Safe phase wrapping
            if phases[n] > 1000.0 { phases[n] = phases[n].truncatingRemainder(dividingBy: 1.0) }

            sample += sin(phases[n] * 2.0 * .pi) * amp * hEnv
        }

        // Normalize: sum of 1/h^1.2 for h=1..8 ≈ 2.15, so peak ≈ 2.15
        sample *= 0.18

        // DC blocker (removes any offset buildup)
        let dcOut = sample - dcX + 0.997 * dcY
        dcX = sample
        dcY = dcOut
        sample = dcOut

        // Hard clamp for safety
        sample = max(-0.9, min(0.9, sample))

        return Float(sample) * envelope * volume
    }

    private func updateEnvelope() {
        if noteIsOn {
            let t = max(0, sampleTime - noteOnTime)
            if t < 0.05 {
                // Attack: 50ms cosine-smoothed
                let linear = Float(t / 0.05)
                envelope = 0.5 * (1.0 - cos(Float.pi * linear))
            } else {
                // Sustain: approach 1.0 gently
                envelope += (1.0 - envelope) * 0.001
                envelope = min(envelope, 1.0)
            }
        } else {
            // Release: exponential decay ~40ms
            let t = max(0, sampleTime - noteOffTime)
            envelope = min(envelope, Float(exp(-t / 0.04)))
            if envelope < 0.0005 { envelope = 0.0 }
        }
    }

    // MARK: - Public API

    func setFrequency(_ hz: Double) {
        guard hz.isFinite else { return }
        targetFrequency = max(60.0, min(hz, 2000.0))
    }

    func noteOn() {
        noteOnTime = sampleTime
        noteIsOn = true
        vibratoPhase = 0.0
    }

    func noteOff() {
        noteOffTime = sampleTime
        noteIsOn = false
    }

    func setVolume(_ v: Float) {
        volume = max(0.0, min(v, 1.0))
    }

    func stop() {
        noteIsOn = false
        envelope = 0.0
        engine.stop()
    }
}
