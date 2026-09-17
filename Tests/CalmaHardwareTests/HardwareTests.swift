@testable import CalmaHardware
import CalmaKit
import XCTest

final class AllowlistTests: XCTestCase {
    func testRefusesKeysOutsideAllowlist() {
        let fake = FakeSMC(keys: ["F0Tg": SMCValue(bytes: [0, 0, 0, 0], type: "flt "), "CHTE": SMCValue(bytes: [0, 0, 0, 0], type: "ui32")])
        let guarded = AllowlistedSMC(fake)
        XCTAssertThrowsError(try guarded.write("F0Tg", SMCValue(bytes: [1, 1, 1, 1]))) { error in
            XCTAssertEqual(error as? SMCError, .notAllowed("F0Tg"))
        }
        XCTAssertNoThrow(try guarded.write("CHTE", SMCValue(bytes: [1, 0, 0, 0])))
        XCTAssertEqual(fake.writes.count, 1)
    }

    func testAllowlistIsExactlyTheDocumentedKeys() {
        XCTAssertEqual(SMCKey.writeAllowlist, ["CH0B", "CH0C", "CHTE", "CH0I", "CHIE", "BCLM", "ACLC"])
    }
}

final class ChargeControllerTests: XCTestCase {
    func testDetectsModernBackend() {
        let controller = ChargeController(smc: FakeSMC.modernAppleSilicon())
        XCTAssertEqual(controller.capabilities.backend, .appleSiliconModern)
        XCTAssertTrue(controller.capabilities.canDrain)
        XCTAssertTrue(controller.capabilities.hasMagSafeLED)
    }

    func testDetectsLegacyBackend() {
        let controller = ChargeController(smc: FakeSMC.legacyAppleSilicon())
        XCTAssertEqual(controller.capabilities.backend, .appleSiliconLegacy)
        XCTAssertTrue(controller.capabilities.canDrain)
        XCTAssertFalse(controller.capabilities.hasMagSafeLED)
    }

    func testGoldenGateFirmwareIsMonitoringOnly() {
        let controller = ChargeController(smc: FakeSMC.goldenGate())
        XCTAssertEqual(controller.capabilities.backend, .unsupported)
        XCTAssertFalse(controller.capabilities.canInhibitCharging)
        XCTAssertFalse(controller.capabilities.canDrain)
        XCTAssertFalse(controller.capabilities.hasMagSafeLED)
        XCTAssertEqual(controller.capabilities.nativeChargeLimit, 80)
    }

    func testModernWritesAndIdempotence() throws {
        let fake = FakeSMC.modernAppleSilicon()
        let controller = ChargeController(smc: fake)
        var records: [ChargeController.WriteRecord] = []
        controller.onWrite = { records.append($0) }

        try controller.setChargingAllowed(false, reason: "test")
        try controller.setChargingAllowed(false, reason: "test")
        XCTAssertEqual(try fake.read("CHTE").bytes, [1, 0, 0, 0])
        XCTAssertEqual(records.count, 1, "Unchanged values aren't rewritten")

        try controller.setAdapterEnabled(false, reason: "drain")
        XCTAssertEqual(try fake.read("CHIE").bytes, [0x08])

        try controller.setLED(.green, reason: "led")
        XCTAssertEqual(try fake.read("ACLC").bytes, [0x03])

        XCTAssertTrue(controller.restoreDefaults(reason: "reset").isEmpty)
        XCTAssertEqual(try fake.read("CHTE").bytes, [0, 0, 0, 0])
        XCTAssertEqual(try fake.read("CHIE").bytes, [0])
        XCTAssertEqual(try fake.read("ACLC").bytes, [0])
    }

    func testLegacyWritesBothInhibitKeys() throws {
        let fake = FakeSMC.legacyAppleSilicon()
        let controller = ChargeController(smc: fake)
        try controller.setChargingAllowed(false, reason: "test")
        XCTAssertEqual(try fake.read("CH0B").bytes, [0x02])
        XCTAssertEqual(try fake.read("CH0C").bytes, [0x02])
        try controller.setAdapterEnabled(false, reason: "drain")
        XCTAssertEqual(try fake.read("CH0I").bytes, [0x01])
    }

