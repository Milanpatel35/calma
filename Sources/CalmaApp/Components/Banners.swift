import AppKit
import CalmaKit
import SwiftUI

/// A soft, rounded callout used for helper, firmware and error notices.
struct Callout<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let message: Text
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Font.callout.weight(.semibold))
                message
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .wrapsLines()
                HStack(spacing: 8) { actions() }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.22)))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Lets multi-line text wrap instead of truncating inside fixed-width layouts.
    func wrapsLines() -> some View { fixedSize(horizontal: false, vertical: true) }
}

/// "The helper isn't installed" notice.
struct HelperBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.helperState {
        case .notInstalled:
            Callout(icon: "lock.shield", tint: .accentColor, title: "Install the Calma helper",
                    message: Text("A small background helper controls charging. It needs your administrator password once.")) {
                Button("Install Helper…") { model.installHelper() }
                    .controlSize(.small)
                    .disabled(model.busy)
            }
        case .error(let message):
            Callout(icon: "exclamationmark.triangle", tint: .orange, title: "Can't reach the helper",
                    message: Text(message)) {
                Button("Retry") { model.refresh() }.controlSize(.small)
                Button("Reinstall…") { model.installHelper() }.controlSize(.small)
            }
        case .checking, .running:
            EmptyView()
        }
    }
}

/// Honest notice for firmware without a documented charge-control key.
struct FirmwareBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.helperState == .running, model.capabilities.backend == .unsupported {
            Callout(icon: "info.circle", tint: .blue, title: "Monitoring mode",
                    message: firmwareMessage) {
                Button("Learn more") {
                    NSWorkspace.shared.open(CalmaPaths.repositoryURL.appendingPathComponent("blob/main/docs/SMC_KEYS.md"))
                }
                .controlSize(.small)
                if model.capabilities.nativeChargeLimit != nil {
                    Button("Battery Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var firmwareMessage: Text {
        var text = Text("Your Mac's firmware (macOS 27+) doesn't expose a documented charge-control key yet. Calma is in monitoring mode.")
        if let native = model.capabilities.nativeChargeLimit {
            text = text + Text(" ") + Text("macOS's built-in charge limit is set to \(native)%.")
        }
        return text
    }
}

/// Transient error / info toast.
struct MessageBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let error = model.lastError {
            Callout(icon: "xmark.octagon", tint: .red, title: "Something went wrong", message: Text(error)) {
                Button("Dismiss") { model.lastError = nil }.controlSize(.small)
            }
        } else if let info = model.infoMessage {
            Callout(icon: "checkmark.circle", tint: .green, title: "Done", message: Text(info)) {
                Button("OK") { model.infoMessage = nil }.controlSize(.small)
            }
        }
    }
}
