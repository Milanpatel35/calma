import CalmaHardware
import CalmaKit
import Foundation

// `calma` — command-line control for Calma. Talks to calmad over its local socket.

let usage = """
calma \(CalmaVersion.current) — keep your MacBook's battery calm

USAGE
  calma status                 Current battery, limit and mode
  calma json                   Full status as JSON (for scripts and Shortcuts)
  calma limit <20-100>         Set the charge limit
  calma pause | resume         Pause or resume charging
  calma fullcharge             Charge to 100% once; reverts when you unplug
  calma drain <20-100>         Run from battery while plugged in, down to a level
  calma recalibrate            100% → 10% → 100% → hold 1 h → back to your limit
  calma cancel                 End full charge / drain / recalibration
  calma drift on [1-20] | off  Drift Range: resume charging only N% below the limit
  calma heat on [25-50] | off  Heat Guard: pause charging above a temperature (°C)
  calma autodrain on | off     Drain automatically when above the limit
  calma truepercent on | off   Use the battery controller's raw percentage
  calma sleep on | off         Pause charging while the Mac sleeps
  calma awake on | off         Keep the Mac awake until it reaches the limit
  calma keep on | off          Keep enforcing the limit when the app is closed
  calma led system|status|off  MagSafe light behaviour
  calma lowpower on | off      macOS Low Power Mode
  calma highpower on | off     macOS High Power Mode (supported Macs only)
  calma reset                  Emergency reset: restore stock charging everywhere
  calma probe                  Read-only dump of charge-related SMC keys (no helper needed)
  calma version

Changing settings requires an administrator account.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("calma: \(message)\n".utf8))
    exit(1)
}

func send(_ command: CalmaCommand) -> CalmaResponse {
    do {
        let response = try CalmaClient.send(command)
        guard response.ok else { fail(response.error ?? "request failed") }
        return response
    } catch {
        fail("\(error)")
    }
}

func currentSettings() -> CalmaSettings {
    guard let status = send(.status).status else { fail("calmad returned no status") }
    return status.settings
}

func update(_ change: (inout CalmaSettings) -> Void) {
    var settings = currentSettings()
    change(&settings)
    let response = send(.updateSettings(settings))
    print(response.message ?? "OK")
}

func parseSwitch(_ value: String?) -> Bool {
    switch value?.lowercased() {
    case "on", "true", "yes", "1": return true
    case "off", "false", "no", "0": return false
    default: fail("expected on or off\n\n\(usage)")
    }
}

func parseInt(_ value: String?, _ range: ClosedRange<Int>) -> Int {
    guard let value, let number = Int(value.trimmingCharacters(in: CharacterSet(charactersIn: "%"))), range.contains(number) else {
        fail("expected a number between \(range.lowerBound) and \(range.upperBound)")
    }
    return number
}

func printStatus(_ status: CalmaStatus) {
    let b = status.battery
    let s = status.settings
    func onOff(_ flag: Bool) -> String { flag ? "on" : "off" }
    print("Battery        \(b.percentage)%" + (b.hardwarePercentage.map { "  (true \($0)%)" } ?? ""))
    print("State          \(status.summary)")
    print("Power          \(b.isPluggedIn ? "adapter" + (b.adapterWatts.map { " \($0) W" } ?? "") : "battery")")
    if let temperature = b.temperature { print(String(format: "Temperature    %.1f °C", temperature)) }
    if let health = b.health { print("Health         \(health)%" + (b.cycleCount.map { " · \($0) cycles" } ?? "")) }
    print("Charge limit   \(s.chargeLimit)%" + (s.driftRangeEnabled ? "  (drift range \(s.driftRange)%)" : ""))
    print("Heat Guard     \(s.heatGuardEnabled ? String(format: "on at %.0f °C", s.heatGuardThreshold) : "off")")
    print("Auto Drain     \(onOff(s.autoDrain))   Pause on Sleep \(onOff(s.pauseChargingOnSleep))   Keep After Quit \(onOff(s.keepLimitWhenAppClosed))")
    print("Hardware       \(status.capabilities.modelIdentifier) · backend \(status.capabilities.backend.rawValue)")
    if status.capabilities.backend == .unsupported {
        print("\nThis Mac's firmware doesn't expose a documented charge-control key. Calma is in monitoring mode.")
        if let native = status.capabilities.nativeChargeLimit {
            print("macOS's built-in charge limit is \(native)% (System Settings → Battery).")
        }
    }
    if let user = status.lastChangedBy { print("Last change by \(user)") }
}

func probe() {
    guard let smc = try? SMCConnection() else { fail("AppleSMC is unavailable") }
    let reader = BatteryReader(smc: smc)
    let controller = ChargeController(smc: smc, modelIdentifier: MachineInfo.modelIdentifier, osVersion: MachineInfo.osVersion)
    let caps = controller.capabilities
    print("Model      \(caps.modelIdentifier)")
    print("macOS      \(caps.osVersion)")
    print("Backend    \(caps.backend.rawValue)  (inhibit: \(caps.canInhibitCharging), drain: \(caps.canDrain), MagSafe LED: \(caps.hasMagSafeLED))")
    if let native = caps.nativeChargeLimit { print("Native     macOS charge limit \(native)%") }
    if let battery = reader.read() {
        let truePercent = battery.hardwarePercentage.map(String.init) ?? "?"
        let temperature = battery.temperature.map { String(format: "%.1f °C", $0) } ?? "?"
        print("Battery    \(battery.percentage)% (true \(truePercent)%), plugged \(battery.isPluggedIn), temp \(temperature)")
    }
    print("")
    print("Known keys")
    for key in SMCKey.probeKeys + ["CHLT"] {
        if let value = try? smc.read(key) {
            let number = value.doubleValue.map { String(format: "  (%.1f)", $0) } ?? ""
            print("  \(key)  \(value.type)  \(value.hex)\(number)")
        } else {
            print("  \(key)  —")
        }
    }

    // Everything charge-related this firmware exposes — the most useful part of a hardware report.
    let prefixes = ["CH", "AC", "BC", "bf"]
    let related = smc.allKeys().filter { key in prefixes.contains { key.hasPrefix($0) } }
    print("\nCharge-related keys on this Mac (\(related.count))")
    for key in related {
        if let value = try? smc.read(key) {
            print("  \(key)  \(value.type)  \(value.hex)")
        } else {
            print("  \(key)  (not readable without privileges)")
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(0)
}
let argument = args.count > 1 ? args[1] : nil

switch command {
case "status":
    guard let status = send(.status).status else { fail("no status") }
    printStatus(status)
case "json":
    guard let status = send(.status).status else { fail("no status") }
    let encoder = CalmaJSON.encoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try encoder.encode(status), encoding: .utf8) ?? "{}")
case "limit":
    print(send(.setChargeLimit(parseInt(argument, CalmaLimits.minimumChargeLimit...100))).message ?? "OK")
case "pause":
    print(send(.setChargingPaused(true)).message ?? "OK")
case "resume":
    print(send(.setChargingPaused(false)).message ?? "OK")
case "fullcharge", "full":
    print(send(.startFullCharge).message ?? "OK")
case "drain":
    print(send(.startDrain(target: parseInt(argument, CalmaLimits.minimumChargeLimit...100))).message ?? "OK")
case "recalibrate":
    print(send(.startRecalibration).message ?? "OK")
case "cancel":
    print(send(.cancelMode).message ?? "OK")
case "drift":
    let enabled = parseSwitch(argument)
    let range = args.count > 2 ? parseInt(args[2], 1...20) : nil
    update { $0.driftRangeEnabled = enabled; if let range { $0.driftRange = range } }
case "heat":
    let enabled = parseSwitch(argument)
    let threshold = args.count > 2 ? parseInt(args[2], 25...50) : nil
    update { $0.heatGuardEnabled = enabled; if let threshold { $0.heatGuardThreshold = Double(threshold) } }
case "autodrain":
    let enabled = parseSwitch(argument)
    update { $0.autoDrain = enabled }
case "truepercent":
    let enabled = parseSwitch(argument)
    update { $0.useHardwarePercentage = enabled }
case "sleep":
    let enabled = parseSwitch(argument)
    update { $0.pauseChargingOnSleep = enabled }
case "awake":
    let enabled = parseSwitch(argument)
    update { $0.stayAwakeUntilLimit = enabled }
case "keep":
    let enabled = parseSwitch(argument)
    update { $0.keepLimitWhenAppClosed = enabled }
case "led":
    guard let argument, let mode = MagSafeLEDMode(rawValue: argument) else { fail("expected system, status or off") }
    update { $0.magSafeLED = mode }
case "lowpower":
    print(send(.setLowPowerMode(parseSwitch(argument))).message ?? "OK")
case "highpower":
    print(send(.setHighPowerMode(parseSwitch(argument))).message ?? "OK")
case "reset":
    print(send(.emergencyReset).message ?? "OK")
case "probe":
    probe()
case "version", "--version", "-v":
    print("calma \(CalmaVersion.current)")
case "help", "--help", "-h":
    print(usage)
default:
    fail("unknown command \"\(command)\"\n\n\(usage)")
}
