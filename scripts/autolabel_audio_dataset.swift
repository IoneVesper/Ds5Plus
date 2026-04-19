#!/usr/bin/env swift

import AVFoundation
import CoreMedia
import CryptoKit
import Foundation

struct Options {
    var sourceRoot: URL
    var outputRoot: URL
    var limit: Int?
    var games: Set<String>?
    var force = false
    var uniformPreset: AudioReactivePreset?
    var binDurationMS = 1000
}

struct SourceItem {
    let datasetID: String
    let game: String
    let preset: AudioReactivePreset
    let sourcePath: URL
    let durationSeconds: Double

    func annotationOutputPath(outputRoot: URL) -> URL {
        outputRoot
            .appendingPathComponent("annotations_auto", isDirectory: true)
            .appendingPathComponent(game, isDirectory: true)
            .appendingPathComponent("\(datasetID).csv", isDirectory: false)
    }
}

struct AudioReactiveTuning {
    let drive: Double
    let floor: Double
    let ceiling: Double
}

struct AudioReactiveProfile {
    let leftLow: Float
    let leftBody: Float
    let leftTransient: Float
    let rightLow: Float
    let rightBody: Float
    let rightTransient: Float
    let responseCurve: Float
}

struct AudioReactiveDetectionProfile {
    let musicSuppressionStrength: Float
    let sustainSuppressionStrength: Float
    let movementTriggerThreshold: Float
    let movementCooldown: TimeInterval
    let impactTriggerThreshold: Float
    let burstTriggerThreshold: Float
    let lowBandMusicPenalty: Float
    let midBandMusicPenalty: Float
    let musicDecay: Float
    let movementRecoveryGain: Float
    let backgroundGate: Float
    let sustainLeftCap: Float
    let sustainRightCap: Float
    let sustainLeftBias: Float
    let sustainRightBias: Float
    let tickStrengthCap: Float
    let pulseStrengthCap: Float
    let burstStrengthCap: Float
    let tickLeftMix: Float
    let tickRightMix: Float
    let pulseLeftMix: Float
    let pulseRightMix: Float
    let burstLeftMix: Float
    let burstRightMix: Float
}

struct AudioReactiveSample {
    var rms: Float = 0
    var peak: Float = 0
    var lowFrequency: Float = 0
    var midFrequency: Float = 0
    var transient: Float = 0
    var attack: Float = 0
    var effect: Float = 0
    var movementPulse: Float = 0
    var music: Float = 0
    var background: Float = 0
}

enum AudioReactivePreset: String, CaseIterable {
    case balanced
    case silksong
    case tunic
    case footsteps
    case combat
    case cinematic
    case bassBoost
    case impact

    var tuning: AudioReactiveTuning {
        switch self {
        case .balanced:
            return AudioReactiveTuning(drive: 2.2, floor: 0.015, ceiling: 0.14)
        case .silksong:
            return AudioReactiveTuning(drive: 1.85, floor: 0.022, ceiling: 0.17)
        case .tunic:
            return AudioReactiveTuning(drive: 1.70, floor: 0.024, ceiling: 0.18)
        case .footsteps:
            return AudioReactiveTuning(drive: 1.9, floor: 0.010, ceiling: 0.11)
        case .combat:
            return AudioReactiveTuning(drive: 2.5, floor: 0.014, ceiling: 0.10)
        case .cinematic:
            return AudioReactiveTuning(drive: 2.1, floor: 0.012, ceiling: 0.13)
        case .bassBoost:
            return AudioReactiveTuning(drive: 2.6, floor: 0.010, ceiling: 0.12)
        case .impact:
            return AudioReactiveTuning(drive: 2.8, floor: 0.018, ceiling: 0.11)
        }
    }

    var profile: AudioReactiveProfile {
        switch self {
        case .balanced:
            return AudioReactiveProfile(
                leftLow: 0.74,
                leftBody: 0.22,
                leftTransient: 0.04,
                rightLow: 0.08,
                rightBody: 0.54,
                rightTransient: 0.38,
                responseCurve: 0.92
            )
        case .silksong:
            return AudioReactiveProfile(
                leftLow: 0.42,
                leftBody: 0.12,
                leftTransient: 0.10,
                rightLow: 0.05,
                rightBody: 0.28,
                rightTransient: 0.82,
                responseCurve: 0.88
            )
        case .tunic:
            return AudioReactiveProfile(
                leftLow: 0.34,
                leftBody: 0.10,
                leftTransient: 0.14,
                rightLow: 0.04,
                rightBody: 0.20,
                rightTransient: 0.86,
                responseCurve: 0.82
            )
        case .footsteps:
            return AudioReactiveProfile(
                leftLow: 0.92,
                leftBody: 0.12,
                leftTransient: 0.06,
                rightLow: 0.18,
                rightBody: 0.26,
                rightTransient: 0.28,
                responseCurve: 0.96
            )
        case .combat:
            return AudioReactiveProfile(
                leftLow: 0.48,
                leftBody: 0.22,
                leftTransient: 0.30,
                rightLow: 0.04,
                rightBody: 0.20,
                rightTransient: 0.76,
                responseCurve: 0.76
            )
        case .cinematic:
            return AudioReactiveProfile(
                leftLow: 0.68,
                leftBody: 0.26,
                leftTransient: 0.10,
                rightLow: 0.12,
                rightBody: 0.44,
                rightTransient: 0.44,
                responseCurve: 0.90
            )
        case .bassBoost:
            return AudioReactiveProfile(
                leftLow: 0.88,
                leftBody: 0.10,
                leftTransient: 0.02,
                rightLow: 0.28,
                rightBody: 0.50,
                rightTransient: 0.22,
                responseCurve: 0.86
            )
        case .impact:
            return AudioReactiveProfile(
                leftLow: 0.52,
                leftBody: 0.28,
                leftTransient: 0.20,
                rightLow: 0.05,
                rightBody: 0.30,
                rightTransient: 0.65,
                responseCurve: 0.78
            )
        }
    }

