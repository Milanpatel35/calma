import CalmaKit
import SwiftUI

/// The menu bar item: a template symbol for the current state plus optional percentage.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    let showPercentage: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: StateSymbol.name(for: model.chargeState, level: model.level ?? 100))
            if showPercentage, let level = model.level {
                Text("\(level)%")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Calma"))
        .accessibilityValue(Text(StateSymbol.accessibilityDescription(for: model.chargeState, level: model.level)))
    }
}

enum StateSymbol {
    static func name(for state: ChargeState, level: Int) -> String {
        switch state {
        case .charging: return "battery.100percent.bolt"
        case .paused: return "powerplug"
        case .draining: return "arrow.down.circle"
        case .heatPaused: return "thermometer.sun"
        case .onBattery: return batteryLevelSymbol(level)
        }
    }

    static func batteryLevelSymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func title(for state: ChargeState) -> LocalizedStringKey {
        switch state {
        case .charging: return "Charging"
        case .paused: return "Holding"
        case .draining: return "Draining"
        case .heatPaused: return "Cooling down"
        case .onBattery: return "On battery"
        }
    }

    static func accessibilityDescription(for state: ChargeState, level: Int?) -> String {
        let levelText = level.map { "\($0)%" } ?? ""
        switch state {
        case .charging: return String(localized: "Charging, \(levelText)")
        case .paused: return String(localized: "Plugged in, charging paused, \(levelText)")
        case .draining: return String(localized: "Plugged in, draining, \(levelText)")
        case .heatPaused: return String(localized: "Charging paused because the battery is warm, \(levelText)")
        case .onBattery: return String(localized: "On battery, \(levelText)")
        }
    }

    static func tint(for state: ChargeState) -> Color {
        switch state {
        case .charging: return .green
        case .paused: return .teal
        case .draining: return .orange
        case .heatPaused: return .red
        case .onBattery: return .secondary
        }
    }
}
