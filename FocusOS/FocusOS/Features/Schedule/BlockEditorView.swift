import SwiftUI
import SwiftData

/// Crear / editar un bloque con todos sus campos.
struct BlockEditorView: View {
    enum Mode {
        case create(day: Date, start: Date? = nil)
        case edit(WorkBlock)
    }

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var kind: BlockKind = .work
    @State private var category: BlockCategory = .business
    @State private var priority: BlockPriority = .medium
    @State private var objective = ""
    @State private var notes = ""
    @State private var colorHex = "FF6500"
    @State private var alarmBefore = true
    @State private var alarmStart = true
    @State private var alarmEnd = true
    @State private var sound: AlarmSound = .pulse
    @State private var policyOverride: ScreenTimeShared.Policy? = nil
    @State private var status: BlockStatus = .pending
    @State private var workedMinutes: Double = 0
    @State private var repeatWeekly = false
    @State private var weekdays: Set<Int> = []
    @State private var loaded = false
    @State private var confirmDelete = false

    private var existing: WorkBlock? {
        if case .edit(let block) = mode { return block }
        return nil
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && end > start
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre de la tarea", text: $title)
                        .font(.title3.weight(.semibold))
                    TextField("Objetivo concreto", text: $objective, axis: .vertical)
                }
                .listRowBackground(Palette.card)

                Section("Horario") {
                    DatePicker("Inicio", selection: $start)
                    DatePicker("Fin", selection: $end, in: start.addingTimeInterval(5 * 60)...)
                    HStack {
                        Text("Duración").foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text(TimeFormat.duration(max(0, end.timeIntervalSince(start)))).font(.metric(17))
                    }
                    if !isValid && end <= start {
                        Text("La hora de fin debe ser posterior al inicio.").font(.caption).foregroundStyle(Palette.danger)
                    }
                    if let conflict = conflictTitle {
                        Label("Se solapa con «\(conflict)»", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Palette.warning)
                    }
                }
                .listRowBackground(Palette.card)

                Section("Tipo y prioridad") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(BlockKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Picker("Categoría", selection: $category) {
                        ForEach(BlockCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Picker("Prioridad", selection: $priority) {
                        ForEach(BlockPriority.allCases) { Text("\($0.short) · \($0.label)").tag($0) }
                    }
                    colorPicker
                }
                .listRowBackground(Palette.card)

                if kind.tracksDistractions {
                    Section {
                        Picker("Apps distractoras", selection: $policyOverride) {
                            Text("Según ajustes (\(policyLabel(defaultPolicy)))").tag(Optional<ScreenTimeShared.Policy>.none)
                            Text("No medir ni bloquear").tag(ScreenTimeShared.Policy?.some(.off))
                            Text("Medir uso").tag(ScreenTimeShared.Policy?.some(.measure))
                            Text("Bloquear").tag(ScreenTimeShared.Policy?.some(.block))
                        }
                    } header: {
                        Text("Distracciones")
                    } footer: {
                        Text("Ej.: en un bloque de contenido puedes permitir Instagram eligiendo «No medir ni bloquear».")
                    }
                    .listRowBackground(Palette.card)
                }

                Section("Alarmas") {
                    Toggle("Aviso \(coordinator.settings.notifications.preAlertMinutes) min antes", isOn: $alarmBefore)
                    Toggle("Alarma de inicio", isOn: $alarmStart)
                    Toggle("Alarma de finalización", isOn: $alarmEnd)
                    Picker("Sonido", selection: $sound) {
                        ForEach(AlarmSound.allCases) { Text($0.label).tag($0) }
                    }
                }
                .listRowBackground(Palette.card)
                .tint(Palette.accent)

                Section {
                    if let block = existing, block.routineID != nil {
                        Label("Este bloque pertenece a una rutina semanal. Edítala en Schedule › Rutinas para cambiar todos los días.",
                              systemImage: "repeat")
                            .font(.footnote).foregroundStyle(Palette.textSecondary)
                    } else {
                        Toggle("Repetir cada semana", isOn: $repeatWeekly).tint(Palette.accent)
                        if repeatWeekly {
                            WeekdayPicker(selection: $weekdays)
                        }
                    }
                } header: {
                    Text("Repetición")
                }
                .listRowBackground(Palette.card)

                if existing != nil {
                    Section {
                        Picker("Estado", selection: $status) {
                            ForEach(BlockStatus.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                        }
                        if status == .completed || (existing?.workedSeconds ?? 0) > 0 {
                            Stepper(value: $workedMinutes, in: 0...720, step: 5) {
                                HStack {
                                    Text("Tiempo trabajado")
                                    Spacer()
                                    Text("\(Int(workedMinutes)) min").font(.metric(16))
                                }
                            }
                        }
                        if let block = existing {
                            if let delay = block.delaySeconds {
                                LabeledContent("Retraso al empezar", value: TimeFormat.duration(delay))
                            }
                            if let actualStart = block.actualStart {
                                LabeledContent("Inicio real", value: TimeFormat.hhmm(actualStart))
                            }
                            if let actualEnd = block.actualEnd {
                                LabeledContent("Fin real", value: TimeFormat.hhmm(actualEnd))
                            }
                            if block.distractionSeconds > 0 {
                                LabeledContent("Distracciones", value: TimeFormat.duration(block.distractionSeconds))
                            }
                        }
                    } header: {
                        Text("Registro")
                    } footer: {
                        Text("Si cambias el tiempo trabajado a mano, se marcará como dato manual.")
                    }
                    .listRowBackground(Palette.card)
                }

                Section("Notas") {
                    TextField("Notas", text: $notes, axis: .vertical).lineLimit(3...8)
                }
                .listRowBackground(Palette.card)

                if let block = existing {
                    Section {
                        if block.status != .completed && block.kind != .breakTime {
                            Button {
                                save()
                                coordinator.startSession(block: block)
                                dismiss()
                            } label: { Label("Empezar ahora", systemImage: "play.fill") }
                            Button {
                                ScheduleService.moveToNextDay(block, context: context)
                                coordinator.didChangeData()
                                coordinator.showToast("Tarea movida a mañana.", style: .success)
                                dismiss()
                            } label: { Label("Mover a mañana", systemImage: "arrow.uturn.forward") }
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Eliminar bloque", systemImage: "trash")
                        }
                        .disabled(coordinator.activeSession?.blockID == block.id)
                    }
                    .listRowBackground(Palette.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(existing == nil ? "Nuevo bloque" : "Editar bloque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save(); dismiss() }.disabled(!isValid).fontWeight(.bold)
                }
            }
            .confirmationDialog("¿Eliminar este bloque?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    if let block = existing {
                        context.delete(block)
                        coordinator.didChangeData()
                    }
                    dismiss()
                }
            } message: {
                Text("Se borrará también su registro de tiempo de este día.")
            }
            .onAppear(perform: load)
            .onChange(of: start) { _, newStart in
                // Si el inicio supera al fin, se recoloca el fin con 1 h de duración.
                if end <= newStart { end = newStart.addingTimeInterval(60 * 60) }
            }
            .onChange(of: kind) { _, newKind in
                guard loaded, existing == nil else { return }
                if newKind == .breakTime { colorHex = "30D5C8"; alarmBefore = false }
                if newKind == .deepWork { colorHex = "FF6500" }
            }
        }
    }