    var detectionProfile: AudioReactiveDetectionProfile {
        switch self {
        case .balanced:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.06,
                sustainSuppressionStrength: 0.94,
                movementTriggerThreshold: 0.08,
                movementCooldown: 0.07,
                impactTriggerThreshold: 0.11,
                burstTriggerThreshold: 0.22,
                lowBandMusicPenalty: 0.26,
                midBandMusicPenalty: 0.18,
                musicDecay: 0.86,
                movementRecoveryGain: 0.42,
                backgroundGate: 0.035,
                sustainLeftCap: 0.20,
                sustainRightCap: 0.16,
                sustainLeftBias: 1.0,
                sustainRightBias: 1.0,
                tickStrengthCap: 0.52,
                pulseStrengthCap: 0.66,
                burstStrengthCap: 0.92,
                tickLeftMix: 0.18,
                tickRightMix: 0.05,
                pulseLeftMix: 0.09,
                pulseRightMix: 0.24,
                burstLeftMix: 0.14,
                burstRightMix: 0.34
            )
        case .silksong:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.38,
                sustainSuppressionStrength: 1.16,
                movementTriggerThreshold: 0.10,
                movementCooldown: 0.09,
                impactTriggerThreshold: 0.10,
                burstTriggerThreshold: 0.20,
                lowBandMusicPenalty: 0.44,
                midBandMusicPenalty: 0.34,
                musicDecay: 0.80,
                movementRecoveryGain: 0.36,
                backgroundGate: 0.055,
                sustainLeftCap: 0.11,
                sustainRightCap: 0.08,
                sustainLeftBias: 0.62,
                sustainRightBias: 0.48,
                tickStrengthCap: 0.34,
                pulseStrengthCap: 0.68,
                burstStrengthCap: 0.90,
                tickLeftMix: 0.18,
                tickRightMix: 0.04,
                pulseLeftMix: 0.08,
                pulseRightMix: 0.34,
                burstLeftMix: 0.10,
                burstRightMix: 0.46
            )
        case .tunic:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.52,
                sustainSuppressionStrength: 1.24,
                movementTriggerThreshold: 0.12,
                movementCooldown: 0.12,
                impactTriggerThreshold: 0.12,
                burstTriggerThreshold: 0.18,
                lowBandMusicPenalty: 0.52,
                midBandMusicPenalty: 0.40,
                musicDecay: 0.92,
                movementRecoveryGain: 0.28,
                backgroundGate: 0.06,
                sustainLeftCap: 0.09,
                sustainRightCap: 0.06,
                sustainLeftBias: 0.52,
                sustainRightBias: 0.42,
                tickStrengthCap: 0.24,
                pulseStrengthCap: 0.72,
                burstStrengthCap: 0.94,
                tickLeftMix: 0.10,
                tickRightMix: 0.03,
                pulseLeftMix: 0.06,
                pulseRightMix: 0.38,
                burstLeftMix: 0.12,
                burstRightMix: 0.52
            )
        case .footsteps:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 0.92,
                sustainSuppressionStrength: 0.84,
                movementTriggerThreshold: 0.06,
                movementCooldown: 0.06,
                impactTriggerThreshold: 0.12,
                burstTriggerThreshold: 0.26,
                lowBandMusicPenalty: 0.18,
                midBandMusicPenalty: 0.12,
                musicDecay: 0.84,
                movementRecoveryGain: 0.48,
                backgroundGate: 0.022,
                sustainLeftCap: 0.24,
                sustainRightCap: 0.16,
                sustainLeftBias: 1.08,
                sustainRightBias: 0.88,
                tickStrengthCap: 0.58,
                pulseStrengthCap: 0.60,
                burstStrengthCap: 0.82,
                tickLeftMix: 0.22,
                tickRightMix: 0.07,
                pulseLeftMix: 0.08,
                pulseRightMix: 0.20,
                burstLeftMix: 0.12,
                burstRightMix: 0.28
            )
        case .combat:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.08,
                sustainSuppressionStrength: 0.90,
                movementTriggerThreshold: 0.09,
                movementCooldown: 0.08,
                impactTriggerThreshold: 0.08,
                burstTriggerThreshold: 0.16,
                lowBandMusicPenalty: 0.24,
                midBandMusicPenalty: 0.16,
                musicDecay: 0.84,
                movementRecoveryGain: 0.30,
                backgroundGate: 0.03,
                sustainLeftCap: 0.16,
                sustainRightCap: 0.12,
                sustainLeftBias: 0.88,
                sustainRightBias: 0.92,
                tickStrengthCap: 0.38,
                pulseStrengthCap: 0.72,
                burstStrengthCap: 0.96,
                tickLeftMix: 0.14,
                tickRightMix: 0.05,
                pulseLeftMix: 0.10,
                pulseRightMix: 0.32,
                burstLeftMix: 0.14,
                burstRightMix: 0.48
            )
        case .cinematic:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.14,
                sustainSuppressionStrength: 0.98,
                movementTriggerThreshold: 0.09,
                movementCooldown: 0.10,
                impactTriggerThreshold: 0.11,
                burstTriggerThreshold: 0.22,
                lowBandMusicPenalty: 0.30,
                midBandMusicPenalty: 0.22,
                musicDecay: 0.90,
                movementRecoveryGain: 0.34,
                backgroundGate: 0.04,
                sustainLeftCap: 0.17,
                sustainRightCap: 0.13,
                sustainLeftBias: 0.90,
                sustainRightBias: 0.84,
                tickStrengthCap: 0.30,
                pulseStrengthCap: 0.58,
                burstStrengthCap: 0.76,
                tickLeftMix: 0.16,
                tickRightMix: 0.05,
                pulseLeftMix: 0.08,
                pulseRightMix: 0.18,
                burstLeftMix: 0.12,
                burstRightMix: 0.22
            )
        case .bassBoost:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 0.86,
                sustainSuppressionStrength: 0.70,
                movementTriggerThreshold: 0.07,
                movementCooldown: 0.07,
                impactTriggerThreshold: 0.12,
                burstTriggerThreshold: 0.24,
                lowBandMusicPenalty: 0.10,
                midBandMusicPenalty: 0.08,
                musicDecay: 0.88,
                movementRecoveryGain: 0.52,
                backgroundGate: 0.02,
                sustainLeftCap: 0.28,
                sustainRightCap: 0.22,
                sustainLeftBias: 1.12,
                sustainRightBias: 0.96,
                tickStrengthCap: 0.48,
                pulseStrengthCap: 0.62,
                burstStrengthCap: 0.82,
                tickLeftMix: 0.20,
                tickRightMix: 0.06,
                pulseLeftMix: 0.12,
                pulseRightMix: 0.18,
                burstLeftMix: 0.16,
                burstRightMix: 0.26
            )
        case .impact:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.04,
                sustainSuppressionStrength: 0.88,
                movementTriggerThreshold: 0.09,
                movementCooldown: 0.08,
                impactTriggerThreshold: 0.08,
                burstTriggerThreshold: 0.14,
                lowBandMusicPenalty: 0.20,
                midBandMusicPenalty: 0.12,
                musicDecay: 0.82,
                movementRecoveryGain: 0.24,
                backgroundGate: 0.03,
                sustainLeftCap: 0.15,
                sustainRightCap: 0.12,
                sustainLeftBias: 0.78,
                sustainRightBias: 0.88,
                tickStrengthCap: 0.34,
                pulseStrengthCap: 0.76,
                burstStrengthCap: 0.98,
                tickLeftMix: 0.12,
                tickRightMix: 0.05,
                pulseLeftMix: 0.09,
                pulseRightMix: 0.30,
                burstLeftMix: 0.15,
                burstRightMix: 0.44
            )
        }
    }
}

