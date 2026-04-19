import XCTest
import CoreGraphics
@testable import Ds5plus

final class Ds5plusTests: XCTestCase {
    @MainActor
    func testInitBootstrapsDeviceAndDisplayDiscovery() async {
        let hidService = HIDServiceSpy()
        let audioEngine = AudioEngineSpy()
        let suiteName = "Ds5plusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedDevice = DualSenseDeviceInfo(
            id: "device-a",
            name: "DualSense Wireless Controller",
            serialNumber: "AA-BB",
            transport: "Bluetooth",
            productID: 0x0CE6
        )
        let expectedDisplay = CaptureDisplay(id: 7, width: 2560, height: 1440)
        hidService.devicesSnapshot = [expectedDevice]
        audioEngine.refreshDisplaysResult = .success([expectedDisplay])

        let devicesExpectation = expectation(description: "refreshes devices on launch")
        let displaysExpectation = expectation(description: "refreshes displays on launch")
        hidService.onRefreshDevicesSnapshotHook = { devicesExpectation.fulfill() }
        audioEngine.onRefreshDisplaysHook = { displaysExpectation.fulfill() }

        let model = AppViewModel(
            hidService: hidService,
            audioEngine: audioEngine,
            userDefaults: defaults,
            autoBootstrap: true
        )

        _ = model
        await fulfillment(of: [devicesExpectation, displaysExpectation], timeout: 1.0)

