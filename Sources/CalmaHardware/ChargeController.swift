import CalmaKit
import Foundation

/// Translates engine decisions into SMC writes for the detected backend.
///
/// Only writes when the desired value differs from what we last wrote (or from what the key
/// currently holds), and reports every write so the daemon can log it.
public final class ChargeController {
    public struct WriteRecord: Equatable {
        public var key: String
        public var old: String
        public var new: String
        public var reason: String
    }

    public let capabilities: Capabilities
    private let smc: SMCAccess
    public var onWrite: ((WriteRecord) -> Void)?

    /// Intel Macs without CH0B/CH0C can only be limited through the BCLM ceiling.
    public let usesIntelCeilingOnly: Bool

    public init(smc: SMCAccess, modelIdentifier: String = "", osVersion: String = "") {
        self.smc = AllowlistedSMC(smc)
        self.capabilities = Self.detect(smc: smc, modelIdentifier: modelIdentifier, osVersion: osVersion)
        self.usesIntelCeilingOnly = capabilities.backend == .intel
            && !(smc.exists(SMCKey.chargeInhibitB) && smc.exists(SMCKey.chargeInhibitC))
    }

    // MARK: Detection

    public static func detect(smc: SMCAccess, modelIdentifier: String, osVersion: String) -> Capabilities {
        #if arch(x86_64)
        let isIntel = true
        #else
        let isIntel = false
        #endif

        let hasCHTE = smc.exists(SMCKey.chargeInhibitTE)
        let hasCH0B = smc.exists(SMCKey.chargeInhibitB)
        let hasCH0C = smc.exists(SMCKey.chargeInhibitC)
        let hasCH0I = smc.exists(SMCKey.adapterInhibitI)
        let hasCHIE = smc.exists(SMCKey.adapterInhibitIE)
        let hasBCLM = smc.exists(SMCKey.intelChargeLimit)
        let hasLED = !isIntel && smc.exists(SMCKey.magSafeLED)

        let backend: ChargeBackend
        let canDrain: Bool
        if isIntel, hasBCLM || (hasCH0B && hasCH0C) {
            backend = .intel
            canDrain = hasCH0I
        } else if hasCHTE {
            backend = .appleSiliconModern
            canDrain = hasCHIE || hasCH0I
        } else if hasCH0B && hasCH0C {
            backend = .appleSiliconLegacy
            canDrain = hasCH0I || hasCHIE
        } else {
            backend = .unsupported
            canDrain = false
        }

        return Capabilities(
            backend: backend,
            canInhibitCharging: backend != .unsupported,
            canDrain: canDrain,
            hasMagSafeLED: hasLED && backend != .unsupported,
            nativeChargeLimit: readNativeLimit(smc: smc),
            modelIdentifier: modelIdentifier,
            osVersion: osVersion
        )
    }

    /// macOS 26.4+ exposes its own charge-limit setting read-only; the first byte is the percentage.
    static func readNativeLimit(smc: SMCAccess) -> Int? {
        guard let value = try? smc.read("CHLT"), let first = value.bytes.first, (50...100).contains(first) else { return nil }
        return Int(first)
    }

    // MARK: Charging

    public func setChargingAllowed(_ allowed: Bool, reason: String) throws {
        switch capabilities.backend {
        case .appleSiliconModern:
            try writeIfNeeded(SMCKey.chargeInhibitTE, allowed ? [0, 0, 0, 0] : [1, 0, 0, 0], reason: reason)
        case .appleSiliconLegacy:
            try writeIfNeeded(SMCKey.chargeInhibitB, allowed ? [0x00] : [0x02], reason: reason)
            try writeIfNeeded(SMCKey.chargeInhibitC, allowed ? [0x00] : [0x02], reason: reason)
        case .intel:
            // BCLM-only Macs are limited through `setIntelCeiling` instead; it's a ceiling, not a switch.
            guard !usesIntelCeilingOnly else { return }
            try writeIfNeeded(SMCKey.chargeInhibitB, allowed ? [0x00] : [0x02], reason: reason)
            try writeIfNeeded(SMCKey.chargeInhibitC, allowed ? [0x00] : [0x02], reason: reason)
        case .unsupported:
            return
        }
    }

    /// Intel BCLM path: hardware-enforced ceiling that also survives the daemon stopping.
    public func setIntelCeiling(_ percent: Int, reason: String) throws {
        guard capabilities.backend == .intel, smc.exists(SMCKey.intelChargeLimit) else { return }
        try writeIfNeeded(SMCKey.intelChargeLimit, [UInt8(min(100, max(20, percent)))], reason: reason)
    }

    // MARK: Adapter

    public func setAdapterEnabled(_ enabled: Bool, reason: String) throws {
        guard capabilities.canDrain else { return }
        if smc.exists(SMCKey.adapterInhibitIE) {
            try writeIfNeeded(SMCKey.adapterInhibitIE, enabled ? [0x00] : [0x08], reason: reason)
        } else if smc.exists(SMCKey.adapterInhibitI) {
            try writeIfNeeded(SMCKey.adapterInhibitI, enabled ? [0x00] : [0x01], reason: reason)
        }
    }

    // MARK: MagSafe

    public func setLED(_ value: MagSafeLEDValue, reason: String) throws {
        guard capabilities.hasMagSafeLED else { return }
        try writeIfNeeded(SMCKey.magSafeLED, [value.rawValue], reason: reason)
    }

    // MARK: Reset

    /// Returns every key Calma touches to stock behaviour. Collects errors instead of stopping at the first.
    @discardableResult
    public func restoreDefaults(reason: String) -> [Error] {
        var errors: [Error] = []
        func attempt(_ body: () throws -> Void) {
            do { try body() } catch { errors.append(error) }
        }
        attempt { try setAdapterEnabled(true, reason: reason) }
        attempt { try setChargingAllowed(true, reason: reason) }
        attempt { try setIntelCeiling(100, reason: reason) }
        attempt { try setLED(.system, reason: reason) }
        return errors
    }

    // MARK: Probe

    /// Reads every known key. Safe without root.
    public func probe() -> [String: String] {
        var result: [String: String] = [:]
        for key in SMCKey.probeKeys {
            if let value = try? smc.read(key) {
                result[key] = "\(value.type.trimmingCharacters(in: .whitespaces)):\(value.hex)"
            }
        }
        return result
    }

    // MARK: Internals

    private func writeIfNeeded(_ key: String, _ bytes: [UInt8], reason: String) throws {
        let current = try smc.read(key)
        guard current.bytes != bytes else { return }
        guard current.bytes.count == bytes.count else {
            throw SMCError.writeFailed(key, -1)
        }
        try smc.write(key, SMCValue(bytes: bytes, type: current.type))
        onWrite?(WriteRecord(key: key, old: current.hex, new: SMCValue(bytes: bytes).hex, reason: reason))
    }
}
