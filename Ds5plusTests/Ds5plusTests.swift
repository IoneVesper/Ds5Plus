import XCTest
@testable import Ds5plus

final class Ds5plusTests: XCTestCase {
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
}
