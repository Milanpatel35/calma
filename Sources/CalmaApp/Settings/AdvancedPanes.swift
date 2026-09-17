import AppKit
import CalmaKit
import ServiceManagement
import SwiftUI

// MARK: - Appearance

struct AppearancePane: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(AppearanceKeys.showPercentage) private var showPercentage = true
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        PaneForm(pane: .appearance, subtitle: "How Calma looks in your menu bar.", showsBanners: false) {
            Section {
                ExplainedToggle(title: "Show percentage in menu bar",
                                explanation: "Display the battery level next to the Calma icon.",
                                isOn: $showPercentage)
                ExplainedToggle(title: "Launch at login",
                                explanation: "Start Calma automatically when you log in.",
                                isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Menu bar icons") {
                ForEach([ChargeState.charging, .paused, .draining, .heatPaused, .onBattery], id: \.self) { state in
                    HStack(spacing: 12) {
                        Image(systemName: StateSymbol.name(for: state, level: 70))
                            .frame(width: 26)
                            .font(.title3)
                        Text(StateSymbol.title(for: state))
                        Spacer()
                        Text(iconExplanation(state)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            if !model.isPreview { launchAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }

    private func iconExplanation(_ state: ChargeState) -> LocalizedStringKey {
        switch state {
        case .charging: return "Plugged in and charging"
        case .paused: return "Plugged in, holding at the limit"
        case .draining: return "Plugged in, running from battery"
        case .heatPaused: return "Paused by Heat Guard"
        case .onBattery: return "Unplugged"
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard !model.isPreview else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updates: UpdateChecker
    @AppStorage(UpdateChecker.enabledKey) private var checkForUpdates = false
    @State private var confirmReset = false
    @State private var confirmUninstall = false

    var body: some View {
        PaneForm(pane: .advanced, subtitle: "Helper, command-line tool, recovery and updates.") {
            Section("Helper") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(helperColor).frame(width: 8, height: 8)
                        Text(helperText)
                    }
                }
                if let version = model.status?.daemonVersion {
                    LabeledContent("Helper version", value: version)
                }
                LabeledContent("Control method", value: BackendDescription.text(model.capabilities.backend, helperRunning: model.helperState == .running))
                if !model.capabilities.modelIdentifier.isEmpty {
                    LabeledContent("Mac", value: "\(model.capabilities.modelIdentifier) · macOS \(model.capabilities.osVersion)")
                }
                HStack {
                    Text("The helper is the only part of Calma that runs as root. It can only touch a fixed list of charging keys.")
                        .font(.caption).foregroundStyle(.secondary).wrapsLines()
                    Spacer()
                    if model.helperState == .running {
                        Button("Uninstall…") { confirmUninstall = true }
                    } else {
                        Button("Install Helper…") { model.installHelper() }
                    }
                }
                .disabled(model.busy)
            }

            Section("Command line & Shortcuts") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("calma command")
                        Text("Links the `calma` tool into /usr/local/bin — try `calma status` or `calma limit 80`.")
                            .font(.caption).foregroundStyle(.secondary).wrapsLines()
                    }
                    Spacer()
                    Button("Install…") { model.installCommandLineTool() }
                        .disabled(model.busy)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcuts")
                    Text("Use the “Open URL” action with calma://limit/80, calma://fullcharge, calma://drain/60, calma://pause, calma://resume, calma://recalibrate or calma://cancel.")
                        .font(.caption).foregroundStyle(.secondary).wrapsLines()
                        .textSelection(.enabled)
                }
            }

            Section("Recovery") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency Reset")
                        Text("Restores normal charging on every key and cancels all modes. Use this if anything seems stuck.")
                            .font(.caption).foregroundStyle(.secondary).wrapsLines()
                    }
                    Spacer()
                    Button("Reset…", role: .destructive) { confirmReset = true }
                        .disabled(model.helperState != .running)
                }
                HStack {
                    Text("Every change the helper makes is logged locally, with the previous value.")
                        .font(.caption).foregroundStyle(.secondary).wrapsLines()
                    Spacer()
                    Button("Show Logs") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: CalmaPaths.logDirectory))
                    }
                }
            }

            Section("Updates") {
                ExplainedToggle(title: "Check for updates",
                                // swiftlint:disable:next line_length
                                explanation: "Asks GitHub for the latest release when Calma starts. This is the only network request Calma ever makes — off by default.",
                                isOn: $checkForUpdates)
                if checkForUpdates {
                    HStack {
                        updateStatus
                        Spacer()
                        Button("Check Now") { updates.checkNow() }
                            .disabled(updates.result == .checking)
                    }
                }
            }
        }
        .alert("Reset charging to normal?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.send(.emergencyReset) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Charging, the adapter and the MagSafe light go back to stock macOS behaviour and any running mode is cancelled. Your settings are kept.")
        }
        .alert("Uninstall the helper?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { model.uninstallHelper() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Charging returns to normal and the helper is removed. You can reinstall it at any time.")
        }
    }

    private var helperColor: Color {
        switch model.helperState {
        case .running: return .green
        case .checking: return .gray
        case .notInstalled: return .orange
        case .error: return .red
        }
    }

    private var helperText: LocalizedStringKey {
        switch model.helperState {
        case .running: return "Running"
        case .checking: return "Checking…"
        case .notInstalled: return "Not installed"
        case .error: return "Not responding"
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.result {
        case .idle: Text("Not checked yet").foregroundStyle(.secondary)
        case .checking: ProgressView().controlSize(.small)
        case .upToDate: Label("You're up to date (\(CalmaVersion.current))", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .available(let version, let url):
            Link(destination: url) { Label("Calma \(version) is available", systemImage: "arrow.down.circle") }
        case .failed(let message): Text(message).foregroundStyle(.secondary).font(.caption)
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
                Text("Calma").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Version \(CalmaVersion.current)").foregroundStyle(.secondary)
                Text("Keep your MacBook's battery calm.")
                    .font(.title3)
                HStack(spacing: 8) {
                    pill("Free & open source · GPL-3.0", icon: "heart")
                    pill("No telemetry", icon: "eye.slash")
                }
                pill("No accounts. No paid tier. Every feature included.", icon: "gift")
                HStack(spacing: 12) {
                    Link(destination: CalmaPaths.repositoryURL) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Link(destination: CalmaPaths.repositoryURL.appendingPathComponent("graphs/contributors")) { Label("Contributors", systemImage: "person.3") }
                    Link(destination: CalmaPaths.repositoryURL.appendingPathComponent("issues/new/choose")) { Label("Report an issue", systemImage: "ladybug") }
                }
                .padding(.top, 6)
                Text("Calma controls charging hardware and is provided as-is, without warranty. See docs/SAFETY.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .navigationTitle(Text("About"))
    }

    private func pill(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(Font.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }
}
