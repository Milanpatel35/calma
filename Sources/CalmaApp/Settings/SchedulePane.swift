import CalmaKit
import SwiftUI

struct SchedulePane: View {
    @EnvironmentObject var model: AppModel
    @State private var showingAdd = false

    var body: some View {
        let tasks = model.settings.schedule
        PaneForm(pane: .schedule, subtitle: "Run actions automatically — daily, weekly or whenever you need.") {
            Section {
                if tasks.isEmpty {
                    Text("No scheduled tasks yet. For example: set the limit to 100% every Friday evening before the weekend.")
                        .foregroundStyle(.secondary)
                        .wrapsLines()
                }
                ForEach(tasks) { task in
                    TaskRow(task: task)
                }
                HStack {
                    Spacer()
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Task…", systemImage: "plus")
                    }
                    .disabled(!model.canControl)
                }
            } header: {
                Text("Tasks")
            }

            Section("History") {
                let history = model.status?.taskHistory ?? []
                if history.isEmpty {
                    Text("Tasks that have run will show up here.").foregroundStyle(.secondary)
                }
                ForEach(history.prefix(12)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.taskName)
                            Text(entry.result).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddTaskSheet { task in
                model.updateSettings { $0.schedule.append(task) }
            }
        }
    }
}

private struct TaskRow: View {
    @EnvironmentObject var model: AppModel
    let task: ScheduledTask

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name.isEmpty ? task.action.title : task.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { task.enabled }, set: { enabled in
                model.updateSettings { settings in
                    if let index = settings.schedule.firstIndex(where: { $0.id == task.id }) {
                        settings.schedule[index].enabled = enabled
                    }
                }
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            Button(role: .destructive) {
                model.updateSettings { $0.schedule.removeAll { $0.id == task.id } }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Delete \(task.name)"))
        }
        .disabled(!model.canControl)
    }

    private var icon: String {
        switch task.action {
        case .setChargeLimit: return "slider.horizontal.3"
        case .fullCharge: return "bolt.fill"
        case .recalibrate: return "arrow.triangle.2.circlepath"
        case .pauseCharging: return "pause.fill"
        case .drainTo: return "arrow.down.circle"
        }
    }

    private var detail: String {
        var parts = [task.action.title, task.repeatRule.title]
        if let next = ScheduleCalculator.nextFire(for: task, after: Date()) {
            parts.append(String(localized: "next \(next.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct AddTaskSheet: View {
    enum ActionKind: String, CaseIterable, Identifiable {
        case setLimit, fullCharge, recalibrate, pause, resume, drain
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .setLimit: return "Set charge limit"
            case .fullCharge: return "Full charge once"
            case .recalibrate: return "Start recalibration"
            case .pause: return "Pause charging"
            case .resume: return "Resume charging"
            case .drain: return "Drain to"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let onAdd: (ScheduledTask) -> Void

    @State private var name = ""
    @State private var kind: ActionKind = .setLimit
    @State private var value = 80
    @State private var repeatRule: RepeatRule = .daily
    @State private var date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var runIfMissed = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("New Task") {
                    TextField("Name", text: $name, prompt: Text("e.g. Weekend trip"))
                    Picker("Action", selection: $kind) {
                        ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
                    }
                    if kind == .setLimit || kind == .drain {
                        Stepper(value: $value, in: CalmaLimits.minimumChargeLimit...100, step: 5) {
                            LabeledContent("Level", value: "\(value)%")
                        }
                    }
                    Picker("Repeat", selection: $repeatRule) {
                        ForEach(RepeatRule.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    DatePicker("Starts", selection: $date)
                    ExplainedToggle(title: "Run if missed",
                                    explanation: "If the Mac was asleep or off at that time, run the task when it wakes.",
                                    isOn: $runIfMissed)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Task") {
                    let task = ScheduledTask(name: name.isEmpty ? action.title : name, action: action,
                                             repeatRule: repeatRule, startDate: date, runIfMissed: runIfMissed)
                    onAdd(task)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 460, height: 440)
    }

    private var action: ScheduledAction {
        switch kind {
        case .setLimit: return .setChargeLimit(value)
        case .fullCharge: return .fullCharge
        case .recalibrate: return .recalibrate
        case .pause: return .pauseCharging(true)
        case .resume: return .pauseCharging(false)
        case .drain: return .drainTo(value)
        }
    }
}
