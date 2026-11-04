// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac

@MainActor private final class PermissionObservations: NativeTriggerObservations {
    var state: TriggerPermissionState = .notDetermined
    var locationRequests = 0
    var bluetoothRequests = 0
    var settings: [TriggerKind] = []
    override func permissionState(for kind: TriggerKind) -> TriggerPermissionState { state }
    override func requestLocationAuthorization() { locationRequests += 1 }
    override func requestBluetoothAuthorization() { bluetoothRequests += 1 }
    override func openPermissionSettings(for kind: TriggerKind) { settings.append(kind) }
}

@MainActor final class TriggerPermissionTests: XCTestCase {
    func testLocationAuthorizationKeepsOneManagerForObservationAndRequests() {
        let source = NativeTriggerObservations()
        let initial = source.locationAuthorizationManager()
        _ = source.permissionState(for: .wifiSSID)
        XCTAssertTrue(initial === source.locationAuthorizationManager())
    }
    func testDeniedPermissionsOpenSettingsWithoutRequestingAgain() {
        for state in [TriggerPermissionState.denied, .restricted] {
            let source = PermissionObservations(); source.state = state
            source.requestPermission(for: .wifiSSID)
            source.requestPermission(for: .bluetoothDevice)
            XCTAssertEqual(source.settings, [.wifiSSID, .bluetoothDevice])
            XCTAssertEqual(source.locationRequests, 0)
            XCTAssertEqual(source.bluetoothRequests, 0)
        }
    }
    func testAuthorizedPermissionsDoNotRequestAgain() {
        let source = PermissionObservations(); source.state = .authorized
        source.requestPermission(for: .wifiSSID)
        source.requestPermission(for: .bluetoothDevice)
        XCTAssertEqual(source.locationRequests, 0)
        XCTAssertEqual(source.bluetoothRequests, 0)
        XCTAssertTrue(source.settings.isEmpty)
    }
    func testUndeterminedPermissionsRequestTheirOwnSystemPrompt() {
        let source = PermissionObservations()
        source.requestPermission(for: .wifiSSID)
        source.requestPermission(for: .bluetoothDevice)
        XCTAssertEqual(source.locationRequests, 1)
        XCTAssertEqual(source.bluetoothRequests, 1)
        XCTAssertTrue(source.settings.isEmpty)
    }
}