    func testUnsupportedBackendNeverWrites() throws {
        let fake = FakeSMC.goldenGate()
        let controller = ChargeController(smc: fake)
        try controller.setChargingAllowed(false, reason: "test")
        try controller.setAdapterEnabled(false, reason: "test")
        try controller.setLED(.amber, reason: "test")
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testRestoreCollectsErrorsInsteadOfStopping() {
        let fake = FakeSMC.modernAppleSilicon()
        let controller = ChargeController(smc: fake)
        try? controller.setChargingAllowed(false, reason: "x")
        fake.failWrites = true
        XCTAssertFalse(controller.restoreDefaults(reason: "reset").isEmpty)
    }
}

final class SMCValueTests: XCTestCase {
    func testAppleSiliconFloat() {
        // 30.6 °C as observed on a Mac16,1.
        let value = SMCValue(bytes: [0xC8, 0xCC, 0xF4, 0x41], type: "flt ")
        XCTAssertEqual(value.doubleValue!, 30.6, accuracy: 0.01)
    }

    func testIntelSP78() {
        let value = SMCValue(bytes: [0x1E, 0x80], type: "sp78")
        XCTAssertEqual(value.doubleValue!, 30.5, accuracy: 0.01)
    }
}

final class BatteryReaderTests: XCTestCase {
    /// Registry layout observed on macOS 27 (no top-level Temperature / AppleRaw* keys).
    func testMacOS27RegistryLayout() {
        let props: [String: Any] = [
            "CurrentCapacity": NSNumber(value: 80),
            "MaxCapacity": NSNumber(value: 100),
            "ExternalConnected": true,
            "IsCharging": false,
            "CycleCount": NSNumber(value: 132),
            "Voltage": NSNumber(value: 12503),
            "Amperage": NSNumber(value: UInt64(bitPattern: -1200)),
            "BatteryData": ["FullChargeCapacity": NSNumber(value: 5626), "RemainingCapacity": NSNumber(value: 4445),
                            "DesignCapacity": NSNumber(value: 6249)],
            "AdapterDetails": ["Watts": NSNumber(value: 80)],
            "PowerTelemetryData": ["SystemPowerIn": NSNumber(value: 5684), "SystemLoad": NSNumber(value: 5684)],
        ]
        let snapshot = BatteryReader.snapshot(from: props, temperature: 30.6)!
        XCTAssertEqual(snapshot.percentage, 80)
        XCTAssertEqual(snapshot.hardwarePercentage, 79)
        XCTAssertTrue(snapshot.isPluggedIn)
        XCTAssertEqual(snapshot.cycleCount, 132)
        XCTAssertEqual(snapshot.designCapacity, 6249)
        XCTAssertEqual(snapshot.fullChargeCapacity, 5626)
        XCTAssertEqual(snapshot.health, 90)
        XCTAssertEqual(snapshot.amperage, -1200)
        XCTAssertEqual(snapshot.adapterWatts, 80)
        XCTAssertEqual(snapshot.systemPowerIn!, 5.684, accuracy: 0.001)
        XCTAssertEqual(snapshot.temperature, 30.6)
    }

    func testOlderRegistryLayout() {
        let props: [String: Any] = [
            "CurrentCapacity": NSNumber(value: 4000), "MaxCapacity": NSNumber(value: 5000),
            "AppleRawCurrentCapacity": NSNumber(value: 3900), "AppleRawMaxCapacity": NSNumber(value: 5000),
            "Temperature": NSNumber(value: 3050), "ExternalConnected": false,
        ]
        let snapshot = BatteryReader.snapshot(from: props, temperature: nil)!
        XCTAssertEqual(snapshot.percentage, 80)
        XCTAssertEqual(snapshot.hardwarePercentage, 78)
        XCTAssertEqual(snapshot.temperature, 30.5)
        XCTAssertFalse(snapshot.isPluggedIn)
    }

    func testLiveReadDoesNotCrash() {
        // On CI (no battery) this returns nil; on a MacBook it returns a sane percentage.
        if let snapshot = BatteryReader().read() {
            XCTAssertTrue((0...100).contains(snapshot.percentage))
        }
    }
}