struct AutoScores {
    let music: Float
    let impact: Float
    let movement: Float
    let sustain: Float
    let ambient: Float
}

struct RawFrame {
    let startMS: Int
    let endMS: Int
    let scores: AutoScores
}

struct BinnedLabel {
    let startMS: Int
    let endMS: Int
    let dominantSource: String
    let musicSuppress: Int
    let impactStrength: Int
    let movementStrength: Int
    let sustainStrength: Int
    let confidence: Int
    let scores: AutoScores

    var mergeKey: String {
        "\(dominantSource)|\(musicSuppress)|\(impactStrength)|\(movementStrength)|\(sustainStrength)"
    }
}

struct AnnotationSegment {
    var startMS: Int
    var endMS: Int
    let dominantSource: String
    let musicSuppress: Int
    let impactStrength: Int
    let movementStrength: Int
    let sustainStrength: Int
    var confidenceSum: Int
    var binCount: Int
    var musicSum: Float
    var impactSum: Float
    var movementSum: Float
    var sustainSum: Float
    let preset: AudioReactivePreset

    var confidence: Int {
        max(1, min(3, Int(round(Double(confidenceSum) / Double(max(binCount, 1))))))
    }

    var note: String {
        let count = Float(max(binCount, 1))
        let music = musicSum / count
        let impact = impactSum / count
        let movement = movementSum / count
        let sustain = sustainSum / count
        return String(
            format: "auto:preset=%@ m=%.2f i=%.2f mv=%.2f s=%.2f",
            preset.rawValue,
            music,
            impact,
            movement,
            sustain
        )
    }
}

enum ScriptError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case missingAudioTrack(URL)
    case readerStartFailed(URL)
    case readerFailed(URL, String)

    var description: String {
        switch self {
        case let .invalidArguments(message):
            return message
        case let .missingAudioTrack(url):
            return "No audio track found for \(url.path)"
        case let .readerStartFailed(url):
            return "Could not start AVAssetReader for \(url.path)"
        case let .readerFailed(url, message):
            return "AVAssetReader failed for \(url.path): \(message)"
        }
    }
}

final class OfflineAudioAnalyzer {
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

    func analyze(sampleBuffer: CMSampleBuffer) -> AudioReactiveSample? {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else {
            return nil
        }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let sourceFormatPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let sourceFormat = sourceFormatPointer.pointee
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let totalLength = CMBlockBufferGetDataLength(blockBuffer)
        guard totalLength > 0 else { return nil }

        var contiguousLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let pointerStatus = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &contiguousLength,
            dataPointerOut: &dataPointer
        )

        if pointerStatus == kCMBlockBufferNoErr,
           contiguousLength >= totalLength,
           let dataPointer {
            return analyzePCMBytes(
                bytes: UnsafeRawPointer(dataPointer),
                byteCount: totalLength,
                frameCount: frameCount,
                sourceFormat: sourceFormat
            )
        }

