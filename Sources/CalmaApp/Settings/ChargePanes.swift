import CalmaKit
import SwiftUI

// MARK: - Charge

struct ChargePane: View {
    @EnvironmentObject var model: AppModel
    @State private var drainTarget = 60
    @State private var confirmDrain = false

    var body: some View {
        let settings = model.settings
        let limit = model.pendingLimit ?? settings.chargeLimit

        PaneForm(pane: .charge, subtitle: "Choose how far your battery charges.") {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Charge Limit")
                            Text("Most research on lithium-ion ageing favours 50–80% for a Mac that lives on a desk.")
                                .font(.caption).foregroundStyle(.secondary).wrapsLines()
                        }
                        Spacer()
                        TextField("Limit", value: Binding(get: { limit }, set: { model.setChargeLimit(min(100, max(CalmaLimits.minimumChargeLimit, $0))) }),
                                  format: .number)
                            .labelsHidden()
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel(Text("Charge limit percent"))
                        Text("%").foregroundStyle(.secondary)
                    }
                    ChargeLimitSlider(limit: limit, level: model.level,
                                      driftRange: settings.driftRangeEnabled ? settings.driftRange : nil,
                                      enabled: model.canControl) { model.setChargeLimit($0) }
                    HStack {
                        ForEach([50, 60, 80, 100], id: \.self) { preset in
                            Button("\(preset)%") { model.setChargeLimit(preset) }
                                .controlSize(.small)
                                .disabled(!model.canControl || preset == limit)
                        }
                    }
                }
                .padding(.vertical, 2)

                ExplainedToggle(title: "Drift Range",
                                explanation: "At the limit, wait until the level drifts a few percent lower before charging again — fewer tiny top-ups.",
                                isOn: model.binding(\.driftRangeEnabled), enabled: model.canControl)
                if settings.driftRangeEnabled {
                    Stepper(value: model.binding(\.driftRange), in: 1...20) {
                        LabeledContent("Resume charging below", value: "\(max(0, limit - settings.driftRange))% (−\(settings.driftRange)%)")
                    }
                    .disabled(!model.canControl)
                }
                ExplainedToggle(title: "True Percentage",
                                explanation: "Use the battery controller's raw reading instead of the rounded value macOS shows. Every feature follows it.",
                                isOn: model.binding(\.useHardwarePercentage), enabled: model.helperState == .running)
            }

            Section("Draining") {
                ExplainedToggle(title: "Auto Drain",
                                explanation: "When you lower the limit below the current level, run from the battery until it gets there.",
                                isOn: model.binding(\.autoDrain), enabled: model.canDrain)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drain to…")
                        Text("Run from battery while plugged in until the chosen level. The Mac stays awake meanwhile.")
                            .font(.caption).foregroundStyle(.secondary).wrapsLines()
                    }
                    Spacer()
                    Text("\(drainTarget)%")
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                    Stepper("Drain target", value: $drainTarget, in: CalmaLimits.minimumChargeLimit...95, step: 5)
                        .labelsHidden()
                    Button("Drain") { confirmDrain = true }
                        .disabled(!model.canDrain)
                }
            }

            Section("One-off") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Charge")
                        Text("Charge to 100% once — handy before a trip. Your limit comes back as soon as you unplug.")
                            .font(.caption).foregroundStyle(.secondary).wrapsLines()
                    }
                    Spacer()
                    if model.runtime.mode == .fullCharge {
                        Button("Cancel") { model.send(.cancelMode) }
                    } else {
                        Button("Charge to 100%") { model.send(.startFullCharge) }
                            .disabled(!model.canControl)
                    }
                }
                ExplainedToggle(title: "Pause Charging",
                                explanation: "Stop charging completely, whatever the level, until you switch this off.",
                                isOn: Binding(get: { settings.chargingPaused }, set: { model.send(.setChargingPaused($0)) }),
                                enabled: model.canControl)
            }
        }
        .onAppear { drainTarget = max(CalmaLimits.minimumChargeLimit, min(95, settings.chargeLimit)) }
        .alert("Drain to \(drainTarget)%?", isPresented: $confirmDrain) {
            Button("Start Draining") { model.send(.startDrain(target: drainTarget)) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Mac will run from its battery while plugged in until it reaches \(drainTarget)%.")
        }
    }
}

