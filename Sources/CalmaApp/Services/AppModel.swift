import AppKit
import CalmaHardware
import CalmaKit
import Combine
import Foundation

/// Whether the privileged helper is reachable.
enum HelperState: Equatable {
    case checking
    case running
    case notInstalled
    case error(String)
}

/// Single source of truth for the UI. Talks to `calmad`, falls back to local battery reads.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: CalmaStatus?
    @Published private(set) var localBattery: BatterySnapshot?
    @Published private(set) var helperState: HelperState = .checking
    @Published var lastError: String?
    @Published var busy = false
    /// Local slider value while dragging, so the UI doesn't jump back between polls.
    @Published var pendingLimit: Int?

    let isPreview: Bool
    private var pollTimer: Timer?
    private var heartbeatTimer: Timer?
    private var powerObserver: PowerSourceObserver?
    private var fastPolling = false
    private let reader: BatteryReader?

    init() {
        isPreview = false
        reader = BatteryReader()
    }

    /// Fixed-data model for screenshots and previews. Never touches the daemon or hardware.
    init(preview status: CalmaStatus) {
        isPreview = true
        reader = nil
        self.status = status
        self.localBattery = status.battery
        self.helperState = .running
    }

    // MARK: Derived state

    var battery: BatterySnapshot? { status?.battery ?? localBattery }
    var settings: CalmaSettings { status?.settings ?? .defaults }
    var capabilities: Capabilities { status?.capabilities ?? .none }
    var runtime: RuntimeState { status?.runtime ?? RuntimeState() }

    var level: Int? {
        guard let battery else { return nil }
        return battery.effectivePercentage(useHardware: settings.useHardwarePercentage)
    }

    var chargeState: ChargeState {
        if let status { return status.state }
        guard let battery else { return .onBattery }
        if !battery.isPluggedIn { return .onBattery }
        return battery.isCharging ? .charging : .paused
    }

    var canControl: Bool { helperState == .running && capabilities.canInhibitCharging }
    var canDrain: Bool { helperState == .running && capabilities.canDrain && capabilities.canInhibitCharging }

    var summary: String {
        if let status { return status.summary }
        guard let battery else { return String(localized: "No battery found") }
        if !battery.isPluggedIn { return String(localized: "On battery") }
        return battery.isCharging ? String(localized: "Charging") : String(localized: "Plugged in")
    }

    // MARK: Lifecycle

    func start() {
        guard !isPreview, pollTimer == nil else { return }
        refresh()
        schedulePolling()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendQuietly(.appHeartbeat) }
        }
        powerObserver = PowerSourceObserver { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private var visibleSurfaces = 0

    /// Call from `onAppear`/`onDisappear` of the popover and settings window.
    func surface(visible: Bool) {
        visibleSurfaces = max(0, visibleSurfaces + (visible ? 1 : -1))
        setFastPolling(visibleSurfaces > 0)
    }

    /// Poll every 5 s while a Calma window is visible, every 30 s otherwise.
    private func setFastPolling(_ fast: Bool) {
        guard fast != fastPolling else { return }
        fastPolling = fast
        schedulePolling()
        if fast { refresh() }
    }

    private func schedulePolling() {
        guard !isPreview else { return }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: fastPolling ? 5 : 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isPreview else { return }
        let reader = self.reader
        Task.detached(priority: .utility) {
            let local = reader?.read()
            do {
                let response = try CalmaClient.send(.status, timeout: 3)
                await MainActor.run {
                    self.localBattery = local
                    if let status = response.status {
                        self.status = status
                        self.helperState = .running
                    } else {
                        self.helperState = .error(response.error ?? "Unknown error")
                    }
                }
            } catch CalmaIPCError.daemonNotRunning {
                await MainActor.run {
                    self.localBattery = local
                    self.status = nil
                    self.helperState = .notInstalled
                }
            } catch {
                await MainActor.run {
                    self.localBattery = local
                    self.status = nil
                    self.helperState = .error(String(describing: error))
                }
            }
        }
    }

    func appWillQuit() {
        guard !isPreview else { return }
        _ = try? CalmaClient.send(.appWillQuit, timeout: 1)
    }

    // MARK: Commands

    /// Sends a command and refreshes status from the response.
    func send(_ command: CalmaCommand) {
        guard !isPreview else { return }
        busy = true
        Task.detached(priority: .userInitiated) {
            let result: Result<CalmaResponse, Error> = Result { try CalmaClient.send(command) }
            await MainActor.run {
                self.busy = false
                switch result {
                case .success(let response):
                    if let status = response.status {
                        self.status = status
                        self.helperState = .running
                    } else {
                        self.refresh()
                    }
                    if !response.ok { self.lastError = response.error ?? String(localized: "Calma couldn't do that.") }
                    self.pendingLimit = nil
                case .failure(let error):
                    self.lastError = String(describing: error)
                    self.pendingLimit = nil
                    if case CalmaIPCError.daemonNotRunning = error { self.helperState = .notInstalled }
                    self.refresh()
                }
            }
        }
    }

    private func sendQuietly(_ command: CalmaCommand) {
        Task.detached(priority: .background) { _ = try? CalmaClient.send(command, timeout: 2) }
    }

    /// Edit a copy of the current settings and send it to the daemon.
    func updateSettings(_ change: (inout CalmaSettings) -> Void) {
        guard var current = status?.settings else { return }
        change(&current)
        current.sanitize()
        if var optimistic = status {
            optimistic.settings = current
            status = optimistic
        }
        send(.updateSettings(current))
    }

    func setChargeLimit(_ limit: Int) {
        pendingLimit = limit
        send(.setChargeLimit(limit))
    }

    // MARK: Helper management

    var bundleResources: String { Bundle.main.resourcePath ?? "" }

    func installHelper() {
        runPrivileged(script: "'\(escaped(bundleResources))/install-daemon.sh' '\(escaped(bundleResources))'",
                      success: String(localized: "Helper installed."))
    }

    func uninstallHelper() {
        runPrivileged(script: "'\(escaped(bundleResources))/uninstall-daemon.sh'",
                      success: String(localized: "Helper removed. Charging is back to normal."))
    }

    func installCommandLineTool() {
        runPrivileged(script: "mkdir -p /usr/local/bin && ln -sf '\(escaped(bundleResources))/calma' /usr/local/bin/calma",
                      success: String(localized: "Installed the calma command at /usr/local/bin/calma."))
    }

    @Published var infoMessage: String?

    private func escaped(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runPrivileged(script: String, success: String) {
        guard !isPreview else { return }
        busy = true
        let source = "do shell script \"\(script)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            let appleScript = NSAppleScript(source: source)
            appleScript?.executeAndReturnError(&errorInfo)
            let message = errorInfo?[NSAppleScript.errorMessage] as? String
            let cancelled = (errorInfo?[NSAppleScript.errorNumber] as? Int) == -128
            DispatchQueue.main.async {
                self.busy = false
                if let message, !cancelled {
                    self.lastError = message
                } else if errorInfo == nil {
                    self.infoMessage = success
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
            }
        }
    }
}
