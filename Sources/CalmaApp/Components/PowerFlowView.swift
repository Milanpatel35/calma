import CalmaKit
import SwiftUI

/// Where the watts are going, derived from battery telemetry.
struct PowerFlow: Equatable {
    var adapterToSystem: Double
    var adapterToBattery: Double
    var batteryToSystem: Double
    var systemLoad: Double
    var adapterIn: Double

    init(adapterToSystem: Double, adapterToBattery: Double, batteryToSystem: Double) {
        self.adapterToSystem = adapterToSystem
        self.adapterToBattery = adapterToBattery
        self.batteryToSystem = batteryToSystem
        self.adapterIn = adapterToSystem + adapterToBattery
        self.systemLoad = adapterToSystem + batteryToSystem
    }

    init(battery: BatterySnapshot, adapterEnabled: Bool) {
        let batteryWatts = battery.batteryWatts ?? 0
        let adapterIn = battery.isPluggedIn && adapterEnabled ? max(0, battery.systemPowerIn ?? 0) : 0

        if batteryWatts > 0.05 {
            // Charging: adapter feeds both the battery and the system.
            let toBattery = min(batteryWatts, adapterIn > 0 ? adapterIn : batteryWatts)
            self.init(adapterToSystem: max(0, adapterIn - toBattery), adapterToBattery: toBattery, batteryToSystem: 0)
        } else if batteryWatts < -0.05 {
            // Discharging: battery feeds the system, possibly together with an underpowered adapter.
            self.init(adapterToSystem: adapterIn, adapterToBattery: 0, batteryToSystem: -batteryWatts)
        } else {
            self.init(adapterToSystem: adapterIn > 0 ? adapterIn : max(0, battery.systemLoad ?? 0),
                      adapterToBattery: 0, batteryToSystem: 0)
        }
    }
}

/// Sankey-style Power Flow diagram drawn with Canvas.
struct PowerFlowView: View {
    let flow: PowerFlow
    let pluggedIn: Bool
    let batteryLevel: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 190
    private let nodeWidth: CGFloat = 116
    private let nodeHeight: CGFloat = 60

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: height - nodeHeight * 2 - 10) {
                node(icon: "powerplug.fill", title: "Adapter", watts: flow.adapterIn,
                     tint: .green, dimmed: !pluggedIn)
                node(icon: "battery.75percent", title: "Battery",
                     watts: flow.adapterToBattery > 0 ? flow.adapterToBattery : flow.batteryToSystem,
                     tint: flow.batteryToSystem > 0 ? .orange : .teal,
                     subtitle: flow.adapterToBattery > 0 ? "charging" : (flow.batteryToSystem > 0 ? "supplying" : "idle"))
            }
            .frame(width: nodeWidth)

            bands
                .frame(maxWidth: .infinity)

            node(icon: "laptopcomputer", title: "System", watts: flow.systemLoad, tint: .blue)
                .frame(width: nodeWidth)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Power flow"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    @ViewBuilder
    private var bands: some View {
        if reduceMotion {
            Canvas { context, size in draw(context: context, size: size, phase: 0) }
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate * -24
                Canvas { context, size in draw(context: context, size: size, phase: phase) }
            }
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, phase: Double) {
        let total = max(flow.adapterIn + flow.batteryToSystem, flow.systemLoad, 1)
        let maxThickness: CGFloat = 44
        let scale = maxThickness / CGFloat(total)
        let adapterY = nodeHeight / 2
        let batteryY = size.height - nodeHeight / 2
        let systemY = size.height / 2

        // System inputs are stacked so bands meet cleanly on the right.
        let toSystemFromAdapter = CGFloat(flow.adapterToSystem) * scale
        let toSystemFromBattery = CGFloat(flow.batteryToSystem) * scale
        let stack = toSystemFromAdapter + toSystemFromBattery
        let systemTop = systemY - stack / 2

        func band(from startY: CGFloat, to endY: CGFloat, thickness: CGFloat, color: Color) {
            guard thickness > 0.3 else { return }
            let t = max(thickness, 2)
            var path = Path()
            let midX = size.width / 2
            path.move(to: CGPoint(x: 0, y: startY))
            path.addCurve(to: CGPoint(x: size.width, y: endY),
                          control1: CGPoint(x: midX, y: startY), control2: CGPoint(x: midX, y: endY))
            context.stroke(path, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: t, lineCap: .butt))
            context.stroke(path, with: .color(color.opacity(0.9)),
                           style: StrokeStyle(lineWidth: min(2.5, t / 3), lineCap: .round, dash: [2, 9], dashPhase: phase))
        }

        band(from: adapterY, to: systemTop + toSystemFromAdapter / 2, thickness: toSystemFromAdapter, color: .green)
        band(from: batteryY, to: systemTop + toSystemFromAdapter + toSystemFromBattery / 2,
             thickness: toSystemFromBattery, color: .orange)

        // Adapter → battery loops out from the adapter's right edge and back into the battery.
        let toBattery = CGFloat(flow.adapterToBattery) * scale
        if toBattery > 0.3 {
            let t = max(toBattery, 2)
            let reach = min(size.width * 0.28, 90)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: adapterY + nodeHeight * 0.28))
            path.addCurve(to: CGPoint(x: 0, y: batteryY - nodeHeight * 0.28),
                          control1: CGPoint(x: reach, y: adapterY + nodeHeight * 0.28),
                          control2: CGPoint(x: reach, y: batteryY - nodeHeight * 0.28))
            context.stroke(path, with: .color(Color.teal.opacity(0.35)), style: StrokeStyle(lineWidth: t))
            context.stroke(path, with: .color(Color.teal.opacity(0.9)),
                           style: StrokeStyle(lineWidth: min(2.5, t / 3), lineCap: .round, dash: [2, 9], dashPhase: phase))
        }
    }

    private func node(icon: String, title: LocalizedStringKey, watts: Double, tint: Color,
                      dimmed: Bool = false, subtitle: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(String(format: "%.1f W", watts))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: nodeWidth, height: nodeHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.25)))
        .opacity(dimmed ? 0.45 : 1)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if flow.adapterIn > 0 { parts.append(String(format: "Adapter supplies %.1f watts", flow.adapterIn)) }
        if flow.adapterToBattery > 0 { parts.append(String(format: "%.1f watts charge the battery", flow.adapterToBattery)) }
        if flow.batteryToSystem > 0 { parts.append(String(format: "battery supplies %.1f watts", flow.batteryToSystem)) }
        parts.append(String(format: "system uses %.1f watts", flow.systemLoad))
        return parts.joined(separator: ", ")
    }
}