    private var defaultPolicy: ScreenTimeShared.Policy {
        coordinator.settingsStore.policy(for: kind)
    }

    private func policyLabel(_ policy: ScreenTimeShared.Policy) -> String {
        switch policy {
        case .off: return "no medir"
        case .measure: return "medir"
        case .block: return "bloquear"
        }
    }

    private var conflictTitle: String? {
        let others = DayDataService.blocks(on: start, context: context).filter { $0.id != existing?.id }
        return others.first { $0.start < end && start < $0.end }?.title
    }

    private var colorPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Palette.blockColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 2.5 : 0))
                        .onTapGesture { colorHex = hex; Haptics.selection() }
                        .accessibilityLabel("Color \(hex)")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func load() {
        guard !loaded else { return }
        let prefs = coordinator.settings.notifications
        switch mode {
        case .create(let day, let suggested):
            let s = suggested ?? ScheduleService.date(on: day, minutes: 9 * 60)
            start = s
            end = s.addingTimeInterval(60 * 60)
            sound = prefs.defaultSound
            weekdays = [Calendar.current.component(.weekday, from: s)]
        case .edit(let block):
            title = block.title
            start = block.start
            end = block.end
            kind = block.kind
            category = block.category
            priority = block.priority
            objective = block.objective
            notes = block.notes
            colorHex = block.colorHex
            alarmBefore = block.alarmBefore
            alarmStart = block.alarmStart
            alarmEnd = block.alarmEnd
            sound = block.sound
            policyOverride = block.policyOverride
            status = block.status
            workedMinutes = (block.workedSeconds / 60).rounded()
            weekdays = [Calendar.current.component(.weekday, from: block.start)]
        }
        DispatchQueue.main.async { loaded = true }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, end > start else { return }
        let block: WorkBlock
        if let existing {
            block = existing
            block.title = trimmed
            block.reschedule(start: start, end: end)
            let manualWorked = workedMinutes * 60
            if abs(manualWorked - block.workedSeconds) >= 60 {
                block.workedSeconds = manualWorked
                block.workedIsManual = true
            }
            if status != block.status {
                block.status = status
                if status == .completed && block.actualEnd == nil { block.actualEnd = min(Date(), block.end) }
            }
        } else {
            block = WorkBlock(title: trimmed, start: start, end: end)
            context.insert(block)
        }
        block.kind = kind
        block.category = category
        block.priority = priority
        block.objective = objective
        block.notes = notes
        block.colorHex = colorHex
        block.alarmBefore = alarmBefore
        block.alarmStart = alarmStart
        block.alarmEnd = alarmEnd
        block.sound = sound
        block.policyOverride = kind.tracksDistractions ? policyOverride : nil

        if repeatWeekly && block.routineID == nil && !weekdays.isEmpty {
            ScheduleService.makeRoutine(from: block, weekdays: weekdays, context: context)
        }
        coordinator.didChangeData()
        Haptics.success()
    }
}

/// Selector de días de la semana (L M X J V S D).
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    // Calendar: 1 = domingo … 7 = sábado. Se muestran de lunes a domingo.
    private let order: [(Int, String)] = [(2, "L"), (3, "M"), (4, "X"), (5, "J"), (6, "V"), (7, "S"), (1, "D")]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.0) { day, label in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                    Haptics.selection()
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isOn ? .black : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? Palette.accent : Palette.cardElevated))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
