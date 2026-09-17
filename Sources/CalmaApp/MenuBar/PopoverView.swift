import AppKit
import CalmaKit
import SwiftUI

/// The window shown from the menu bar item.
struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmDrain = false
    /// Snapshot rendering uses an opaque background because vibrancy doesn't render offscreen.
    var opaqueBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HelperBanner()
            FirmwareBanner()
            MessageBanner()
            if model.isMonitoringOnly {
                nativeLimitSection
            } else {
                limitSection
                ActiveModeCard()
                quickActions
            }
            if let owner = model.status?.lastChangedBy, owner != NSUserName(), !model.isPreview {
                Label("Limit last set by \(owner)", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(opaqueBackground ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .onAppear { model.surface(visible: true) }
        .onDisappear { model.surface(visible: false) }
        .alert("Drain to \(model.settings.chargeLimit)%?", isPresented: $confirmDrain) {
            Button("Start Draining") { model.send(.startDrain(target: model.settings.chargeLimit)) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Mac will run from its battery while plugged in until it reaches your charge limit. It stays awake while draining.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(model.level.map(String.init) ?? "–")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Battery level"))

                Text(model.summary)
                    .font(Font.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .wrapsLines()
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                stateBadge
                if model.settings.useHardwarePercentage, let battery = model.battery {
                    Text("macOS shows \(battery.percentage)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let hardware = model.battery?.hardwarePercentage {
                    Text("True \(hardware)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var stateBadge: some View {
        let state = model.chargeState
        let tint = StateSymbol.tint(for: state)
        return Label(StateSymbol.title(for: state), systemImage: StateSymbol.name(for: state, level: model.level ?? 100))
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    /// Monitoring mode: show the limit macOS enforces instead of controls that can't act.
    private var nativeLimitSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Charge Limit").font(.headline)
                Text("Set by macOS in Battery Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.capabilities.nativeChargeLimit.map { "\($0)%" } ?? String(localized: "Off"))
                .font(.headline)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var limitSection: some View {
        let settings = model.settings
        let limit = model.pendingLimit ?? settings.chargeLimit
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Charge Limit").font(.headline)
                Spacer()
                Text("\(limit)%")
                    .font(.headline)
                    .monospacedDigit()
                Stepper("Charge Limit", value: Binding(
                    get: { limit },
                    set: { model.setChargeLimit($0) }
                ), in: CalmaLimits.minimumChargeLimit...100, step: 5)
                .labelsHidden()
                .disabled(!model.canControl)
            }
            ChargeLimitSlider(limit: limit, level: model.level,
                              driftRange: settings.driftRangeEnabled ? settings.driftRange : nil,
                              enabled: model.canControl) { model.setChargeLimit($0) }
            Text(limitCaption(settings: settings, limit: limit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func limitCaption(settings: CalmaSettings, limit: Int) -> LocalizedStringKey {
        if limit >= 100 { return "No limit — charges like stock macOS." }
        if settings.driftRangeEnabled {
            return "Stops at \(limit)% · resumes below \(max(0, limit - settings.driftRange))% (Drift Range)"
        }
        return "Stops charging at \(limit)% and runs from the adapter."
    }

    private var quickActions: some View {
        let settings = model.settings
        return HStack(spacing: 8) {
            ActionTile(title: "Full Charge", icon: "bolt.fill", active: model.runtime.mode == .fullCharge,
                       enabled: model.canControl) {
                model.send(model.runtime.mode == .fullCharge ? .cancelMode : .startFullCharge)
            }
            if !settings.autoDrain {
                ActionTile(title: "Drain", icon: "arrow.down.circle", active: isDraining,
                           enabled: model.canDrain) {
                    if isDraining { model.send(.cancelMode) } else { confirmDrain = true }
                }
            }
            ActionTile(title: settings.chargingPaused ? "Resume" : "Pause", icon: settings.chargingPaused ? "play.fill" : "pause.fill",
                       active: settings.chargingPaused, enabled: model.canControl) {
                model.send(.setChargingPaused(!settings.chargingPaused))
            }
        }
    }

    private var isDraining: Bool {
        if case .drain = model.runtime.mode { return true }
        return false
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: SettingsWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Calma", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(Font.callout)
    }
}

/// A compact square action button.
struct ActionTile: View {
    let title: LocalizedStringKey
    let icon: String
    let active: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.accentColor : Color.primary.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Shows Full Charge / Drain / Recalibrate progress with a cancel button.
struct ActiveModeCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.runtime.mode {
        case .normal:
            EmptyView()
        case .fullCharge:
            card(icon: "bolt.fill", title: "Full Charge", detail: Text("Charging to 100%. Your limit returns when you unplug."))
        case .drain(let target):
            card(icon: "arrow.down.circle", title: "Draining", detail: Text("Running from battery until \(target)%."))
        case .recalibrate(let stage):
            card(icon: "arrow.triangle.2.circlepath", title: "Recalibrating",
                 detail: recalibrationDetail(stage), stage: stage)
        }
    }

    private func recalibrationDetail(_ stage: RecalibrationStage) -> Text {
        var text = Text(LocalizedStringKey(stage.title))
        if let started = model.runtime.modeStartedAt {
            text = text + Text(" · ") + Text("started ") + Text(started, style: .relative) + Text(" ago")
        }
        return text
    }

    private func card(icon: String, title: LocalizedStringKey, detail: Text, stage: RecalibrationStage? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Font.callout.weight(.semibold))
                    detail.font(.caption).foregroundStyle(.secondary).wrapsLines()
                }
                Spacer()
                Button("Cancel") { model.send(.cancelMode) }
                    .controlSize(.small)
            }
            if let stage, let index = RecalibrationStage.allCases.firstIndex(of: stage) {
                ProgressView(value: Double(index), total: Double(RecalibrationStage.allCases.count))
                    .accessibilityLabel(Text("Recalibration step \(index + 1) of 4"))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.10)))
    }
}
