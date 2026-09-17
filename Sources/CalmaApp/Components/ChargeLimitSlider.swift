import CalmaKit
import SwiftUI

/// Charge Limit slider (20–100 %) that also shows the current level and the Drift Range band.
struct ChargeLimitSlider: View {
    /// Committed limit.
    let limit: Int
    let level: Int?
    /// Width of the Drift Range band in percent, or nil when Drift Range is off.
    let driftRange: Int?
    let enabled: Bool
    let onCommit: (Int) -> Void

    @State private var dragValue: Int?
    @FocusState private var focused: Bool

    private let minimum = CalmaLimits.minimumChargeLimit
    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 18

    private var shown: Int { dragValue ?? limit }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - thumbSize
            let x = { (value: Int) -> CGFloat in thumbSize / 2 + width * CGFloat(value) / 100 }
            let trackY: CGFloat = 14

            ZStack(alignment: .topLeading) {
                // Track
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: trackHeight)
                    .offset(y: trackY - trackHeight / 2)

                // Allowed charge (up to the limit)
                Capsule()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: x(shown), height: trackHeight)
                    .offset(y: trackY - trackHeight / 2)
                    .opacity(enabled ? 1 : 0.4)

                // Current level marker: a small notch above the track.
                if let level {
                    let clamped = min(100, max(0, level))
                    Triangle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 8, height: 5)
                        .offset(x: x(clamped) - 4, y: 0)
                        .accessibilityHidden(true)
                }

                // Drift Range band: dashed bracket in its own lane under the track.
                if let driftRange, shown < 100 {
                    let lower = max(0, shown - driftRange)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])))
                        .frame(width: max(6, x(shown) - x(lower)), height: 7)
                        .offset(x: x(lower), y: trackY + trackHeight / 2 + 5)
                        .accessibilityHidden(true)
                }

                // Thumb
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: focused ? 3 : 0).padding(-3))
                    .offset(x: x(shown) - thumbSize / 2, y: trackY - thumbSize / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        dragValue = value(at: gesture.location.x, width: width)
                    }
                    .onEnded { gesture in
                        guard enabled else { return }
                        let final = value(at: gesture.location.x, width: width)
                        dragValue = nil
                        if final != limit { onCommit(final) }
                    }
            )
        }
        .frame(height: 36)
        .focusable(enabled)
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: step(-1)
            case .right, .up: step(1)
            default: break
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Charge limit"))
        .accessibilityValue(Text("\(shown) percent"))
        .accessibilityHint(driftRange.map { Text("Charging resumes below \(max(0, shown - $0)) percent") } ?? Text(""))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(5)
            case .decrement: step(-5)
            @unknown default: break
            }
        }
        .disabled(!enabled)
    }

    private func value(at location: CGFloat, width: CGFloat) -> Int {
        let raw = (location - thumbSize / 2) / max(1, width) * 100
        return min(100, max(minimum, Int(raw.rounded())))
    }

    private func step(_ delta: Int) {
        guard enabled else { return }
        let next = min(100, max(minimum, limit + delta))
        if next != limit { onCommit(next) }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
