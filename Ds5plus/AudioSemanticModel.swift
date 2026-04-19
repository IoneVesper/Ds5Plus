import Foundation
import Accelerate
import QuartzCore

nonisolated struct AudioSemanticPrediction: Sendable {
    var isAvailable = false
    var dominantImpact: Float = 0
    var dominantMixed: Float = 0
    var dominantMovement: Float = 0
    var dominantMusic: Float = 0
    var dominantSilence: Float = 0
    var musicSuppression: Float = 0
    var impactStrength: Float = 0
    var movementStrength: Float = 0
    var sustainStrength: Float = 0
}

nonisolated final class AudioSemanticModelRuntime: @unchecked Sendable {
    let analysis: AudioSemanticAnalysisConfiguration

    private let inputDimension: Int
    private let dominantSourceVocab: [String]
    private let featureMean: [Float]
    private let featureStd: [Float]
    private let linear1: AudioSemanticLinearLayer
    private let layerNorm1: AudioSemanticLayerNorm
    private let linear2: AudioSemanticLinearLayer
    private let dominantHead: AudioSemanticLinearLayer
    private let musicHead: AudioSemanticLinearLayer
    private let impactHead: AudioSemanticLinearLayer
    private let movementHead: AudioSemanticLinearLayer
    private let sustainHead: AudioSemanticLinearLayer
    private let dominantIndexByName: [String: Int]

    convenience init?(bundle: Bundle = .main) {
        guard let assetURL = Self.findAssetURL(in: bundle) else { return nil }
        try? self.init(assetURL: assetURL)
    }

    init(assetURL: URL) throws {
        let data = try Data(contentsOf: assetURL)
        let asset = try JSONDecoder().decode(AudioSemanticModelAsset.self, from: data)

        inputDimension = asset.inputDimension
        analysis = asset.analysis
        dominantSourceVocab = asset.dominantSourceVocab
        featureMean = asset.featureMean
        featureStd = asset.featureStd
        linear1 = asset.linear1
        layerNorm1 = asset.layerNorm1
        linear2 = asset.linear2
        dominantHead = asset.heads.dominantSource
        musicHead = asset.heads.musicSuppress
        impactHead = asset.heads.impactStrength
        movementHead = asset.heads.movementStrength
        sustainHead = asset.heads.sustainStrength
        dominantIndexByName = Dictionary(uniqueKeysWithValues: dominantSourceVocab.enumerated().map { ($1, $0) })
    }

    func predict(rawFeatureVector: [Float]) -> AudioSemanticPrediction? {
        guard rawFeatureVector.count == inputDimension else { return nil }

        var normalized = [Float](repeating: 0, count: inputDimension)
        for index in 0 ..< inputDimension {
            let scale = abs(featureStd[index]) < 1e-5 ? 1 : featureStd[index]
            normalized[index] = (rawFeatureVector[index] - featureMean[index]) / scale
        }

        var hidden1 = applyLinear(normalized, layer: linear1)
        applyLayerNorm(&hidden1, layer: layerNorm1)
        applyGELU(&hidden1)

        var hidden2 = applyLinear(hidden1, layer: linear2)
        applyGELU(&hidden2)

        let dominantLogits = applyLinear(hidden2, layer: dominantHead)
        let musicLogits = applyLinear(hidden2, layer: musicHead)
        let impactLogits = applyLinear(hidden2, layer: impactHead)
        let movementLogits = applyLinear(hidden2, layer: movementHead)
        let sustainLogits = applyLinear(hidden2, layer: sustainHead)

        let dominantProbabilities = softmax(dominantLogits)

        var prediction = AudioSemanticPrediction(isAvailable: true)
        prediction.dominantImpact = probability(named: "impact", in: dominantProbabilities)
        prediction.dominantMixed = probability(named: "mixed", in: dominantProbabilities)
        prediction.dominantMovement = probability(named: "movement", in: dominantProbabilities)
        prediction.dominantMusic = probability(named: "music", in: dominantProbabilities)
        prediction.dominantSilence = probability(named: "silence", in: dominantProbabilities)
        prediction.musicSuppression = normalizedExpectedOrdinal(from: musicLogits)
        prediction.impactStrength = normalizedExpectedOrdinal(from: impactLogits)
        prediction.movementStrength = normalizedExpectedOrdinal(from: movementLogits)
        prediction.sustainStrength = normalizedExpectedOrdinal(from: sustainLogits)
        return prediction
    }

    private func probability(named name: String, in probabilities: [Float]) -> Float {
        guard let index = dominantIndexByName[name], index < probabilities.count else { return 0 }
        return probabilities[index]
    }

    private func applyLinear(_ input: [Float], layer: AudioSemanticLinearLayer) -> [Float] {
        var output = Array(repeating: Float.zero, count: layer.rows)
        for row in 0 ..< layer.rows {
            let base = row * layer.columns
            var sum = layer.bias[row]
            for column in 0 ..< layer.columns {
                sum += layer.weights[base + column] * input[column]
            }
            output[row] = sum
        }
        return output
    }

    private func applyLayerNorm(_ values: inout [Float], layer: AudioSemanticLayerNorm) {
        guard !values.isEmpty else { return }
        let count = Float(values.count)
        let mean = values.reduce(0, +) / count

        var variance: Float = 0
        for value in values {
            let delta = value - mean
            variance += delta * delta
        }
        variance /= count

        let denominator = sqrt(variance + layer.epsilon)
        for index in values.indices {
            let normalized = (values[index] - mean) / denominator
            values[index] = (normalized * layer.weight[index]) + layer.bias[index]
        }
    }

    private func applyGELU(_ values: inout [Float]) {
        for index in values.indices {
            let value = values[index]
            values[index] = 0.5 * value * (1 + erf(value / sqrt(2)))
        }
    }

    private func softmax(_ logits: [Float]) -> [Float] {
        guard let maximum = logits.max() else { return [] }
        var exponentials = Array(repeating: Float.zero, count: logits.count)
        var total: Float = 0
        for index in logits.indices {
            let value = exp(logits[index] - maximum)
            exponentials[index] = value
            total += value
        }
        guard total > 0 else { return exponentials }
        for index in exponentials.indices {
            exponentials[index] /= total
        }
        return exponentials
    }

    private func normalizedExpectedOrdinal(from logits: [Float]) -> Float {
        let probabilities = softmax(logits)
        guard probabilities.count > 1 else { return 0 }
        let denominator = Float(probabilities.count - 1)
        var total: Float = 0
        for (index, probability) in probabilities.enumerated() {
            total += (Float(index) / denominator) * probability
        }
        return total
    }

    private static func findAssetURL(in bundle: Bundle) -> URL? {
        let direct = bundle.url(forResource: "AudioSemanticModel", withExtension: "json")
        let nested = bundle.url(forResource: "AudioSemanticModel", withExtension: "json", subdirectory: "Resources")
        if let direct { return direct }
        if let nested { return nested }

        let candidates = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []) +
            (bundle.urls(forResourcesWithExtension: "json", subdirectory: "Resources") ?? [])
        return candidates.first { $0.lastPathComponent == "AudioSemanticModel.json" }
    }
}

nonisolated final class AudioSemanticRealtimeAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private let model: AudioSemanticModelRuntime?
    private let spectrumBinCount: Int
    private let lowBandUpperBound: Int
    private let midBandUpperBound: Int
    private let windowSampleCount: Int
    private let runtimeUpdateInterval: CFTimeInterval
    private let stftPowerScale: Float
    private let dft: vDSP.DiscreteFourierTransform<Float>?
    private let zeroImaginary: [Float]

    private var recentSamples: [Float]
    private var recentSampleWriteIndex = 0
    private var recentSampleCount = 0
    private var downsampleBuffer: [Float] = []
    private var lastPredictionTime: CFTimeInterval = 0
    private var cachedPrediction = AudioSemanticPrediction()

    init(bundle: Bundle = .main) {
        model = AudioSemanticModelRuntime(bundle: bundle)
        let analysis = model?.analysis ?? AudioSemanticAnalysisConfiguration.fallback
        spectrumBinCount = (analysis.nFFT / 2) + 1
        let sampleRate = Float(analysis.sampleRate)
        let fft = Float(analysis.nFFT)
        lowBandUpperBound = max(1, min(spectrumBinCount, Int(floor((180 / sampleRate) * fft)) + 1))
        midBandUpperBound = max(lowBandUpperBound + 1, min(spectrumBinCount, Int(floor((2200 / sampleRate) * fft)) + 1))
        windowSampleCount = max(analysis.winLength, Int((analysis.analysisWindowSeconds * Float(analysis.sampleRate)).rounded()))
        runtimeUpdateInterval = CFTimeInterval(analysis.runtimeUpdateIntervalSeconds)
        let windowSum = max(analysis.analysisWindow.reduce(0, +), 1e-6)
        stftPowerScale = windowSum * windowSum
        dft = try? vDSP.DiscreteFourierTransform(
            count: analysis.nFFT,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
        zeroImaginary = Array(repeating: 0, count: analysis.nFFT)
        recentSamples = Array(repeating: 0, count: windowSampleCount)
        downsampleBuffer.reserveCapacity(max(1, Int(48_000 / max(analysis.sampleRate, 1))))
    }

    var isAvailable: Bool {
        model != nil
    }

    func reset() {
        lock.lock()
        recentSamples = Array(repeating: 0, count: windowSampleCount)
        recentSampleWriteIndex = 0
        recentSampleCount = 0
        downsampleBuffer.removeAll(keepingCapacity: true)
        cachedPrediction = AudioSemanticPrediction()
        lastPredictionTime = 0
        lock.unlock()
    }

    func process(monoSamples: [Float], sourceSampleRate: Float) -> AudioSemanticPrediction? {
        lock.lock()
        defer { lock.unlock() }

        guard let model, let dft else { return nil }
        appendDownsampled(samples: monoSamples, sourceSampleRate: sourceSampleRate, targetSampleRate: Float(model.analysis.sampleRate))
        guard recentSampleCount >= windowSampleCount else { return cachedPrediction.isAvailable ? cachedPrediction : nil }

        let now = CACurrentMediaTime()
        if cachedPrediction.isAvailable, now - lastPredictionTime < runtimeUpdateInterval {
            return cachedPrediction
        }

        guard let featureVector = buildFeatureVector(using: model, dft: dft) else {
            return cachedPrediction.isAvailable ? cachedPrediction : nil
        }

        guard let prediction = model.predict(rawFeatureVector: featureVector) else {
            return cachedPrediction.isAvailable ? cachedPrediction : nil
        }

        cachedPrediction = prediction
        lastPredictionTime = now
        return prediction
    }

    private func appendDownsampled(samples: [Float], sourceSampleRate: Float, targetSampleRate: Float) {
        let ratio = max(1, Int(round(sourceSampleRate / max(targetSampleRate, 1))))
        for sample in samples {
            downsampleBuffer.append(sample)
            if downsampleBuffer.count >= ratio {
                let averaged = downsampleBuffer.reduce(0, +) / Float(downsampleBuffer.count)
                pushRecentSample(averaged)
                downsampleBuffer.removeAll(keepingCapacity: true)
            }
        }
    }

    private func pushRecentSample(_ sample: Float) {
        recentSamples[recentSampleWriteIndex] = sample
        recentSampleWriteIndex = (recentSampleWriteIndex + 1) % recentSamples.count
        recentSampleCount = min(recentSampleCount + 1, recentSamples.count)
    }

    private func buildFeatureVector(
        using model: AudioSemanticModelRuntime,
        dft: vDSP.DiscreteFourierTransform<Float>
    ) -> [Float]? {
        let analysis = model.analysis
        let samples = latestWindowSamples()
        guard samples.count >= analysis.winLength else { return nil }

        let frameCount = 1 + max(0, (samples.count - analysis.winLength) / analysis.hopLength)
        guard frameCount > 0 else { return nil }

        var melSums = Array(repeating: Float.zero, count: analysis.nMels)
        var melSquaredSums = Array(repeating: Float.zero, count: analysis.nMels)
        var melMaximums = Array(repeating: -Float.greatestFiniteMagnitude, count: analysis.nMels)
        var previousLogMel = Array(repeating: Float.zero, count: analysis.nMels)
        var hasPreviousLogMel = false

        var rmsSum: Float = 0
        var rmsSquaredSum: Float = 0
        var rmsMax: Float = 0
        var fluxSum: Float = 0
        var fluxMax: Float = 0
        var lowBandSum: Float = 0
        var lowBandSquaredSum: Float = 0
        var midBandSum: Float = 0
        var midBandSquaredSum: Float = 0
        var highBandSum: Float = 0
        var highBandSquaredSum: Float = 0

        var fftInputReal = Array(repeating: Float.zero, count: analysis.nFFT)
        var fftOutputReal = Array(repeating: Float.zero, count: analysis.nFFT)
        var fftOutputImag = Array(repeating: Float.zero, count: analysis.nFFT)
        var powerSpectrum = Array(repeating: Float.zero, count: spectrumBinCount)

        for frameIndex in 0 ..< frameCount {
            let sampleOffset = frameIndex * analysis.hopLength
            for index in 0 ..< analysis.nFFT {
                fftInputReal[index] = 0
            }
            for index in 0 ..< analysis.winLength {
                fftInputReal[index] = samples[sampleOffset + index] * analysis.analysisWindow[index]
            }

            dft.transform(
                inputReal: fftInputReal,
                inputImaginary: zeroImaginary,
                outputReal: &fftOutputReal,
                outputImaginary: &fftOutputImag
            )

            var powerSum: Float = 0
            var lowBandPower: Float = 0
            var midBandPower: Float = 0
            var highBandPower: Float = 0

            for binIndex in 0 ..< spectrumBinCount {
                let real = fftOutputReal[binIndex]
                let imaginary = fftOutputImag[binIndex]
                // Match scipy.signal.stft(..., scaling="spectrum"), which normalizes
                // the complex spectrum by the analysis-window sum before power.
                let power = ((real * real) + (imaginary * imaginary)) / stftPowerScale
                powerSpectrum[binIndex] = power
                powerSum += power
                if binIndex < lowBandUpperBound {
                    lowBandPower += power
                } else if binIndex < midBandUpperBound {
                    midBandPower += power
                } else {
                    highBandPower += power
                }
            }

            let rms = sqrt(max(powerSum / Float(spectrumBinCount), 1e-8))
            rmsSum += rms
            rmsSquaredSum += rms * rms
            rmsMax = max(rmsMax, rms)

            let lowBand = log((lowBandPower / Float(max(lowBandUpperBound, 1))) + 1e-6)
            let midBand = log((midBandPower / Float(max(midBandUpperBound - lowBandUpperBound, 1))) + 1e-6)
            let highBand = log((highBandPower / Float(max(spectrumBinCount - midBandUpperBound, 1))) + 1e-6)

            lowBandSum += lowBand
            lowBandSquaredSum += lowBand * lowBand
            midBandSum += midBand
            midBandSquaredSum += midBand * midBand
            highBandSum += highBand
            highBandSquaredSum += highBand * highBand

            var positiveDeltaEnergy: Float = 0
            for melIndex in 0 ..< analysis.nMels {
                let rowOffset = melIndex * analysis.melFilterbankColumns
                var melPower: Float = 0
                for binIndex in 0 ..< analysis.melFilterbankColumns {
                    melPower += analysis.melFilterbank[rowOffset + binIndex] * powerSpectrum[binIndex]
                }
                let logMel = log(melPower + 1e-6)
                melSums[melIndex] += logMel
                melSquaredSums[melIndex] += logMel * logMel
                melMaximums[melIndex] = max(melMaximums[melIndex], logMel)
                if hasPreviousLogMel {
                    positiveDeltaEnergy += max(logMel - previousLogMel[melIndex], 0)
                }
                previousLogMel[melIndex] = logMel
            }

            let spectralFlux = hasPreviousLogMel ? sqrt(positiveDeltaEnergy) : 0
            fluxSum += spectralFlux
            fluxMax = max(fluxMax, spectralFlux)
            hasPreviousLogMel = true
        }

        let frameCountValue = Float(frameCount)
        var featureVector: [Float] = []
        featureVector.reserveCapacity(model.analysis.inputDimension)

        for melIndex in 0 ..< analysis.nMels {
            featureVector.append(melSums[melIndex] / frameCountValue)
        }
        for melIndex in 0 ..< analysis.nMels {
            let mean = melSums[melIndex] / frameCountValue
            let variance = max((melSquaredSums[melIndex] / frameCountValue) - (mean * mean), 0)
            featureVector.append(sqrt(variance))
        }
        for melIndex in 0 ..< analysis.nMels {
            featureVector.append(melMaximums[melIndex])
        }

        let durationSeconds = Float(samples.count) / Float(analysis.sampleRate)
        let rmsMean = rmsSum / frameCountValue
        let rmsVariance = max((rmsSquaredSum / frameCountValue) - (rmsMean * rmsMean), 0)
        let lowBandMean = lowBandSum / frameCountValue
        let lowBandVariance = max((lowBandSquaredSum / frameCountValue) - (lowBandMean * lowBandMean), 0)
        let midBandMean = midBandSum / frameCountValue
        let midBandVariance = max((midBandSquaredSum / frameCountValue) - (midBandMean * midBandMean), 0)
        let highBandMean = highBandSum / frameCountValue
        let highBandVariance = max((highBandSquaredSum / frameCountValue) - (highBandMean * highBandMean), 0)

        featureVector.append(contentsOf: [
            durationSeconds,
            rmsMean,
            sqrt(rmsVariance),
            rmsMax,
            fluxSum / frameCountValue,
            fluxMax,
            lowBandMean,
            midBandMean,
            highBandMean,
            sqrt(lowBandVariance),
            sqrt(midBandVariance),
            sqrt(highBandVariance),
        ])

        return featureVector.count == model.analysis.inputDimension ? featureVector : nil
    }

    private func latestWindowSamples() -> [Float] {
        let count = min(recentSampleCount, recentSamples.count)
        guard count > 0 else { return [] }
        let startIndex = (recentSampleWriteIndex - count + recentSamples.count) % recentSamples.count
        if startIndex + count <= recentSamples.count {
            return Array(recentSamples[startIndex ..< startIndex + count])
        }
        let head = recentSamples[startIndex ..< recentSamples.count]
        let tail = recentSamples[0 ..< (count - head.count)]
        return Array(head + tail)
    }
}