        XCTAssertEqual(model.selectedDeviceID, expectedDevice.id)
        XCTAssertEqual(model.selectedDisplayID, expectedDisplay.id)
        XCTAssertEqual(hidService.refreshDevicesSnapshotCallCount, 1)
        XCTAssertEqual(audioEngine.refreshDisplaysCallCount, 1)
    }

    @MainActor
    func testChangingSelectedDeviceWhileRunningRebindsRealtimeSession() async {
        let hidService = HIDServiceSpy()
        let audioEngine = AudioEngineSpy()
        let suiteName = "Ds5plusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let deviceA = DualSenseDeviceInfo(
            id: "device-a",
            name: "DualSense Wireless Controller",
            serialNumber: "AA-BB",
            transport: "Bluetooth",
            productID: 0x0CE6
        )
        let deviceB = DualSenseDeviceInfo(
            id: "device-b",
            name: "DualSense Edge Wireless Controller",
            serialNumber: "CC-DD",
            transport: "Bluetooth",
            productID: 0x0DF2
        )
        let display = CaptureDisplay(id: 11, width: 1920, height: 1080)
        hidService.devicesSnapshot = [deviceA, deviceB]
        audioEngine.refreshDisplaysResult = .success([display])

        let model = AppViewModel(
            hidService: hidService,
            audioEngine: audioEngine,
            userDefaults: defaults,
            autoBootstrap: true
        )

        await waitUntil("launch bootstrap finished") {
            hidService.refreshDevicesSnapshotCallCount == 1 &&
            audioEngine.refreshDisplaysCallCount == 1 &&
            model.selectedDeviceID == deviceA.id &&
            model.selectedDisplayID == display.id
        }

        model.startAudioReactive()

        await waitUntil("initial run started") {
            model.isRunning &&
            hidService.startRealtimeControlRequests == [deviceA.id] &&
            audioEngine.startDisplayRequests == [display.id]
        }

        model.selectedDeviceID = deviceB.id

        await waitUntil("session rebound to the newly selected device") {
            model.isRunning &&
            hidService.startRealtimeControlRequests == [deviceA.id, deviceB.id] &&
            audioEngine.startDisplayRequests == [display.id, display.id] &&
            hidService.stopEffectCallCount >= 1 &&
            audioEngine.stopCallCount >= 1
        }
    }

    @MainActor
    func testTrimmedLogDataPreservingUTF8ReturnsValidUTF8() {
        let repeatedLine = "[12:00:00] 你好，DualSense\n"
        let data = Data(String(repeating: repeatedLine, count: 32).utf8)

        let trimmed = AppViewModel.trimmedLogDataPreservingUTF8(data, limit: 127)

        XCTAssertLessThanOrEqual(trimmed.count, 127)
        XCTAssertNotNil(String(data: trimmed, encoding: .utf8))
    }

    @MainActor
    func testPreviewModelDisablesLiveServiceControls() {
        let model = AppViewModel.preview

        XCTAssertTrue(model.isPreviewMode)
        XCTAssertFalse(model.canRefreshServices)
        XCTAssertFalse(model.canToggleRun)
        XCTAssertEqual(model.statusLine, "预览模式")
    }

    func testBluetoothOutputReportIncludesExpectedFieldsAndChecksum() {
        let report = DualSenseBluetoothOutputReport(
            sequence: 0x0E,
            leftMotor: 160,
            rightMotor: 80,
            useVibrationV2: true,
            lightbar: (1, 2, 3),
            resetLightbar: false
        ).bytes

        XCTAssertEqual(report.count, 78)
        XCTAssertEqual(report[0], 0x31)
        XCTAssertEqual(report[1], 0xE0)
        XCTAssertEqual(report[2], 0x10)
        XCTAssertEqual(report[3], 0x02)
        XCTAssertEqual(report[4], 0x74)
        XCTAssertEqual(report[5], 80)
        XCTAssertEqual(report[6], 160)
        XCTAssertEqual(report[41], 0x06)
        XCTAssertEqual(report[42], 0x01)
        XCTAssertEqual(report[44], 0x02)
        XCTAssertEqual(report[46], 0b00100)
        XCTAssertEqual(report[47], 1)
        XCTAssertEqual(report[48], 2)
        XCTAssertEqual(report[49], 3)
        XCTAssertEqual(Array(report[74 ... 77]), [47, 78, 103, 203])
    }

    func testBluetoothOutputReportUsesLegacyVibrationFlagWhenV2IsDisabled() {
        let report = DualSenseBluetoothOutputReport(
            sequence: 0x01,
            leftMotor: 32,
            rightMotor: 64,
            useVibrationV2: false,
            lightbar: (9, 8, 7),
            resetLightbar: true
        ).bytes

        XCTAssertEqual(report[3], 0x03)
        XCTAssertEqual(report[4], 0x7C)
        XCTAssertEqual(report[41], 0x02)
        XCTAssertEqual(report[44], 0x01)
        XCTAssertEqual(report[47], 9)
        XCTAssertEqual(report[48], 8)
        XCTAssertEqual(report[49], 7)
    }

    @MainActor
    func testBatteryStatusByteMapsToPercentageAndChargingState() {
        let discharging = DualSenseHIDService.batteryStatus(fromBluetoothStatusByte: 0x05)
        XCTAssertEqual(discharging.percentage, 60)
        XCTAssertEqual(discharging.chargingState, .discharging)

        let charging = DualSenseHIDService.batteryStatus(fromBluetoothStatusByte: 0x1A)
        XCTAssertEqual(charging.percentage, 100)
        XCTAssertEqual(charging.chargingState, .charging)

        let full = DualSenseHIDService.batteryStatus(fromBluetoothStatusByte: 0x2A)
        XCTAssertEqual(full.percentage, 100)
        XCTAssertEqual(full.chargingState, .full)

        let unavailable = DualSenseHIDService.batteryStatus(fromBluetoothStatusByte: 0xAB)
        XCTAssertNil(unavailable.percentage)
        XCTAssertEqual(unavailable.chargingState, .notCharging)
    }

    func testAudioSemanticModelMatchesExportedReferencePrediction() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetURL = repoRoot
            .appendingPathComponent("Ds5plus")
            .appendingPathComponent("Resources")
            .appendingPathComponent("AudioSemanticModel.json")

        let runtime = try AudioSemanticModelRuntime(assetURL: assetURL)
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: assetURL)) as? [String: Any]
        let reference = try XCTUnwrap(payload?["reference"] as? [String: Any])
        let rawFeatureVector = try XCTUnwrap(reference["rawFeatureVector"] as? [NSNumber]).map(\.floatValue)
        let prediction = try XCTUnwrap(runtime.predict(rawFeatureVector: rawFeatureVector))

        let dominantProbabilities = try XCTUnwrap(reference["dominantSourceProbabilities"] as? [NSNumber]).map(\.floatValue)
        let musicSuppressExpected = try XCTUnwrap(reference["musicSuppressExpected"] as? NSNumber).floatValue
        let impactStrengthExpected = try XCTUnwrap(reference["impactStrengthExpected"] as? NSNumber).floatValue
        let movementStrengthExpected = try XCTUnwrap(reference["movementStrengthExpected"] as? NSNumber).floatValue
        let sustainStrengthExpected = try XCTUnwrap(reference["sustainStrengthExpected"] as? NSNumber).floatValue

        XCTAssertTrue(prediction.isAvailable)
        XCTAssertEqual(prediction.dominantImpact, dominantProbabilities[0], accuracy: 0.0001)
        XCTAssertEqual(prediction.dominantMixed, dominantProbabilities[1], accuracy: 0.0001)
        XCTAssertEqual(prediction.dominantMovement, dominantProbabilities[2], accuracy: 0.0001)
        XCTAssertEqual(prediction.dominantMusic, dominantProbabilities[3], accuracy: 0.0001)
        XCTAssertEqual(prediction.dominantSilence, dominantProbabilities[4], accuracy: 0.0001)
        XCTAssertEqual(prediction.musicSuppression, musicSuppressExpected, accuracy: 0.0001)
        XCTAssertEqual(prediction.impactStrength, impactStrengthExpected, accuracy: 0.0001)
        XCTAssertEqual(prediction.movementStrength, movementStrengthExpected, accuracy: 0.0001)
        XCTAssertEqual(prediction.sustainStrength, sustainStrengthExpected, accuracy: 0.0001)
    }

    func testAudioSemanticRealtimeAnalyzerMatchesRuntimeReference() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetURL = repoRoot
            .appendingPathComponent("Ds5plus")
            .appendingPathComponent("Resources")
            .appendingPathComponent("AudioSemanticModel.json")

        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: assetURL)) as? [String: Any]
        let runtimeReference = try XCTUnwrap(payload?["runtimeReference"] as? [String: Any])
        let sampleRate = try XCTUnwrap(runtimeReference["sampleRate"] as? NSNumber).floatValue
        let sampleCount = try XCTUnwrap(runtimeReference["sampleCount"] as? NSNumber).intValue
        let sineComponents = try XCTUnwrap(runtimeReference["sineComponents"] as? [[String: Any]])
        let impulseEnvelopes = try XCTUnwrap(runtimeReference["impulseEnvelopes"] as? [[String: Any]])
        let expected = try XCTUnwrap(runtimeReference["prediction"] as? [String: Any])

        var waveform = Array(repeating: Float.zero, count: sampleCount)
        for (index, _) in waveform.enumerated() {
            let time = Float(index) / sampleRate
            var sample: Float = 0
            for component in sineComponents {
                let amplitude = try XCTUnwrap(component["amplitude"] as? NSNumber).floatValue
                let frequency = try XCTUnwrap(component["frequencyHz"] as? NSNumber).floatValue
                sample += amplitude * sin(2 * .pi * frequency * time)
            }
            waveform[index] = sample
        }

        for envelope in impulseEnvelopes {
            let startSeconds = try XCTUnwrap(envelope["startSeconds"] as? NSNumber).floatValue
            let lengthSamples = try XCTUnwrap(envelope["lengthSamples"] as? NSNumber).intValue
            let peakAmplitude = try XCTUnwrap(envelope["peakAmplitude"] as? NSNumber).floatValue
            let startSample = Int((startSeconds * sampleRate).rounded())
            guard startSample < waveform.count else { continue }
            let endSample = min(waveform.count, startSample + lengthSamples)
            for offset in 0 ..< (endSample - startSample) {
                let progress = Float(offset) / Float(max(lengthSamples - 1, 1))
                waveform[startSample + offset] += peakAmplitude * (1 - progress)
            }
        }

        for index in waveform.indices {
            waveform[index] = min(max(waveform[index], -1), 1)
        }

        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSemanticModelTests-\(UUID().uuidString)")
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try FileManager.default.copyItem(
            at: assetURL,
            to: bundleURL.appendingPathComponent("AudioSemanticModel.json")
        )

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        let analyzer = AudioSemanticRealtimeAnalyzer(bundle: bundle)
        let prediction = try XCTUnwrap(analyzer.process(monoSamples: waveform, sourceSampleRate: sampleRate))

        XCTAssertEqual(prediction.dominantImpact, try XCTUnwrap(expected["dominantImpact"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.dominantMixed, try XCTUnwrap(expected["dominantMixed"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.dominantMovement, try XCTUnwrap(expected["dominantMovement"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.dominantMusic, try XCTUnwrap(expected["dominantMusic"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.dominantSilence, try XCTUnwrap(expected["dominantSilence"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.musicSuppression, try XCTUnwrap(expected["musicSuppression"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.impactStrength, try XCTUnwrap(expected["impactStrength"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.movementStrength, try XCTUnwrap(expected["movementStrength"] as? NSNumber).floatValue, accuracy: 0.001)
        XCTAssertEqual(prediction.sustainStrength, try XCTUnwrap(expected["sustainStrength"] as? NSNumber).floatValue, accuracy: 0.001)
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1.0,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        XCTFail("Timed out waiting for condition: \(description)")
    }

}

private final class HIDServiceSpy: DualSenseHIDServicing {
    var onDevicesChanged: @Sendable ([DualSenseDeviceInfo]) -> Void = { _ in }
    var onLog: @Sendable (String) -> Void = { _ in }
    var onStatsChanged: @Sendable (DriverStats) -> Void = { _ in }
    var onBatteryChanged: @Sendable (String, ControllerBatteryStatus) -> Void = { _, _ in }

    var devicesSnapshot: [DualSenseDeviceInfo] = []
    var refreshDevicesSnapshotCallCount = 0
    var refreshBatteryStatusRequests: [String] = []
    var startRealtimeControlRequests: [String] = []
    var sentRealtimeHaptics: [(UInt8, UInt8, (UInt8, UInt8, UInt8))] = []
    var previewLightbarRequests: [(String, (UInt8, UInt8, UInt8))] = []
    var stopEffectCallCount = 0
    var startRealtimeControlResult = true
    var onRefreshDevicesSnapshotHook: (() -> Void)?

    func refreshDevicesSnapshot() {
        refreshDevicesSnapshotCallCount += 1
        onRefreshDevicesSnapshotHook?()
        onDevicesChanged(devicesSnapshot)
    }

    func refreshBatteryStatus(deviceID: String) {
        refreshBatteryStatusRequests.append(deviceID)
    }

    func startRealtimeControl(deviceID: String) -> Bool {
        startRealtimeControlRequests.append(deviceID)
        return startRealtimeControlResult
    }

    func sendRealtimeHaptics(leftMotor: UInt8, rightMotor: UInt8, lightbar: (UInt8, UInt8, UInt8)) {
        sentRealtimeHaptics.append((leftMotor, rightMotor, lightbar))
    }

    func previewLightbar(deviceID: String, color: (UInt8, UInt8, UInt8)) {
        previewLightbarRequests.append((deviceID, color))
    }

    func stopEffect() {
        stopEffectCallCount += 1
    }
}

private final class AudioEngineSpy: SystemAudioHapticsEngining {
    var onLog: @Sendable (String) -> Void = { _ in }
    var onSample: @Sendable (AudioReactiveSample) -> Void = { _ in }
    var onCaptureStateChanged: @Sendable (Bool, String?) -> Void = { _, _ in }

    var refreshDisplaysResult: Result<[CaptureDisplay], Error> = .success([])
    var refreshDisplaysCallCount = 0
    var startDisplayRequests: [CGDirectDisplayID] = []
    var stopCallCount = 0
    var onRefreshDisplaysHook: (() -> Void)?

    func refreshDisplays() async throws -> [CaptureDisplay] {
        refreshDisplaysCallCount += 1
        onRefreshDisplaysHook?()
        return try refreshDisplaysResult.get()
    }

    func start(displayID: CGDirectDisplayID) async throws {
        startDisplayRequests.append(displayID)
    }

    func stop() {
        stopCallCount += 1
    }
}
