import CalmaKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case dashboard, charge, protection, sleep, schedule, magSafe, power, appearance, advanced, about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: return "Dashboard"
        case .charge: return "Charge"
        case .protection: return "Protection"
        case .sleep: return "Sleep"
        case .schedule: return "Schedule"
        case .magSafe: return "MagSafe Light"
        case .power: return "Power Modes"
        case .appearance: return "Appearance"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .charge: return "battery.100percent.bolt"
        case .protection: return "shield.lefthalf.filled"
        case .sleep: return "moon.zzz"
        case .schedule: return "calendar.badge.clock"
        case .magSafe: return "lightbulb"
        case .power: return "leaf"
        case .appearance: return "menubar.rectangle"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: return .teal
        case .charge: return .green
        case .protection: return .red
        case .sleep: return .indigo
        case .schedule: return .orange
        case .magSafe: return .yellow
        case .power: return .mint
        case .appearance: return .blue
        case .advanced: return .gray
        case .about: return .secondary
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: SettingsPane?

    init(initialPane: SettingsPane = .dashboard) {
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(visiblePanes, selection: $selection) { pane in
                NavigationLink(value: pane) {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.icon)
                            .foregroundStyle(pane.tint)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            detail(for: selection ?? .dashboard)
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 600, idealHeight: 640)
        .onAppear { model.surface(visible: true) }
        .onDisappear { model.surface(visible: false) }
    }

    private var visiblePanes: [SettingsPane] {
        SettingsPane.allCases.filter { pane in
            pane != .magSafe || model.capabilities.hasMagSafeLED
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .dashboard: DashboardPane()
        case .charge: ChargePane()
        case .protection: ProtectionPane()
        case .sleep: SleepPane()
        case .schedule: SchedulePane()
        case .magSafe: MagSafePane()
        case .power: PowerModesPane()
        case .appearance: AppearancePane()
        case .advanced: AdvancedPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Shared building blocks

/// A toggle with a one-line explanation beneath the title.
struct ExplainedToggle: View {
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .wrapsLines()
            }
        }
        .disabled(!enabled)
    }
}

/// Header shown at the top of each settings pane.
struct PaneHeader: View {
    let pane: SettingsPane
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9).fill(pane.tint.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title).font(.title2.weight(.semibold))
                Text(subtitle).font(Font.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Standard pane scaffold: header + grouped form + banners.
struct PaneForm<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let pane: SettingsPane
    let subtitle: LocalizedStringKey
    var showsBanners = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: pane, subtitle: subtitle)
                if showsBanners {
                    HelperBanner()
                    FirmwareBanner()
                    MessageBanner()
                }
            }
            content()
        }
        .formStyle(.grouped)
        .navigationTitle(Text(pane.title))
    }
}

extension AppModel {
    /// Two-way binding to a settings field that pushes changes to the daemon.
    func binding<Value>(_ keyPath: WritableKeyPath<CalmaSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }
}
