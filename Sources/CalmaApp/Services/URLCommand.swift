import CalmaKit
import Foundation

/// Parses `calma://` URLs into daemon commands. Used by Shortcuts ("Open URL") and scripts.
///
///     calma://limit/80      calma://fullcharge   calma://drain/60
///     calma://pause         calma://resume       calma://recalibrate
///     calma://cancel        calma://reset
enum URLCommand {
    static func command(for url: URL, currentSettings: CalmaSettings?) -> CalmaCommand? {
        guard url.scheme?.lowercased() == "calma" else { return nil }
        let action = (url.host ?? "").lowercased()
        let argument = url.pathComponents.first(where: { $0 != "/" }).flatMap { Int($0) }

        switch action {
        case "limit":
            guard let value = argument else { return nil }
            return .setChargeLimit(value)
        case "fullcharge", "full-charge":
            return .startFullCharge
        case "drain":
            guard let value = argument ?? currentSettings?.chargeLimit else { return nil }
            return .startDrain(target: value)
        case "pause":
            return .setChargingPaused(true)
        case "resume":
            return .setChargingPaused(false)
        case "recalibrate":
            return .startRecalibration
        case "cancel":
            return .cancelMode
        case "reset":
            return .emergencyReset
        default:
            return nil
        }
    }
}
