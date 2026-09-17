import AppKit
import CalmaKit
import SwiftUI

/// Renders real Calma views to PNG for the README and website.
///
///     .build/release/CalmaApp --render-screenshots screenshots
///
/// Views are hosted in offscreen windows and captured with `cacheDisplay`, so AppKit-backed
/// controls (toggles, sliders, pickers) render exactly as they do on screen.
@MainActor
enum ScreenshotRenderer {
    static let flag = "--render-screenshots"

    static func renderAll(to directory: URL) {
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let paused = AppModel(preview: PreviewData.status())
        let charging = AppModel(preview: PreviewData.chargingStatus())
        let updates = UpdateChecker()

        let popoverSize = CGSize(width: 320, height: 0)
        let settingsSize = CGSize(width: 920, height: 640)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            render(PopoverView(opaqueBackground: true).environmentObject(paused),
                   size: popoverSize, dark: dark, to: directory.appendingPathComponent("popover-\(suffix).png"))
            render(settings(.dashboard, model: charging, updates: updates),
                   size: settingsSize, dark: dark, to: directory.appendingPathComponent("dashboard-\(suffix).png"))
        }
        render(settings(.charge, model: paused, updates: updates), size: settingsSize, dark: false,
               to: directory.appendingPathComponent("charge.png"))
        render(settings(.protection, model: paused, updates: updates), size: settingsSize, dark: false,
               to: directory.appendingPathComponent("protection.png"))
        render(settings(.schedule, model: paused, updates: updates), size: settingsSize, dark: false,
               to: directory.appendingPathComponent("schedule.png"))
        render(settings(.advanced, model: paused, updates: updates), size: settingsSize, dark: true,
               to: directory.appendingPathComponent("advanced.png"))
        print("Screenshots written to \(directory.path)")
    }

    private static func settings(_ pane: SettingsPane, model: AppModel, updates: UpdateChecker) -> some View {
        SettingsRootView(initialPane: pane)
            .environmentObject(model)
            .environmentObject(updates)
    }

    /// Hosts `view` in an offscreen window and writes a PNG at the display's backing scale (2x on Retina).
    /// A height of 0 means "fit the content".
    private static func render<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.controlActiveState, .key)
            .toggleStyle(ActiveSwitchStyle()))
        hosting.appearance = appearance

        var frame = CGRect(origin: .zero, size: size)
        if size.height == 0 {
            hosting.frame = CGRect(x: 0, y: 0, width: size.width, height: 2000)
            frame.size.height = ceil(hosting.fittingSize.height)
        }

        let window = SnapshotWindow(contentRect: frame, styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        hosting.frame = frame

        // Let SwiftUI finish layout, async list population and first-draw animations.
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("  \(url.lastPathComponent) \(rep.pixelsWide)×\(rep.pixelsHigh)")
        }
        window.orderOut(nil)
    }
}

/// Reports itself as key so AppKit draws active-state controls (accent switches, selection).
private final class SnapshotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

/// Offscreen captures draw native switches in their inactive grey. This mirrors the active
/// appearance (accent track when on) so screenshots match what people see on screen.
private struct ActiveSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(configuration.isOn ? 0 : 0.08), lineWidth: 0.5))
                .frame(width: 26, height: 15)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 0.8, y: 0.5)
                        .frame(width: 13, height: 13)
                        .padding(1)
                }
        }
    }
}
