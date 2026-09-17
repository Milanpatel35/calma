import CalmaKit
import SwiftUI

struct DashboardPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        PaneForm(pane: .dashboard, subtitle: "Live battery health and where your power is going.") {
            if let battery = model.battery {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        StatTile(title: "Charge", value: "\(model.level ?? battery.percentage)%",
                                 detail: Text(stateDetail), icon: "battery.75percent", tint: .green)
                        StatTile(title: "Health", value: battery.health.map { "\($0)%" } ?? "–",
                                 detail: Text(capacityDetail(battery)), icon: "heart.fill", tint: .pink)
                        StatTile(title: "Cycles", value: battery.cycleCount.map(String.init) ?? "–",
                                 detail: Text("Charge cycles"), icon: "arrow.triangle.2.circlepath", tint: .blue)
                        StatTile(title: "Temperature", value: battery.temperature.map { String(format: "%.1f °C", $0) } ?? "–",
                                 detail: Text(temperatureDetail(battery)), icon: "thermometer.medium", tint: .orange)
                        StatTile(title: "Voltage", value: battery.voltage.map { String(format: "%.2f V", Double($0) / 1000) } ?? "–",
                                 detail: Text(battery.amperage.map { "\($0) mA" } ?? ""), icon: "bolt.horizontal", tint: .purple)
                        StatTile(title: "Adapter",
                                 value: battery.isPluggedIn
                                    ? (battery.adapterWatts.map { "\($0) W" } ?? String(localized: "Connected"))
                                    : String(localized: "None"),
                                 detail: battery.isPluggedIn ? Text("Connected") : Text("On battery"), icon: "powerplug", tint: .teal)
                    }
                    .padding(.vertical, 4)
                }

                Section("Power Flow") {
                    PowerFlowView(flow: PowerFlow(battery: battery, adapterEnabled: model.chargeState != .draining),
                                  pluggedIn: battery.isPluggedIn, batteryLevel: model.level)
                        .padding(.vertical, 6)
                }

                Section("Status") {
                    LabeledContent("Right now", value: model.summary)
                    LabeledContent("Charge limit", value: "\(model.settings.chargeLimit)%")
                    if let hardware = battery.hardwarePercentage {
                        LabeledContent("True percentage", value: "\(hardware)% (macOS shows \(battery.percentage)%)")
                    }
                    LabeledContent("Control method", value: backendDescription)
                }
            } else {
                Section {
                    Label("No internal battery found. Calma is for MacBooks.", systemImage: "battery.0percent")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var stateDetail: LocalizedStringKey { StateSymbol.title(for: model.chargeState) }

    private func capacityDetail(_ battery: BatterySnapshot) -> LocalizedStringKey {
        guard let full = battery.fullChargeCapacity, let design = battery.designCapacity else { return "Capacity" }
        return "\(full) of \(design) mAh"
    }

    private func temperatureDetail(_ battery: BatterySnapshot) -> LocalizedStringKey {
        guard let temperature = battery.temperature else { return "Unavailable" }
        if temperature >= 40 { return "Hot" }
        if temperature >= 35 { return "Warm" }
        return "Comfortable"
    }

    private var backendDescription: String {
        BackendDescription.text(model.capabilities.backend, helperRunning: model.helperState == .running)
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    let detail: Text
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            detail
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

enum BackendDescription {
    static func text(_ backend: ChargeBackend, helperRunning: Bool) -> String {
        switch backend {
        case .appleSiliconModern: return String(localized: "Apple silicon · CHTE / CHIE")
        case .appleSiliconLegacy: return String(localized: "Apple silicon · CH0B / CH0C")
        case .intel: return String(localized: "Intel · BCLM")
        case .unsupported: return helperRunning ? String(localized: "Monitoring only") : String(localized: "Helper not installed")
        }
    }
}
