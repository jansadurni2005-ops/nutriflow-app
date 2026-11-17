import SwiftUI
import SwiftData

/// Rutinas semanales: plantillas que generan bloques automáticamente de lunes a domingo,
/// con horarios distintos según el día.
struct RoutinesView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \RoutineItem.startMinutes) private var routines: [RoutineItem]
    @State private var weekday = Calendar.current.component(.weekday, from: Date())
    @State private var editing: RoutineItem?
    @State private var creating = false

    private let order: [(Int, String)] = [(2, "Lun"), (3, "Mar"), (4, "Mié"), (5, "Jue"), (6, "Vie"), (7, "Sáb"), (1, "Dom")]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.0) { day, label in
                        let count = routines.filter { $0.isActive && $0.weekdays.contains(day) }.count
                        Button { weekday = day; Haptics.selection() } label: {
                            VStack(spacing: 3) {
                                Text(label).font(.system(size: 12, weight: .bold))
                                Text("\(count)").font(.metric(14))
                            }
                            .foregroundStyle(weekday == day ? .black : Palette.textPrimary)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(weekday == day ? Palette.accent : Palette.card))
                        }
                        .buttonStyle(.plain)
                    }
                }

                let items = routines.filter { $0.weekdays.contains(weekday) }
                if routines.isEmpty {
                    EmptyStateView(icon: "repeat", title: "Sin rutinas",
                                   message: "Crea plantillas que se repitan cada semana. Puedes empezar con una jornada tipo de ejemplo y ajustarla.",
                                   actionTitle: "Usar jornada de ejemplo") {
                        ScheduleService.seedExampleRoutine(context: context)
                        coordinator.didChangeData()
                        coordinator.showToast("Rutina de lunes a viernes creada.", style: .success)
                    }
                } else if items.isEmpty {
                    Text("Nada programado este día.").font(.subheadline).foregroundStyle(Palette.textTertiary).card()
                } else {
                    let totalWork = items.filter { $0.isActive && $0.kind.countsAsWork }
                        .reduce(0) { $0 + max(0, $1.endMinutes - $1.startMinutes) }
                    HStack {
                        Text("\(items.count) bloques · \(TimeFormat.duration(Double(totalWork * 60))) de trabajo")
                            .font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                        Spacer()
                    }
                    ForEach(items) { item in
                        Button { editing = item } label: { routineRow(item) }.buttonStyle(.plain)
                    }
                }

                Button { creating = true } label: { Label("Añadir a la rutina", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle(tint: Palette.accent))

                Text("Los cambios se aplican a los días aún no empezados. Los bloques ya registrados no se modifican.")
                    .font(.caption).foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editing) { item in
            RoutineEditorView(item: item, defaultWeekday: weekday).presentationBackground(Palette.background)
        }
        .sheet(isPresented: $creating) {
            RoutineEditorView(item: nil, defaultWeekday: weekday).presentationBackground(Palette.background)
        }
    }

    private func routineRow(_ item: RoutineItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: item.colorHex)).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text("\(item.kind.label) · \(weekdaysLabel(item.weekdays))")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Text("\(Self.hhmm(item.startMinutes))–\(Self.hhmm(item.endMinutes))").font(.metric(16)).foregroundStyle(Palette.textPrimary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.card))
        .opacity(item.isActive ? 1 : 0.45)
    }

    static func hhmm(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    private func weekdaysLabel(_ days: Set<Int>) -> String {
        if days == [2, 3, 4, 5, 6] { return "Lun–Vie" }
        if days.count == 7 { return "Todos los días" }
        return order.filter { days.contains($0.0) }.map(\.1).joined(separator: " ")
    }
}