private struct AudioSemanticModelAsset: Decodable {
    let inputDimension: Int
    let analysis: AudioSemanticAnalysisConfiguration
    let dominantSourceVocab: [String]
    let featureMean: [Float]
    let featureStd: [Float]
    let linear1: AudioSemanticLinearLayer
    let layerNorm1: AudioSemanticLayerNorm
    let linear2: AudioSemanticLinearLayer
    let heads: AudioSemanticHeads
}

nonisolated struct AudioSemanticAnalysisConfiguration: Decodable, Sendable {
    let sampleRate: Int
    let nFFT: Int
    let winLength: Int
    let hopLength: Int
    let nMels: Int
    let analysisWindowSeconds: Float
    let runtimeUpdateIntervalSeconds: Float
    let analysisWindow: [Float]
    let melFilterbankRows: Int
    let melFilterbankColumns: Int
    let melFilterbank: [Float]

    var inputDimension: Int {
        (nMels * 3) + 12
    }

    static let fallback = AudioSemanticAnalysisConfiguration(
        sampleRate: 16_000,
        nFFT: 512,
        winLength: 400,
        hopLength: 160,
        nMels: 48,
        analysisWindowSeconds: 1,
        runtimeUpdateIntervalSeconds: 0.12,
        analysisWindow: Array(repeating: 1, count: 400),
        melFilterbankRows: 48,
        melFilterbankColumns: 257,
        melFilterbank: Array(repeating: 0, count: 48 * 257)
    )
}

private struct AudioSemanticLinearLayer: Decodable {
    let rows: Int
    let columns: Int
    let weights: [Float]
    let bias: [Float]
}

private struct AudioSemanticLayerNorm: Decodable {
    let dimension: Int
    let weight: [Float]
    let bias: [Float]
    let epsilon: Float
}

private struct AudioSemanticHeads: Decodable {
    let dominantSource: AudioSemanticLinearLayer
    let musicSuppress: AudioSemanticLinearLayer
    let impactStrength: AudioSemanticLinearLayer
    let movementStrength: AudioSemanticLinearLayer
    let sustainStrength: AudioSemanticLinearLayer

    private enum CodingKeys: String, CodingKey {
        case dominantSource = "dominant_source"
        case musicSuppress = "music_suppress"
        case impactStrength = "impact_strength"
        case movementStrength = "movement_strength"
        case sustainStrength = "sustain_strength"
    }
}
