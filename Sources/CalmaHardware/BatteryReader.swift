import CalmaKit
import Foundation
import IOKit
import IOKit.ps

/// Reads battery and adapter telemetry. Needs no special privileges.
///
/// Sources, in order of preference:
/// 1. `AppleSmartBattery` in the IORegistry (percentages, capacities, cycle count, adapter, power telemetry)
/// 2. SMC read-only keys for temperature (macOS 27 no longer publishes `Temperature` in the registry)
public final class BatteryReader {
    private let smc: SMCAccess?

    public init(smc: SMCAccess? = try? SMCConnection()) {
        self.smc = smc
    }

    public func read() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return Self.snapshot(from: props, temperature: readTemperature())
    }

    /// Builds a snapshot from registry properties. Separated out so it can be tested with fixtures.
    public static func snapshot(from props: [String: Any], temperature smcTemperature: Double?) -> BatterySnapshot? {
        let batteryData = props["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String, _ dict: [String: Any]? = nil) -> Int? {
            let source = dict ?? props
            if let number = source[key] as? NSNumber { return number.intValue }
            return nil
        }
        func bool(_ key: String) -> Bool? {
            if let value = props[key] as? Bool { return value }
            if let number = props[key] as? NSNumber { return number.boolValue }
            return nil
        }

        guard let current = int("CurrentCapacity"), let max = int("MaxCapacity"), max > 0 else { return nil }
        // On Apple Silicon MaxCapacity is 100 and CurrentCapacity is already a percentage.
        let percentage = max == 100 ? current : Int((Double(current) / Double(max) * 100).rounded())

        // Raw percentage from the gas gauge: prefer AppleRaw*, fall back to BatteryData capacities.
        var hardware: Int?
        if let raw = int("AppleRawCurrentCapacity"), let rawMax = int("AppleRawMaxCapacity"), rawMax > 0 {
            hardware = Int((Double(raw) / Double(rawMax) * 100).rounded(.down))
        } else if let remaining = int("RemainingCapacity", batteryData), let full = int("FullChargeCapacity", batteryData), full > 0 {
            hardware = Int((Double(remaining) / Double(full) * 100).rounded(.down))
        }

        var temperature = smcTemperature
        if temperature == nil, let centi = int("Temperature") ?? int("VirtualTemperature") {
            temperature = Double(centi) / 100
        }

        let adapter = props["AdapterDetails"] as? [String: Any]
        let telemetry = props["PowerTelemetryData"] as? [String: Any]
        let systemPowerIn = (telemetry?["SystemPowerIn"] as? NSNumber).map { $0.doubleValue / 1000 }
        let systemLoad = (telemetry?["SystemLoad"] as? NSNumber).map { $0.doubleValue / 1000 }

        // Amperage is published as an unsigned 64-bit value in some releases; reinterpret as signed.
        var amperage: Int?
        if let number = props["Amperage"] as? NSNumber {
            amperage = Int(truncatingIfNeeded: Int64(bitPattern: number.uint64Value))
        }

        return BatterySnapshot(
            percentage: percentage,
            hardwarePercentage: hardware,
            isPluggedIn: bool("ExternalConnected") ?? false,
            isCharging: bool("IsCharging") ?? false,
            temperature: temperature,
            cycleCount: int("CycleCount"),
            designCapacity: int("DesignCapacity") ?? int("DesignCapacity", batteryData),
            fullChargeCapacity: int("AppleRawMaxCapacity") ?? int("FullChargeCapacity", batteryData) ?? int("NominalChargeCapacity"),
            voltage: int("Voltage"),
            amperage: amperage,
            adapterWatts: (adapter?["Watts"] as? NSNumber)?.intValue,
            systemPowerIn: systemPowerIn,
            systemLoad: systemLoad
        )
    }

    private func readTemperature() -> Double? {
        guard let smc else { return nil }
        let readings = SMCKey.batteryTemperatureKeys.compactMap { try? smc.read($0).doubleValue }
            .filter { $0 > 0 && $0 < 100 }
        guard !readings.isEmpty else { return nil }
        return readings.max()
    }
}

/// Posts a callback whenever macOS reports a power source change (plug, unplug, percentage).
public final class PowerSourceObserver {
    private var runLoopSource: CFRunLoopSource?
    private let handler: () -> Void

    public init(handler: @escaping () -> Void) {
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue().handler()
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    deinit {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
    }
}
