import AppKit
import CalmaKit
import SwiftUI

@main
struct CalmaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppearanceKeys.showPercentage) private var showPercentage = true

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model, showPercentage: showPercentage)
        }
        .menuBarExtraStyle(.window)

        Window("Calma Settings", id: SettingsWindow.id) {
            SettingsRootView()
                .environmentObject(appDelegate.model)
                .environmentObject(appDelegate.updateChecker)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum SettingsWindow {
    static let id = "settings"
}

enum AppearanceKeys {
    static let showPercentage = "showPercentageInMenuBar"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let updateChecker = UpdateChecker()

    override init() {
        if CommandLine.arguments.contains(ScreenshotRenderer.flag) {
            model = AppModel(preview: PreviewData.status())
        } else {
            model = AppModel()
        }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: ScreenshotRenderer.flag) {
            let directory = CommandLine.arguments.indices.contains(index + 1)
                ? CommandLine.arguments[index + 1]
                : FileManager.default.currentDirectoryPath + "/screenshots"
            ScreenshotRenderer.renderAll(to: URL(fileURLWithPath: directory))
            exit(0)
        }

        model.start()
        if UserDefaults.standard.bool(forKey: UpdateChecker.enabledKey) {
            updateChecker.checkNow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.appWillQuit()
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        guard let command = URLCommand.command(for: url, currentSettings: model.status?.settings) else {
            model.lastError = String(localized: "Unknown Calma link: \(string)")
            return
        }
        model.send(command)
    }
}