// MARK: - Protection

struct ProtectionPane: View {
    @EnvironmentObject var model: AppModel
    @State private var threshold: Double = 35
    @State private var confirmRecalibration = false

    var body: some View {
        let settings = model.settings
        PaneForm(pane: .protection, subtitle: "Keep heat and drift from wearing your battery down.") {
            Section("Heat Guard") {
                ExplainedToggle(title: "Heat Guard",
                                // swiftlint:disable:next line_length
                                explanation: "Pause charging while the battery is warm. It checks again every 5 minutes and, once cool, charges for at least 5 minutes.",
                                isOn: model.binding(\.heatGuardEnabled), enabled: model.canControl)
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Pause above", value: String(format: "%.0f °C", threshold))
                    Slider(value: Binding(get: { threshold }, set: { threshold = $0.rounded() }), in: 25...50) {
                        Text("Pause above")
                    } minimumValueLabel: {
                        Text("25°")
                    } maximumValueLabel: {
                        Text("50°")
                    } onEditingChanged: { editing in
                        if !editing { model.updateSettings { $0.heatGuardThreshold = threshold } }
                    }
                    .labelsHidden()
                    if let temperature = model.battery?.temperature {
                        Text("Battery is at \(String(format: "%.1f °C", temperature)) right now.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.heatGuardEnabled || !model.canControl)
                if case .paused(let until) = model.runtime.heatGuard {
                    Label {
                        Text("Paused for heat — next check ") + Text(until, style: .relative)
                    } icon: {
                        Image(systemName: "thermometer.sun").foregroundStyle(.red)
                    }
                    .font(Font.callout)
                }
            }

            Section("Recalibrate") {
                VStack(alignment: .leading, spacing: 10) {
                    // swiftlint:disable:next line_length
                    Text("A guided full cycle that helps the battery controller re-learn its capacity, so the percentage you see stays accurate. Run it every few months.")
                        .font(Font.callout)
                        .foregroundStyle(.secondary)
                        .wrapsLines()
                    ForEach(Array(RecalibrationStage.allCases.enumerated()), id: \.offset) { index, stage in
                        HStack(spacing: 8) {
                            Image(systemName: stageIcon(stage, index: index))
                                .foregroundStyle(stageColor(stage, index: index))
                                .frame(width: 18)
                            Text(LocalizedStringKey(stage.title))
                        }
                        .font(Font.callout)
                    }
                    HStack {
                        Text("Heat Guard and Drift Range are paused while it runs. Keep your Mac plugged in.")
                            .font(.caption).foregroundStyle(.secondary).wrapsLines()
                        Spacer()
                        if case .recalibrate = model.runtime.mode {
                            Button("Cancel") { model.send(.cancelMode) }
                        } else {
                            Button("Start Recalibration…") { confirmRecalibration = true }
                                .disabled(!model.canDrain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear { threshold = settings.heatGuardThreshold }
        .onChange(of: settings.heatGuardThreshold) { threshold = $0 }
        .alert("Start recalibration?", isPresented: $confirmRecalibration) {
            Button("Start") { model.send(.startRecalibration) }
            Button("Cancel", role: .cancel) {}
        } message: {
            // swiftlint:disable:next line_length
            Text("Calma will charge to 100%, drain to 10% while plugged in, charge back to 100%, then hold for an hour before restoring your limit. This takes several hours and keeps your Mac awake.")
        }
    }

    private var currentIndex: Int? {
        if case .recalibrate(let stage) = model.runtime.mode {
            return RecalibrationStage.allCases.firstIndex(of: stage)
        }
        return nil
    }

    private func stageIcon(_ stage: RecalibrationStage, index: Int) -> String {
        guard let current = currentIndex else { return "\(index + 1).circle" }
        if index < current { return "checkmark.circle.fill" }
        if index == current { return "circle.dotted.circle" }
        return "\(index + 1).circle"
    }

    private func stageColor(_ stage: RecalibrationStage, index: Int) -> Color {
        guard let current = currentIndex else { return .secondary }
        return index <= current ? .accentColor : .secondary
    }
}

// MARK: - Sleep

struct SleepPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        PaneForm(pane: .sleep, subtitle: "Stay in control while your Mac sleeps or Calma is closed.") {
            Section {
                ExplainedToggle(title: "Pause on Sleep",
                                explanation: "Stop charging just before your Mac sleeps, so it can't charge to 100% overnight.",
                                isOn: model.binding(\.pauseChargingOnSleep), enabled: model.canControl)
                ExplainedToggle(title: "Stay Awake to Limit",
                                explanation: "Keep the Mac awake while it's charging toward your limit. The display can still turn off.",
                                isOn: model.binding(\.stayAwakeUntilLimit), enabled: model.canControl)
            }
            Section {
                ExplainedToggle(title: "Keep Limit After Quit",
                                explanation: "Keep enforcing your limit when Calma is quit or you log out. When off, normal charging returns on quit.",
                                isOn: model.binding(\.keepLimitWhenAppClosed), enabled: model.canControl)
                Label("A full shut down resets the charging controller. Calma re-applies your limit at the next login.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Multiple users") {
                Label("The helper is system-wide, so the limit applies to every account on this Mac. The most recent change wins.",
                      systemImage: "person.2")
                    .font(Font.callout)
                    .foregroundStyle(.secondary)
                if let owner = model.status?.lastChangedBy {
                    LabeledContent("Last changed by", value: owner)
                }
            }
        }
    }
}

// MARK: - MagSafe

struct MagSafePane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        PaneForm(pane: .magSafe, subtitle: "Use the MagSafe connector light as a status signal.") {
            Section {
                Picker(selection: model.binding(\.magSafeLED)) {
                    Text("Let macOS decide").tag(MagSafeLEDMode.system)
                    Text("Show Calma status").tag(MagSafeLEDMode.status)
                    Text("Always off").tag(MagSafeLEDMode.off)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MagSafe Light")
                        Text("Status mode: green at your limit, amber while charging or draining toward it.")
                            .font(.caption).foregroundStyle(.secondary).wrapsLines()
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(model.helperState != .running)

                ExplainedToggle(title: "Blink while draining",
                                explanation: "Pulse the amber light while the Mac runs from its battery on purpose.",
                                isOn: model.binding(\.magSafeBlinkWhileDraining),
                                enabled: model.helperState == .running && model.settings.magSafeLED == .status)
            }
            Section {
                HStack(spacing: 18) {
                    ledSample(color: .green, title: "At limit")
                    ledSample(color: .orange, title: "Charging / draining")
                    ledSample(color: .gray.opacity(0.4), title: "Off")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func ledSample(color: Color, title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.7), radius: 3)
            Text(title).font(Font.callout)
        }
    }
}

// MARK: - Power modes

struct PowerModesPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        PaneForm(pane: .power, subtitle: "Switch macOS energy modes without digging through System Settings.") {
            Section {
                modeRow(title: "Low Power Mode", icon: "leaf.fill", tint: .green,
                        explanation: "Reduces energy use — longer battery life, a little less performance.",
                        on: .setLowPowerMode(true), off: .setLowPowerMode(false))
                modeRow(title: "High Power Mode", icon: "hare.fill", tint: .orange,
                        explanation: "Lets demanding work run flat out. Only available on some MacBook Pro models.",
                        on: .setHighPowerMode(true), off: .setHighPowerMode(false))
            }
        }
    }

    private func modeRow(title: LocalizedStringKey, icon: String, tint: Color, explanation: LocalizedStringKey,
                         on: CalmaCommand, off: CalmaCommand) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(explanation).font(.caption).foregroundStyle(.secondary).wrapsLines()
            }
            Spacer()
            Button("Turn On") { model.send(on) }
            Button("Turn Off") { model.send(off) }
        }
        .disabled(model.helperState != .running)
    }
}