struct RoutineEditorView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: RoutineItem?
    let defaultWeekday: Int

    @State private var title = ""
    @State private var weekdays: Set<Int> = []
    @State private var start = Date()
    @State private var end = Date()
    @State private var kind: BlockKind = .work
    @State private var category: BlockCategory = .business
    @State private var priority: BlockPriority = .medium
    @State private var objective = ""
    @State private var colorHex = "FF6500"
    @State private var alarmBefore = true
    @State private var alarmStart = true
    @State private var alarmEnd = true
    @State private var sound: AlarmSound = .pulse
    @State private var policyOverride: ScreenTimeShared.Policy? = nil
    @State private var isActive = true
    @State private var confirmDelete = false

    private var startMinutes: Int { ScheduleService.minutes(of: start) }
    private var endMinutes: Int { ScheduleService.minutes(of: end) }
    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty && endMinutes > startMinutes }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $title).font(.title3.weight(.semibold))
                    TextField("Objetivo", text: $objective, axis: .vertical)
                    Toggle("Activa", isOn: $isActive).tint(Palette.accent)
                }
                .listRowBackground(Palette.card)

                Section("Días") {
                    WeekdayPicker(selection: $weekdays)
                    Text("Para horarios distintos según el día, crea otro elemento con esos días.")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                }
                .listRowBackground(Palette.card)

                Section("Horario") {
                    DatePicker("Inicio", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Fin", selection: $end, displayedComponents: .hourAndMinute)
                    if endMinutes <= startMinutes {
                        Text("El fin debe ser posterior al inicio (mismo día).").font(.caption).foregroundStyle(Palette.danger)
                    }
                }
                .listRowBackground(Palette.card)

                Section("Tipo") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(BlockKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Picker("Categoría", selection: $category) {
                        ForEach(BlockCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Picker("Prioridad", selection: $priority) {
                        ForEach(BlockPriority.allCases) { Text($0.label).tag($0) }
                    }
                    if kind.tracksDistractions {
                        Picker("Apps distractoras", selection: $policyOverride) {
                            Text("Según ajustes").tag(Optional<ScreenTimeShared.Policy>.none)
                            Text("No medir ni bloquear").tag(ScreenTimeShared.Policy?.some(.off))
                            Text("Medir uso").tag(ScreenTimeShared.Policy?.some(.measure))
                            Text("Bloquear").tag(ScreenTimeShared.Policy?.some(.block))
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Palette.blockColors, id: \.self) { hex in
                                Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 2.5 : 0))
                                    .onTapGesture { colorHex = hex }
                            }
                        }
                    }
                }
                .listRowBackground(Palette.card)

                Section("Alarmas") {
                    Toggle("Aviso previo", isOn: $alarmBefore)
                    Toggle("Inicio", isOn: $alarmStart)
                    Toggle("Fin", isOn: $alarmEnd)
                    Picker("Sonido", selection: $sound) {
                        ForEach(AlarmSound.allCases) { Text($0.label).tag($0) }
                    }
                }
                .listRowBackground(Palette.card)
                .tint(Palette.accent)

                if item != nil {
                    Section {
                        Button("Eliminar de la rutina", role: .destructive) { confirmDelete = true }
                    }
                    .listRowBackground(Palette.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(item == nil ? "Nuevo en rutina" : "Editar rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save(); dismiss() }.disabled(!isValid).fontWeight(.bold)
                }
            }
            .confirmationDialog("¿Eliminar este elemento de la rutina?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    if let item { ScheduleService.deleteRoutine(item, context: context); coordinator.didChangeData() }
                    dismiss()
                }
            } message: {
                Text("Se eliminarán sus bloques futuros pendientes. El historial se conserva.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let today = Date()
        if let item {
            title = item.title
            weekdays = item.weekdays
            start = ScheduleService.date(on: today, minutes: item.startMinutes)
            end = ScheduleService.date(on: today, minutes: item.endMinutes)
            kind = item.kind
            category = item.category
            priority = item.priority
            objective = item.objective
            colorHex = item.colorHex
            alarmBefore = item.alarmBefore
            alarmStart = item.alarmStart
            alarmEnd = item.alarmEnd
            sound = AlarmSound(rawValue: item.soundRaw) ?? .pulse
            policyOverride = item.policyRaw.flatMap(ScreenTimeShared.Policy.init(rawValue:))
            isActive = item.isActive
        } else {
            weekdays = [defaultWeekday]
            start = ScheduleService.date(on: today, minutes: 9 * 60)
            end = ScheduleService.date(on: today, minutes: 10 * 60)
            sound = coordinator.settings.notifications.defaultSound
        }
    }

    private func save() {
        guard isValid else { return }
        let routine: RoutineItem
        if let item {
            routine = item
        } else {
            routine = RoutineItem(title: title, weekdays: weekdays, startMinutes: startMinutes, endMinutes: endMinutes,
                                  kind: kind, category: category, colorHex: colorHex)
            context.insert(routine)
        }
        routine.title = title.trimmingCharacters(in: .whitespaces)
        routine.weekdays = weekdays
        routine.startMinutes = startMinutes
        routine.endMinutes = endMinutes
        routine.kind = kind
        routine.category = category
        routine.priority = priority
        routine.objective = objective
        routine.colorHex = colorHex
        routine.alarmBefore = alarmBefore
        routine.alarmStart = alarmStart
        routine.alarmEnd = alarmEnd
        routine.soundRaw = sound.rawValue
        routine.policyRaw = kind.tracksDistractions ? policyOverride?.rawValue : nil
        routine.isActive = isActive
        try? context.save()
        ScheduleService.applyRoutineChange(routine, context: context)
        // Si hoy o mañana aún no se habían generado, generarlos ahora.
        ScheduleService.ensureRoutines(for: Date(), context: context)
        coordinator.didChangeData()
        Haptics.success()
    }
}
