@preconcurrency import ScreenCaptureKit
import Foundation
import CoreMedia
import CoreGraphics
import QuartzCore

nonisolated final class SystemAudioHapticsEngine: NSObject, SCStreamOutput, SCStreamDelegate, SystemAudioHapticsEngining {
    private let captureQueue = DispatchQueue(label: "Ds5plus.audio.capture.queue")
    private let stateLock = NSLock()
    private let semanticAnalyzer = AudioSemanticRealtimeAnalyzer()
    private var stream: SCStream?
    private var isCapturing = false
    private var didLogSemanticAnalyzerAvailability = false
    private var smoothedRMS: Float = 0
    private var smoothedPeak: Float = 0
    private var smoothedLow: Float = 0
    private var smoothedMid: Float = 0
    private var smoothedTransient: Float = 0
    private var smoothedAttack: Float = 0
    private var smoothedEffect: Float = 0
    private var smoothedMovementPulse: Float = 0
    private var smoothedMusic: Float = 0
    private var smoothedBackground: Float = 0
    private var slowRMS: Float = 0
    private var slowLow: Float = 0
    private var slowMid: Float = 0
    private var slowHigh: Float = 0
    private var slowPeak: Float = 0
    private var previousMonoSample: Float = 0
    private var previousLowBandSample: Float = 0
    private var lowPassState: Float = 0
    private var midPassState: Float = 0
    private var processedFrames = 0
    private var lastPublishTime = CACurrentMediaTime()

    var onLog: @Sendable (String) -> Void = { _ in }
    var onSample: @Sendable (AudioReactiveSample) -> Void = { _ in }
    var onCaptureStateChanged: @Sendable (Bool, String?) -> Void = { _, _ in }

    func refreshDisplays() async throws -> [CaptureDisplay] {
        let content = try await shareableContent()
        return content.displays.map { CaptureDisplay(id: $0.displayID, width: $0.width, height: $0.height) }
    }

    func start(displayID: CGDirectDisplayID) async throws {
        stop()

        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw AudioReactiveError.displayNotFound
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        configuration.queueDepth = 1
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.showsCursor = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
        installCurrentStream(stream)

        smoothedRMS = 0
        smoothedPeak = 0
        smoothedLow = 0
        smoothedMid = 0
        smoothedTransient = 0
        smoothedAttack = 0
        smoothedEffect = 0
        smoothedMovementPulse = 0
        smoothedMusic = 0
        smoothedBackground = 0
        slowRMS = 0
        slowLow = 0
        slowMid = 0
        slowHigh = 0
        slowPeak = 0
        previousMonoSample = 0
        previousLowBandSample = 0
        lowPassState = 0
        midPassState = 0
        processedFrames = 0
        lastPublishTime = CACurrentMediaTime()
        semanticAnalyzer.reset()

        if !didLogSemanticAnalyzerAvailability {
            if semanticAnalyzer.isAvailable {
                onLog("已启用语义音频模型，将使用模型增强音乐/冲击/移动识别。")
            } else {
                onLog("未找到语义音频模型资源，继续使用规则音频识别。")
            }
            didLogSemanticAnalyzerAvailability = true
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        guard beginCaptureIfCurrent(stream) else {
            Task {
                try? await stream.stopCapture()
            }
            throw CancellationError()
        }

        onCaptureStateChanged(true, nil)
        onLog("系统音频捕获已启动。若第一次使用，请确认系统已授予屏幕录制权限。")
    }

    func stop() {
        let streamToStop: SCStream?
        let wasCapturing: Bool

        stateLock.lock()
        streamToStop = stream
        stream = nil
        wasCapturing = isCapturing
        isCapturing = false
        stateLock.unlock()

        if let streamToStop {
            streamToStop.stopCapture { _ in }
        }
        semanticAnalyzer.reset()
        if wasCapturing {
            onCaptureStateChanged(false, nil)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard invalidateCurrentStream(stream) else { return }
        onCaptureStateChanged(false, error.localizedDescription)
        onLog("系统音频捕获中断：\(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard isCurrentStream(stream) else { return }
        guard outputType == .audio else { return }
        processAudioSampleBuffer(sampleBuffer)
    }

    private func isCurrentStream(_ candidate: SCStream) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stream === candidate
    }

    private func installCurrentStream(_ candidate: SCStream) {
        stateLock.lock()
        stream = candidate
        stateLock.unlock()
    }

    private func beginCaptureIfCurrent(_ candidate: SCStream) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard stream === candidate else { return false }
        isCapturing = true
        return true
    }

    private func invalidateCurrentStream(_ candidate: SCStream) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard stream === candidate else { return false }
        stream = nil
        let wasCapturing = isCapturing
        isCapturing = false
        return wasCapturing
    }

    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let sourceFormatPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let sourceFormat = sourceFormatPointer.pointee
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        let channelCount = Int(max(sourceFormat.mChannelsPerFrame, 1))
        let bufferListSize = MemoryLayout<AudioBufferList>.size + max(0, channelCount - 1) * MemoryLayout<AudioBuffer>.size
        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: bufferListSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }

        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let sample = analyze(
            bufferList: UnsafeMutableAudioBufferListPointer(audioBufferList),
            frameCount: frameCount,
            sourceFormat: sourceFormat
        )

        let now = CACurrentMediaTime()
        if now - lastPublishTime >= (1.0 / 120.0) {
            lastPublishTime = now
            onSample(sample)
        }
    }

    private func analyze(
        bufferList: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        sourceFormat: AudioStreamBasicDescription
    ) -> AudioReactiveSample {
        let channels = Int(max(sourceFormat.mChannelsPerFrame, 1))
        let bitsPerChannel = Int(sourceFormat.mBitsPerChannel)
        let bytesPerSample = max(bitsPerChannel / 8, 1)
        let isFloat = (sourceFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (sourceFormat.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (sourceFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let isBigEndian = (sourceFormat.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let sampleRate = Float(sourceFormat.mSampleRate > 0 ? sourceFormat.mSampleRate : 48_000)

        var sumSquares: Float = 0
        var peak: Float = 0
        var lowPeak: Float = 0
        var attackPeak: Float = 0
        var lowAttackPeak: Float = 0
        var lowSumSquares: Float = 0
        var midSumSquares: Float = 0
        var highSumSquares: Float = 0

        let lowCutoff: Float = 180
        let midCutoff: Float = 2200
        let dt: Float = 1 / sampleRate
        let lowRC: Float = 1 / (2 * .pi * lowCutoff)
        let midRC: Float = 1 / (2 * .pi * midCutoff)
        let lowAlpha = dt / (lowRC + dt)
        let midAlpha = dt / (midRC + dt)
        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(frameCount)

        for frame in 0 ..< frameCount {
            var mono: Float = 0
            for channel in 0 ..< channels {
                mono += sampleValue(
                    in: bufferList,
                    frame: frame,
                    channel: channel,
                    channels: channels,
                    bytesPerSample: bytesPerSample,
                    isFloat: isFloat,
                    isSignedInteger: isSignedInteger,
                    isNonInterleaved: isNonInterleaved,
                    isBigEndian: isBigEndian,
                    bitsPerChannel: bitsPerChannel
                )
            }

            mono /= Float(channels)
            monoSamples.append(mono)
            let absValue = abs(mono)
            sumSquares += mono * mono
            peak = max(peak, absValue)
            attackPeak = max(attackPeak, abs(mono - previousMonoSample))
            previousMonoSample = mono

            lowPassState += lowAlpha * (mono - lowPassState)
            midPassState += midAlpha * (mono - midPassState)

            let lowBand = lowPassState
            let midBand = midPassState - lowBand
            let highBand = mono - midPassState

            lowAttackPeak = max(lowAttackPeak, abs(lowBand - previousLowBandSample))
            previousLowBandSample = lowBand

            lowSumSquares += lowBand * lowBand
            midSumSquares += midBand * midBand
            highSumSquares += highBand * highBand
            lowPeak = max(lowPeak, abs(lowBand))
        }

        let rms = sqrt(sumSquares / Float(max(frameCount, 1)))
        let lowRMS = sqrt(lowSumSquares / Float(max(frameCount, 1)))
        let midRMS = sqrt(midSumSquares / Float(max(frameCount, 1)))
        let highRMS = sqrt(highSumSquares / Float(max(frameCount, 1)))
        smoothedRMS = max(rms, smoothedRMS * 0.62)
        smoothedPeak = max(peak, smoothedPeak * 0.42)
        smoothedLow = max(lowPeak, smoothedLow * 0.58)
        smoothedMid = max(midRMS, smoothedMid * 0.64)

        slowRMS = (slowRMS * 0.988) + (rms * 0.012)
        slowLow = (slowLow * 0.988) + (lowRMS * 0.012)
        slowMid = (slowMid * 0.988) + (midRMS * 0.012)
        slowHigh = (slowHigh * 0.988) + (highRMS * 0.012)
        slowPeak = (slowPeak * 0.980) + (peak * 0.020)

        let transient = max(0, peak - max((rms * 1.08), (slowPeak * 0.94)))
        let bodyDelta = max(0, rms - (slowRMS * 0.96))
        let lowDelta = max(0, lowRMS - (slowLow * 0.90))
        let midDelta = max(0, midRMS - (slowMid * 0.94))
        let highDelta = max(0, highRMS - (slowHigh * 0.90))
        let attack = max(0, attackPeak - (rms * 0.55))
        let lowAttack = max(0, lowAttackPeak - (lowRMS * 0.48))
        let lowCrest = max(0, lowPeak - (lowRMS * 1.10))
        var effect = (transient * 0.46) +
                     (attack * 1.10) +
                     (highDelta * 1.22) +
                     (midDelta * 0.54) +
                     (bodyDelta * 0.14) +
                     (lowDelta * 0.10)
        var music = max(
            0,
            (slowMid * 1.02) +
            (slowLow * 0.48) +
            (bodyDelta * 0.22) -
            (highDelta * 0.95) -
            (attack * 0.82) -
            (transient * 0.46)
        )
        var movementPulse = max(
            0,
            (lowDelta * 1.20) +
            (lowAttack * 0.92) +
            (lowCrest * 0.88) +
            (transient * 0.12) -
            (music * 0.26)
        )
        var background = max(0, (music * 0.78) + (slowRMS * 0.24) - (effect * 0.60))

        let semanticPrediction = semanticAnalyzer.process(monoSamples: monoSamples, sourceSampleRate: sampleRate)
        let semanticBlend = blendLegacyAndSemanticChannels(
            legacyEffect: effect,
            legacyMusic: music,
            legacyMovementPulse: movementPulse,
            legacyBackground: background,
            transient: transient,
            attack: attack,
            lowDelta: lowDelta,
            slowMid: slowMid,
            slowRMS: slowRMS,
            semanticPrediction: semanticPrediction
        )
        effect = semanticBlend.effect
        music = semanticBlend.music
        movementPulse = semanticBlend.movementPulse
        background = semanticBlend.background

        smoothedTransient = max(transient, smoothedTransient * 0.36)
        smoothedAttack = max(attack, smoothedAttack * 0.28)
        smoothedEffect = max(effect, smoothedEffect * 0.46)
        smoothedMovementPulse = max(movementPulse, smoothedMovementPulse * 0.40)
        smoothedMusic = (smoothedMusic * 0.80) + (music * 0.20)
        smoothedBackground = (smoothedBackground * 0.72) + (background * 0.28)
        processedFrames += frameCount

        return AudioReactiveSample(
            rms: smoothedRMS,
            peak: smoothedPeak,
            lowFrequency: smoothedLow,
            midFrequency: smoothedMid,
            transient: smoothedTransient,
            attack: smoothedAttack,
            effect: smoothedEffect,
            movementPulse: smoothedMovementPulse,
            music: smoothedMusic,
            background: smoothedBackground,
            framesProcessed: processedFrames
        )
    }

    private func blendLegacyAndSemanticChannels(
        legacyEffect: Float,
        legacyMusic: Float,
        legacyMovementPulse: Float,
        legacyBackground: Float,
        transient: Float,
        attack: Float,
        lowDelta: Float,
        slowMid: Float,
        slowRMS: Float,
        semanticPrediction: AudioSemanticPrediction?
    ) -> (effect: Float, music: Float, movementPulse: Float, background: Float) {
        guard let semanticPrediction, semanticPrediction.isAvailable else {
            return (
                effect: legacyEffect,
                music: legacyMusic,
                movementPulse: legacyMovementPulse,
                background: legacyBackground
            )
        }

        let impactBias = max(
            semanticPrediction.impactStrength,
            max(semanticPrediction.dominantImpact * 0.92, semanticPrediction.dominantMixed * 0.55)
        )
        let movementBias = max(
            semanticPrediction.movementStrength,
            max(semanticPrediction.dominantMovement * 0.92, semanticPrediction.dominantMixed * 0.36)
        )
        let musicBias = max(
            semanticPrediction.musicSuppression,
            semanticPrediction.dominantMusic * 0.96
        )
        let sustainBias = max(
            semanticPrediction.sustainStrength,
            max(semanticPrediction.dominantMusic * 0.24, semanticPrediction.dominantMixed * 0.18)
        )
        let silenceAttenuation = max(0.25, 1 - (semanticPrediction.dominantSilence * 0.55))

        let semanticEffect = (
            (legacyEffect * (0.36 + (impactBias * 1.18))) +
            (transient * (impactBias * 0.24)) +
            (attack * (impactBias * 0.32))
        ) * silenceAttenuation

        let semanticMovement = (
            (legacyMovementPulse * (0.34 + (movementBias * 1.16))) +
            (lowDelta * (0.06 + (movementBias * 0.24)))
        ) * silenceAttenuation

        let semanticMusic = (
            (legacyMusic * (0.32 + (musicBias * 1.06))) +
            (slowMid * (0.12 + (musicBias * 0.20)))
        ) * max(0.22, 1 - (semanticPrediction.dominantSilence * 0.30))

        let semanticBackground = max(
            legacyBackground * (0.38 + (sustainBias * 0.86)),
            (slowRMS * (0.06 + (sustainBias * 0.20))) + (musicBias * 0.01)
        )

        return (
            effect: min(max(semanticEffect, 0), 0.35),
            music: min(max(semanticMusic, 0), 0.35),
            movementPulse: min(max(semanticMovement, 0), 0.26),
            background: min(max(semanticBackground, 0), 0.30)
        )
    }

    private func sampleValue(
        in bufferList: UnsafeMutableAudioBufferListPointer,
        frame: Int,
        channel: Int,
        channels: Int,
        bytesPerSample: Int,
        isFloat: Bool,
        isSignedInteger: Bool,
        isNonInterleaved: Bool,
        isBigEndian: Bool,
        bitsPerChannel: Int
    ) -> Float {
        let audioBuffer: AudioBuffer
        let sampleOffset: Int

        if isNonInterleaved {
            guard channel < bufferList.count else { return 0 }
            audioBuffer = bufferList[channel]
            sampleOffset = frame * bytesPerSample
        } else {
            guard let firstBuffer = bufferList.first else { return 0 }
            audioBuffer = firstBuffer
            sampleOffset = (frame * channels + channel) * bytesPerSample
        }

        guard let raw = audioBuffer.mData,
              sampleOffset + bytesPerSample <= Int(audioBuffer.mDataByteSize) else {
            return 0
        }

        let source = raw.advanced(by: sampleOffset)
        if isFloat {
            switch bitsPerChannel {
            case 32:
                return source.assumingMemoryBound(to: Float.self).pointee
            case 64:
                return Float(source.assumingMemoryBound(to: Double.self).pointee)
            default:
                return 0
            }
        }

        guard isSignedInteger else { return 0 }
        switch bitsPerChannel {
        case 16:
            let rawValue = source.assumingMemoryBound(to: Int16.self).pointee
            let value = isBigEndian ? Int16(bigEndian: rawValue) : rawValue
            return Float(value) / Float(Int16.max)
        case 32:
            let rawValue = source.assumingMemoryBound(to: Int32.self).pointee
            let value = isBigEndian ? Int32(bigEndian: rawValue) : rawValue
            return Float(value) / Float(Int32.max)
        default:
            return 0
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: AudioReactiveError.capturePermissionRequired)
                }
            }
        }
    }
}

enum AudioReactiveError: LocalizedError {
    case displayNotFound
    case capturePermissionRequired

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "没有找到可用于音频捕获的显示器。"
        case .capturePermissionRequired:
            return "无法启动系统音频捕获，请检查屏幕录制权限。"
        }
    }
}