        var copied = [UInt8](repeating: 0, count: totalLength)
        let copyStatus = copied.withUnsafeMutableBytes { rawBytes -> OSStatus in
            guard let destination = rawBytes.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: totalLength,
                destination: destination
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        return copied.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress else { return nil }
            return analyzePCMBytes(
                bytes: baseAddress,
                byteCount: totalLength,
                frameCount: frameCount,
                sourceFormat: sourceFormat
            )
        }
    }

    private func analyzePCMBytes(
        bytes: UnsafeRawPointer,
        byteCount: Int,
        frameCount: Int,
        sourceFormat: AudioStreamBasicDescription
    ) -> AudioReactiveSample {
        let channels = Int(max(sourceFormat.mChannelsPerFrame, 1))
        let bitsPerChannel = Int(sourceFormat.mBitsPerChannel)
        let bytesPerSample = max(bitsPerChannel / 8, 1)
        let isFloat = (sourceFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (sourceFormat.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isBigEndian = (sourceFormat.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let sampleRate = Float(sourceFormat.mSampleRate > 0 ? sourceFormat.mSampleRate : 48_000)
        let expectedBytes = frameCount * channels * bytesPerSample
        guard byteCount >= expectedBytes else { return AudioReactiveSample() }

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

        for frame in 0 ..< frameCount {
            var mono: Float = 0
            for channel in 0 ..< channels {
                mono += sampleValue(
                    bytes: bytes,
                    frame: frame,
                    channel: channel,
                    channels: channels,
                    bytesPerSample: bytesPerSample,
                    isFloat: isFloat,
                    isSignedInteger: isSignedInteger,
                    isBigEndian: isBigEndian,
                    bitsPerChannel: bitsPerChannel
                )
            }

            mono /= Float(channels)
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
        let effect = (transient * 0.46) +
            (attack * 1.10) +
            (highDelta * 1.22) +
            (midDelta * 0.54) +
            (bodyDelta * 0.14) +
            (lowDelta * 0.10)
        let music = max(
            0,
            (slowMid * 1.02) +
                (slowLow * 0.48) +
                (bodyDelta * 0.22) -
                (highDelta * 0.95) -
                (attack * 0.82) -
                (transient * 0.46)
        )
        let movementPulse = max(
            0,
            (lowDelta * 1.20) +
                (lowAttack * 0.92) +
                (lowCrest * 0.88) +
                (transient * 0.12) -
                (music * 0.26)
        )
        let background = max(0, (music * 0.78) + (slowRMS * 0.24) - (effect * 0.60))

        smoothedTransient = max(transient, smoothedTransient * 0.36)
        smoothedAttack = max(attack, smoothedAttack * 0.28)
        smoothedEffect = max(effect, smoothedEffect * 0.46)
        smoothedMovementPulse = max(movementPulse, smoothedMovementPulse * 0.40)
        smoothedMusic = (smoothedMusic * 0.80) + (music * 0.20)
        smoothedBackground = (smoothedBackground * 0.72) + (background * 0.28)

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
            background: smoothedBackground
        )
    }

    private func sampleValue(
        bytes: UnsafeRawPointer,
        frame: Int,
        channel: Int,
        channels: Int,
        bytesPerSample: Int,
        isFloat: Bool,
        isSignedInteger: Bool,
        isBigEndian: Bool,
        bitsPerChannel: Int
    ) -> Float {
        let sampleOffset = (frame * channels + channel) * bytesPerSample
        let source = bytes.advanced(by: sampleOffset)
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
}

final class AutoLabelingPipeline {
    private let tuning: AudioReactiveTuning
    private let profile: AudioReactiveProfile
    private let detection: AudioReactiveDetectionProfile
    private var previousMovementSignal: Float = 0
    private var previousImpactSignal: Float = 0
    private var suppressionMemory: Float = 0
    private var sustainLeftState: Float = 0
    private var sustainRightState: Float = 0
    private var tickEnvelope: Float = 0
    private var pulseEnvelope: Float = 0
    private var burstEnvelope: Float = 0
    private var lastTickTriggerTime: Double = 0
    private var lastPulseTriggerTime: Double = 0
    private var lastBurstTriggerTime: Double = 0

    init(preset: AudioReactivePreset) {
        tuning = preset.tuning
        profile = preset.profile
        detection = preset.detectionProfile
    }

    func process(_ sample: AudioReactiveSample, time: Double) -> AutoScores {
        let floor = Float(tuning.floor)
        let ceiling = max(Float(tuning.ceiling), floor + 0.001)
        let gain = Float(tuning.drive)

        func normalize(_ value: Float) -> Float {
            min(max((value - floor) / (ceiling - floor), 0), 1)
        }

        func shape(_ value: Float) -> Float {
            let clamped = min(max(value * gain, 0), 1)
            return pow(clamped, profile.responseCurve)
        }

        let low = normalize(sample.lowFrequency)
        let mid = normalize(sample.midFrequency)
        let body = normalize(sample.rms)
        let transient = normalize(sample.transient)
        let attack = normalize(sample.attack)
        let effect = normalize(sample.effect)
        let movementPulse = normalize(sample.movementPulse)
        let music = normalize(sample.music)
        let background = normalize(sample.background)

        let foreground = max(effect * 1.12, max(transient * 1.02, max(attack * 1.18, movementPulse * 0.86)))
        let rawMusicDominance =
            (music * detection.musicSuppressionStrength) +
            (background * detection.sustainSuppressionStrength) +
            (low * detection.lowBandMusicPenalty) +
            (mid * detection.midBandMusicPenalty)

        let rawSuppression = min(max(rawMusicDominance - (foreground * 0.56), 0), 1)
        suppressionMemory = max(rawSuppression, suppressionMemory * detection.musicDecay)
        let suppression = suppressionMemory

        let lowForeground = max(low - (suppression * detection.lowBandMusicPenalty * 0.32), 0)
        let bodyForeground = max(body - (suppression * detection.midBandMusicPenalty * 0.18), 0)
        let midForeground = max(mid - (suppression * detection.midBandMusicPenalty * 0.26), 0)

        let impactPresence = max(effect, max(transient, max(attack * 1.08, movementPulse * 0.88)))
        let movementBias = min(max((impactPresence * 1.28) + (movementPulse * 0.76) + (bodyForeground * 0.06), 0.10), 0.84)
        let controlledLow = lowForeground * movementBias
        let sustainGate = max(effect, max(transient, max(attack * 1.04, max(movementPulse * 1.02, controlledLow * 0.24))))

        let eventSuppression = min(max(1 - (suppression * 0.24), 0.44), 1)
        let sustainSuppression = min(
            max((1 - (suppression * detection.sustainSuppressionStrength)) + (movementPulse * detection.movementRecoveryGain), 0),
            1
        )

        let leftContinuous =
            (controlledLow * (profile.leftLow * 0.30 + 0.02)) +
            (bodyForeground * (profile.leftBody * 0.06)) +
            (midForeground * 0.04) +
            (transient * (profile.leftTransient * 0.18 + 0.02)) +
            (attack * 0.06) +
            (movementPulse * 0.18) +
            (effect * 0.20)

        let rightContinuous =
            (controlledLow * (profile.rightLow * 0.08)) +
            (bodyForeground * (profile.rightBody * 0.05)) +
            (midForeground * 0.02) +
            (transient * (profile.rightTransient * 0.22 + 0.04)) +
            (attack * 0.24) +
            (movementPulse * 0.08) +
            (effect * 0.22)

        let sustainLeftTarget = min(
            shape(leftContinuous) * (0.14 + profile.leftLow * 0.08) * detection.sustainLeftBias,
            detection.sustainLeftCap
        ) * sustainSuppression

        let sustainRightTarget = min(
            shape(rightContinuous) * (0.10 + profile.rightTransient * 0.06) * detection.sustainRightBias,
            detection.sustainRightCap
        ) * sustainSuppression

        sustainLeftState = max(sustainLeftTarget, sustainLeftState * 0.64)
        sustainRightState = max(sustainRightTarget, sustainRightState * 0.60)

        tickEnvelope *= 0.54
        pulseEnvelope *= 0.76
        burstEnvelope *= 0.86

        let movementSignal = max(movementPulse * 1.06, controlledLow * 0.36)
        let impactSignal = max(effect * 1.08, max(transient * 1.02, attack * 1.20))
        let movementOnset = max(movementSignal - (previousMovementSignal * 0.82), 0)
        let impactOnset = max(impactSignal - (previousImpactSignal * 0.72), 0)
        previousMovementSignal = movementSignal
        previousImpactSignal = impactSignal

        if sustainGate > detection.backgroundGate,
           movementSignal > detection.movementTriggerThreshold,
           movementOnset > (detection.movementTriggerThreshold * 0.42),
           time - lastTickTriggerTime >= detection.movementCooldown {
            let tickStrength = min(
                0.10 + (movementOnset * 1.05) + (movementSignal * 0.18),
                detection.tickStrengthCap
            ) * eventSuppression
            tickEnvelope = max(tickEnvelope, tickStrength)
            lastTickTriggerTime = time
        }

        if impactSignal > detection.impactTriggerThreshold,
           impactOnset > (detection.impactTriggerThreshold * 0.45),
           time - lastPulseTriggerTime >= max(detection.movementCooldown * 1.1, 0.10) {
            let pulseStrength = min(
                0.18 + (impactOnset * 1.12) + (attack * 0.08),
                detection.pulseStrengthCap
            ) * eventSuppression
            pulseEnvelope = max(pulseEnvelope, pulseStrength)
            lastPulseTriggerTime = time
        }

        if impactSignal > detection.burstTriggerThreshold,
           impactOnset > (detection.burstTriggerThreshold * 0.36),
           time - lastBurstTriggerTime >= max(detection.movementCooldown * 1.5, 0.14) {
            let burstStrength = min(
                0.24 + (impactSignal * 0.48) + (impactOnset * 1.28),
                detection.burstStrengthCap
            ) * eventSuppression
            burstEnvelope = max(burstEnvelope, burstStrength)
            lastBurstTriggerTime = time
        }

        if sustainGate < detection.backgroundGate,
           tickEnvelope < 0.015,
           pulseEnvelope < 0.015,
           burstEnvelope < 0.015 {
            sustainLeftState *= 0.80
            sustainRightState *= 0.76
        }

        let musicScore = clamp(max(suppression, music * 0.96, background * 0.72))
        let impactScore = clamp(max(impactSignal, pulseEnvelope * 1.10, burstEnvelope * 1.25, effect * 0.92))
        let movementScore = clamp(max(movementSignal, tickEnvelope * 1.25))
        let sustainScore = clamp(max(sustainLeftState, sustainRightState, controlledLow * 0.50, bodyForeground * 0.18))
        let ambientBase = max(background * 0.95, lowForeground * 0.24, bodyForeground * 0.18)
        let ambientScore = clamp(ambientBase * (1 - min(max(impactScore, movementScore) * 0.55, 0.55)))

        return AutoScores(
            music: musicScore,
            impact: impactScore,
            movement: movementScore,
            sustain: sustainScore,
            ambient: ambientScore
        )
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

struct BinAccumulator {
    var count = 0
    var musicSum: Float = 0
    var impactSum: Float = 0
    var movementSum: Float = 0
    var sustainSum: Float = 0
    var ambientSum: Float = 0
    var musicMax: Float = 0
    var impactMax: Float = 0
    var movementMax: Float = 0
    var sustainMax: Float = 0
    var ambientMax: Float = 0

    mutating func add(_ scores: AutoScores) {
        count += 1
        musicSum += scores.music
        impactSum += scores.impact
        movementSum += scores.movement
        sustainSum += scores.sustain
        ambientSum += scores.ambient
        musicMax = max(musicMax, scores.music)
        impactMax = max(impactMax, scores.impact)
        movementMax = max(movementMax, scores.movement)
        sustainMax = max(sustainMax, scores.sustain)
        ambientMax = max(ambientMax, scores.ambient)
    }

    func normalizedScores() -> AutoScores {
        let divisor = Float(max(count, 1))
        let music = max(musicSum / divisor, musicMax * 0.85)
        let impact = max((impactSum / divisor) * 0.60, impactMax)
        let movement = max((movementSum / divisor) * 0.60, movementMax)
        let sustain = max(sustainSum / divisor, sustainMax * 0.85)
        let ambient = max(ambientSum / divisor, ambientMax * 0.85)
        return AutoScores(music: music, impact: impact, movement: movement, sustain: sustain, ambient: ambient)
    }
}

func parseOptions() throws -> Options {
    var options = Options(
        sourceRoot: URL(fileURLWithPath: "/Volumes/SSD/音频数据集", isDirectory: true),
        outputRoot: URL(fileURLWithPath: "/Volumes/SSD/音频数据集/prepared_dataset", isDirectory: true)
    )

    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let argument = args.removeFirst()
        switch argument {
        case "--source-root":
            guard let value = args.first else { throw ScriptError.invalidArguments("Missing value for --source-root") }
            args.removeFirst()
            options.sourceRoot = URL(fileURLWithPath: value, isDirectory: true)
        case "--output-root":
            guard let value = args.first else { throw ScriptError.invalidArguments("Missing value for --output-root") }
            args.removeFirst()
            options.outputRoot = URL(fileURLWithPath: value, isDirectory: true)
        case "--limit":
            guard let value = args.first, let parsed = Int(value) else { throw ScriptError.invalidArguments("Invalid value for --limit") }
            args.removeFirst()
            options.limit = parsed
        case "--games":
            guard let value = args.first else { throw ScriptError.invalidArguments("Missing value for --games") }
            args.removeFirst()
            let games = value
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            options.games = Set(games)
        case "--uniform-preset":
            guard let value = args.first, let preset = AudioReactivePreset(rawValue: value) else {
                throw ScriptError.invalidArguments("Invalid value for --uniform-preset")
            }
            args.removeFirst()
            options.uniformPreset = preset
        case "--bin-ms":
            guard let value = args.first, let parsed = Int(value), parsed >= 100 else {
                throw ScriptError.invalidArguments("Invalid value for --bin-ms")
            }
            args.removeFirst()
            options.binDurationMS = parsed
        case "--force":
            options.force = true
        case "--help":
            printUsage()
            exit(0)
        default:
            throw ScriptError.invalidArguments("Unknown argument: \(argument)")
        }
    }

    return options
}

func printUsage() {
    print(
        """
        Usage:
          swift scripts/autolabel_audio_dataset.swift [options]

        Options:
          --source-root PATH         Source directory with gameplay videos
          --output-root PATH         Output directory for auto-label CSVs
          --games a,b,c             Limit to selected games
          --limit N                 Process only first N files
          --uniform-preset PRESET   Override per-game presets
          --bin-ms N                Label bin size in milliseconds (default 1000)
          --force                   Overwrite existing auto-label CSVs
        """
    )
}

func inferGame(from fileName: String) -> String {
    if fileName.contains("丝之歌") {
        return "silksong"
    }
    if fileName.contains("战地1") {
        return "battlefield1"
    }
    if fileName.contains("死亡搁浅2") || fileName.contains("Death Stranding2") {
        return "death_stranding_2"
    }
    return "unknown"
}

func defaultPreset(for game: String) -> AudioReactivePreset {
    switch game {
    case "silksong":
        return .silksong
    case "battlefield1":
        return .combat
    case "death_stranding_2":
        return .cinematic
    default:
        return .balanced
    }
}

func inferPartNumber(from fileName: String) -> Int? {
    let pattern = #"\s-\s(\d{1,3})\s-\s"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(fileName.startIndex ..< fileName.endIndex, in: fileName)
    guard let match = regex.firstMatch(in: fileName, range: range),
          match.numberOfRanges > 1,
          let partRange = Range(match.range(at: 1), in: fileName) else {
        return nil
    }
    return Int(fileName[partRange])
}

func datasetID(for sourcePath: URL, game: String, ordinal: Int) -> String {
    let hashData = Data(sourcePath.path.utf8)
    let digest = Insecure.SHA1.hash(data: hashData)
    let fingerprint = digest.map { String(format: "%02x", $0) }.joined().prefix(8)
    if let partNumber = inferPartNumber(from: sourcePath.lastPathComponent) {
        return "\(game)_\(String(format: "%03d", partNumber))_\(fingerprint)"
    }
    return "\(game)_x\(String(format: "%03d", ordinal))_\(fingerprint)"
}

func durationSeconds(for sourcePath: URL) -> Double {
    let asset = AVURLAsset(url: sourcePath)
    return CMTimeGetSeconds(asset.duration)
}

func discoverSources(options: Options) -> [SourceItem] {
    let fm = FileManager.default
    let supportedExtensions = Set(["mp4", "mkv", "mov", "webm", "m4v", "mp3", "wav", "flac", "m4a", "aac"])
    guard let enumerator = fm.enumerator(
        at: options.sourceRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var groupedOrdinals: [String: Int] = [:]
    var result: [SourceItem] = []
    for case let fileURL as URL in enumerator {
        guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
        let game = inferGame(from: fileURL.lastPathComponent)
        if let games = options.games, !games.contains(game) {
            continue
        }

        groupedOrdinals[game, default: 0] += 1
        let preset = options.uniformPreset ?? defaultPreset(for: game)
        result.append(
            SourceItem(
                datasetID: datasetID(for: fileURL, game: game, ordinal: groupedOrdinals[game] ?? 1),
                game: game,
                preset: preset,
                sourcePath: fileURL,
                durationSeconds: durationSeconds(for: fileURL)
            )
        )

        if let limit = options.limit, result.count >= limit {
            break
        }
    }

    return result.sorted { lhs, rhs in
        lhs.sourcePath.path < rhs.sourcePath.path
    }
}

func processSource(_ item: SourceItem, binDurationMS: Int) throws -> [AnnotationSegment] {
    let asset = AVURLAsset(url: item.sourcePath)
    guard let track = asset.tracks(withMediaType: .audio).first else {
        throw ScriptError.missingAudioTrack(item.sourcePath)
    }

    let reader = try AVAssetReader(asset: asset)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        throw ScriptError.readerStartFailed(item.sourcePath)
    }
    reader.add(output)

    guard reader.startReading() else {
        throw ScriptError.readerStartFailed(item.sourcePath)
    }

    let analyzer = OfflineAudioAnalyzer()
    let pipeline = AutoLabelingPipeline(preset: item.preset)
    var rawFrames: [RawFrame] = []

    while reader.status == .reading {
        guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
        guard let analyzed = analyzer.analyze(sampleBuffer: sampleBuffer) else { continue }

        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        let sampleRate = formatDescription
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate }
            ?? 48_000
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let durationSeconds: Double
        if duration.isValid, duration.seconds.isFinite, duration.seconds > 0 {
            durationSeconds = duration.seconds
        } else {
            durationSeconds = Double(frameCount) / sampleRate
        }

        let startSeconds = max(0, startTime.seconds)
        let endSeconds = startSeconds + durationSeconds
        let midpoint = startSeconds + (durationSeconds / 2)
        let scores = pipeline.process(analyzed, time: midpoint)
        rawFrames.append(
            RawFrame(
                startMS: Int((startSeconds * 1000).rounded()),
                endMS: Int((endSeconds * 1000).rounded()),
                scores: scores
            )
        )
    }

    if reader.status == .failed {
        throw ScriptError.readerFailed(item.sourcePath, reader.error?.localizedDescription ?? "unknown error")
    }

    return buildSegments(rawFrames: rawFrames, preset: item.preset, binDurationMS: binDurationMS)
}

func buildSegments(rawFrames: [RawFrame], preset: AudioReactivePreset, binDurationMS: Int) -> [AnnotationSegment] {
    guard !rawFrames.isEmpty else { return [] }
    var bins: [Int: BinAccumulator] = [:]

    for frame in rawFrames {
        let midpoint = (frame.startMS + frame.endMS) / 2
        let index = midpoint / binDurationMS
        bins[index, default: BinAccumulator()].add(frame.scores)
    }

    let sortedIndices = bins.keys.sorted()
    var labels: [BinnedLabel] = sortedIndices.compactMap { index in
        guard let accumulator = bins[index] else { return nil }
        let scores = accumulator.normalizedScores()
        return classifyBin(index: index, scores: scores, binDurationMS: binDurationMS)
    }

    if labels.count >= 3 {
        for index in 1 ..< (labels.count - 1) {
            let previous = labels[index - 1]
            let current = labels[index]
            let next = labels[index + 1]
            if previous.mergeKey == next.mergeKey, current.mergeKey != previous.mergeKey {
                labels[index] = BinnedLabel(
                    startMS: current.startMS,
                    endMS: current.endMS,
                    dominantSource: previous.dominantSource,
                    musicSuppress: previous.musicSuppress,
                    impactStrength: previous.impactStrength,
                    movementStrength: previous.movementStrength,
                    sustainStrength: previous.sustainStrength,
                    confidence: min(previous.confidence, next.confidence),
                    scores: previous.scores
                )
            }
        }
    }

    var segments: [AnnotationSegment] = []
    for label in labels {
        if var last = segments.last, last.dominantSource == label.dominantSource,
           last.musicSuppress == label.musicSuppress,
           last.impactStrength == label.impactStrength,
           last.movementStrength == label.movementStrength,
           last.sustainStrength == label.sustainStrength {
            last.endMS = label.endMS
            last.confidenceSum += label.confidence
            last.binCount += 1
            last.musicSum += label.scores.music
            last.impactSum += label.scores.impact
            last.movementSum += label.scores.movement
            last.sustainSum += label.scores.sustain
            segments[segments.count - 1] = last
        } else {
            segments.append(
                AnnotationSegment(
                    startMS: label.startMS,
                    endMS: label.endMS,
                    dominantSource: label.dominantSource,
                    musicSuppress: label.musicSuppress,
                    impactStrength: label.impactStrength,
                    movementStrength: label.movementStrength,
                    sustainStrength: label.sustainStrength,
                    confidenceSum: label.confidence,
                    binCount: 1,
                    musicSum: label.scores.music,
                    impactSum: label.scores.impact,
                    movementSum: label.scores.movement,
                    sustainSum: label.scores.sustain,
                    preset: preset
                )
            )
        }
    }

    return segments
}

func classifyBin(index: Int, scores: AutoScores, binDurationMS: Int) -> BinnedLabel {
    let musicSuppress = quantize(scores.music, thresholds: (0.12, 0.24, 0.42))
    let impactStrength = quantize(scores.impact, thresholds: (0.08, 0.18, 0.36))
    let movementStrength = quantize(scores.movement, thresholds: (0.12, 0.26, 0.46))
    let sustainStrength = quantize(scores.sustain, thresholds: (0.06, 0.15, 0.28))

    let candidates: [(String, Float)] = [
        ("music", scores.music),
        ("impact", scores.impact),
        ("movement", scores.movement),
        ("ambient", scores.ambient),
    ].sorted { lhs, rhs in
        lhs.1 > rhs.1
    }

    let top = candidates[0]
    let second = candidates.count > 1 ? candidates[1] : ("silence", 0)

    let dominantSource: String
    if top.1 < 0.08, sustainStrength == 0 {
        dominantSource = "silence"
    } else if second.1 > 0.18, second.1 >= top.1 * 0.82 {
        dominantSource = "mixed"
    } else {
        dominantSource = top.0
    }

    let confidence: Int
    if dominantSource == "silence" {
        confidence = 3
    } else {
        let gap = top.1 - second.1
        if gap >= 0.18 || top.1 >= 0.72 {
            confidence = 3
        } else if gap >= 0.08 {
            confidence = 2
        } else {
            confidence = 1
        }
    }

    let startMS = index * binDurationMS
    return BinnedLabel(
        startMS: startMS,
        endMS: startMS + binDurationMS,
        dominantSource: dominantSource,
        musicSuppress: musicSuppress,
        impactStrength: impactStrength,
        movementStrength: movementStrength,
        sustainStrength: sustainStrength,
        confidence: confidence,
        scores: scores
    )
}

func quantize(_ value: Float, thresholds: (Float, Float, Float)) -> Int {
    if value < thresholds.0 { return 0 }
    if value < thresholds.1 { return 1 }
    if value < thresholds.2 { return 2 }
    return 3
}

func writeSegments(_ segments: [AnnotationSegment], to destination: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

    var lines = [
        "start_ms,end_ms,dominant_source,music_suppress,impact_strength,movement_strength,sustain_strength,confidence,notes"
    ]
    lines.reserveCapacity(segments.count + 1)
    for segment in segments {
        let escapedNote = csvEscape(segment.note)
        lines.append(
            "\(segment.startMS),\(segment.endMS),\(segment.dominantSource),\(segment.musicSuppress),\(segment.impactStrength),\(segment.movementStrength),\(segment.sustainStrength),\(segment.confidence),\(escapedNote)"
        )
    }
    try lines.joined(separator: "\n").write(to: destination, atomically: true, encoding: .utf8)
}

func csvEscape(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}

func writeManifest(rows: [[String: String]], outputRoot: URL) throws {
    guard !rows.isEmpty else { return }
    let fm = FileManager.default
    let manifestDirectory = outputRoot.appendingPathComponent("manifests", isDirectory: true)
    try fm.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)

    let headers = [
        "dataset_id",
        "game",
        "preset",
        "duration_seconds",
        "segment_count",
        "source_path",
        "annotation_path",
    ]
    var lines = [headers.joined(separator: ",")]
    for row in rows {
        lines.append(headers.map { csvEscape(row[$0] ?? "") }.joined(separator: ","))
    }

    let manifestPath = manifestDirectory.appendingPathComponent("auto_labels_manifest.csv", isDirectory: false)
    try lines.joined(separator: "\n").write(to: manifestPath, atomically: true, encoding: .utf8)
}

do {
    let options = try parseOptions()
    let sources = discoverSources(options: options)
    guard !sources.isEmpty else {
        throw ScriptError.invalidArguments("No matching media files found under \(options.sourceRoot.path)")
    }

    print("Auto-labeling \(sources.count) source files...")
    var manifestRows: [[String: String]] = []
    for (index, item) in sources.enumerated() {
        let destination = item.annotationOutputPath(outputRoot: options.outputRoot)
        if FileManager.default.fileExists(atPath: destination.path), !options.force {
            print("[\(index + 1)/\(sources.count)] Skipping existing \(destination.lastPathComponent)")
            continue
        }

        print("[\(index + 1)/\(sources.count)] \(item.sourcePath.lastPathComponent)")
        let segments = try processSource(item, binDurationMS: options.binDurationMS)
        try writeSegments(segments, to: destination)
        manifestRows.append(
            [
                "dataset_id": item.datasetID,
                "game": item.game,
                "preset": item.preset.rawValue,
                "duration_seconds": String(format: "%.3f", item.durationSeconds),
                "segment_count": "\(segments.count)",
                "source_path": item.sourcePath.path,
                "annotation_path": destination.path,
            ]
        )
    }

    try writeManifest(rows: manifestRows, outputRoot: options.outputRoot)
    print("Auto-labeling finished.")
    print("Manifest: \(options.outputRoot.appendingPathComponent("manifests/auto_labels_manifest.csv").path)")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
