import CalmaHardware
import CalmaKit
import Foundation

// calmad — Calma's privileged helper.
//
//   calmad                         Normal operation (run by launchd as root).
//   calmad --simulate <profile>    Development: in-memory SMC, no hardware writes.
//        profiles: modern | legacy | goldengate
//        --level <n> --unplugged   Fake battery for the simulator.

let arguments = CommandLine.arguments
let log = DaemonLog()

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

if arguments.contains("--version") {
    print("calmad \(CalmaVersion.current)")
    exit(0)
}

let smc: SMCAccess?
var simulatedBattery: BatterySnapshot?

if let profile = value(after: "--simulate") {
    switch profile {
    case "legacy": smc = FakeSMC.legacyAppleSilicon()
    case "goldengate": smc = FakeSMC.goldenGate()
    default: smc = FakeSMC.modernAppleSilicon()
    }
    let level = Int(value(after: "--level") ?? "") ?? 85
    simulatedBattery = BatterySnapshot(percentage: level, hardwarePercentage: level - 2,
                                       isPluggedIn: !arguments.contains("--unplugged"), isCharging: false,
                                       temperature: 31.5, cycleCount: 120, designCapacity: 6249,
                                       fullChargeCapacity: 5800, voltage: 12500, amperage: 0, adapterWatts: 96,
                                       systemPowerIn: 12.4, systemLoad: 12.0)
    log.info("SIMULATION MODE (\(profile)) — no real SMC writes will happen")
} else {
    if geteuid() != 0 {
        log.warn("calmad is not running as root: charge control writes will fail. Use --simulate for development.")
    }
    do {
        smc = try SMCConnection()
    } catch {
        log.error("Couldn't open AppleSMC: \(error). Running without hardware control.")
        smc = nil
    }
}

let daemon = Daemon(log: log, smc: smc, simulatedBattery: simulatedBattery)
let server = SocketServer(path: CalmaPaths.socketPath, log: log) { command, peer in
    daemon.handle(command, peer: peer)
}

do {
    try server.start()
    log.info("Listening on \(CalmaPaths.socketPath)")
} catch {
    log.error("Socket server failed: \(error)")
    exit(1)
}

daemon.start()

// Restore stock charging on shutdown / bootout / Ctrl-C.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        log.info("Received signal \(sig)")
        daemon.shutdown()
        server.stop()
        // Give the log queue a moment to flush.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
    }
    source.resume()
    signalSources.append(source)
}

dispatchMain()
