import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    enum Mode: String, CaseIterable { case day = "Día", routines = "Rutinas" }

    @State private var mode: Mode = .day
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset = 0
    @State private var newBlockStart: Date?
    @State private var showImport = false
    @State private var showDatePicker = false
    @State private var confirmDuplicate = false

    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        // Semana que empieza en lunes.
        let mondayOffset = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -mondayOffset + weekOffset * 7, to: today) ?? today
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(overline: selectedDay.formatted(.dateTime.month(.wide).year()), title: "Schedule") {
                HStack(spacing: 8) {
                    Menu {
                        Button { newBlockStart = defaultNewStart() } label: { Label("Nuevo bloque", systemImage: "plus") }
                        Button { confirmDuplicate = true } label: { Label("Duplicar día anterior aquí", systemImage: "doc.on.doc") }
                        Button { duplicateToNextDay() } label: { Label("Copiar este día a mañana", systemImage: "arrow.right.doc.on.clipboard") }
                        Button { showImport = true } label: { Label("Importar de Calendario / Google", systemImage: "calendar.badge.plus") }
                        Button { showDatePicker = true } label: { Label("Ir a fecha…", systemImage: "calendar") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.textPrimary)
                            .frame(width: 40, height: 40).background(Circle().fill(Palette.card))
                    }
                    Button { newBlockStart = defaultNewStart() } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 40, height: 40).background(Circle().fill(Palette.accent))
                    }
                    .accessibilityLabel("Nuevo bloque")
                }
            }
            .padding(.horizontal, 16)

            Picker("Modo", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if mode == .day {
                weekStrip
                DayTimelineView(day: selectedDay) { start in newBlockStart = start }
                    .id(selectedDay)
            } else {
                RoutinesView()
            }
        }
        .screenBackground()
        .sheet(item: Binding(get: { newBlockStart.map(IdentifiableDate.init) }, set: { newBlockStart = $0?.date })) { item in
            BlockEditorView(mode: .create(day: selectedDay, start: item.date)).presentationBackground(Palette.background)
        }
        .sheet(isPresented: $showImport) {
            CalendarImportView(day: selectedDay).presentationBackground(Palette.background)
        }
        .sheet(isPresented: $showDatePicker) {
            VStack {
                DatePicker("Fecha", selection: Binding(get: { selectedDay }, set: { jump(to: $0) }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Palette.accent)
                Button("Listo") { showDatePicker = false }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.background)
        }
        .confirmationDialog("¿Duplicar la planificación del día anterior en \(selectedDay.formatted(.dateTime.weekday(.wide).day()))?",
                            isPresented: $confirmDuplicate, titleVisibility: .visible) {
            Button("Duplicar") {
                let previous = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
                let n = ScheduleService.duplicate(day: previous, to: selectedDay, context: context)
                coordinator.didChangeData()
                coordinator.showToast(n > 0 ? "\(n) bloques duplicados." : "No había bloques nuevos que copiar.", style: n > 0 ? .success : .info)
            }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear { ScheduleService.ensureRoutines(for: selectedDay, context: context) }
        .onChange(of: selectedDay) { _, day in ScheduleService.ensureRoutines(for: day, context: context) }
    }

    private func defaultNewStart() -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) {
            // Siguiente múltiplo de 15 min.
            let now = Date()
            let minutes = ScheduleService.minutes(of: now)
            return ScheduleService.date(on: selectedDay, minutes: min(23 * 60, ((minutes / 15) + 1) * 15))
        }
        return ScheduleService.date(on: selectedDay, minutes: 9 * 60)
    }

    private func duplicateToNextDay() {
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        let n = ScheduleService.duplicate(day: selectedDay, to: next, context: context)
        coordinator.didChangeData()
        coordinator.showToast(n > 0 ? "\(n) bloques copiados a mañana." : "Mañana ya tenía estos bloques.", style: n > 0 ? .success : .info)
    }

    private func jump(to date: Date) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        selectedDay = day
        let today = cal.startOfDay(for: Date())
        let weeks = cal.dateComponents([.day], from: weekDays.first ?? today, to: day).day ?? 0
        weekOffset += Int(floor(Double(weeks) / 7.0))
    }

    // MARK: Tira semanal

    private var weekStrip: some View {
        HStack(spacing: 6) {
            Button { withAnimation { weekOffset -= 1 } } label: {
                Image(systemName: "chevron.left").font(.caption.weight(.bold)).foregroundStyle(Palette.textSecondary).frame(width: 22)
            }
            ForEach(weekDays, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                let isToday = Calendar.current.isDateInToday(day)
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3)) { selectedDay = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? .black.opacity(0.7) : Palette.textTertiary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.metric(17))
                            .foregroundStyle(isSelected ? .black : (isToday ? Palette.accent : Palette.textPrimary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? Palette.accent : Palette.card))
                }
                .buttonStyle(.plain)
            }
            Button { withAnimation { weekOffset += 1 } } label: {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.textSecondary).frame(width: 22)
            }
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Línea temporal del día con arrastre

struct DayTimelineView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Query private var blocks: [WorkBlock]
    @State private var editingBlock: WorkBlock?

    let day: Date
    var onCreate: (Date) -> Void

    static let hourHeight: CGFloat = 96
    private let labelWidth: CGFloat = 48

    init(day: Date, onCreate: @escaping (Date) -> Void) {
        self.day = day
        self.onCreate = onCreate
        let (start, end) = DayDataService.dayRange(day)
        _blocks = Query(filter: #Predicate<WorkBlock> { $0.start >= start && $0.start < end }, sort: \.start)
    }

    private var hourRange: ClosedRange<Int> {
        let firstHour = blocks.map { Calendar.current.component(.hour, from: $0.start) }.min() ?? 6
        return min(5, firstHour)...24
    }

    private func y(for date: Date) -> CGFloat {
        let minutes = CGFloat(ScheduleService.minutes(of: date)) - CGFloat(hourRange.lowerBound * 60)
        return minutes / 60 * Self.hourHeight
    }

    var body: some View {
        let overlaps = ScheduleService.overlaps(in: blocks)
        let columns = Self.columnLayout(blocks)
        let workPlanned = blocks.filter { $0.kind.countsAsWork }.reduce(0) { $0 + $1.plannedSeconds }

        VStack(spacing: 8) {
            HStack {
                Label("\(blocks.count) bloques · \(TimeFormat.duration(workPlanned)) de trabajo", systemImage: "square.stack")
                Spacer()
                if !overlaps.isEmpty {
                    Label("\(overlaps.count) solapados", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 20)

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        GeometryReader { geo in
                            let width = geo.size.width - labelWidth - 12
                            ForEach(blocks) { block in
                                let layout = columns[block.id] ?? (0, 1)
                                let colWidth = width / CGFloat(layout.1)
                                DraggableBlock(block: block, hourHeight: Self.hourHeight, minuteOrigin: hourRange.lowerBound * 60,
                                               isOverlapping: overlaps.contains(block.id),
                                               onTap: { editingBlock = block },
                                               onCommit: { coordinator.didChangeData() })
                                    .frame(width: colWidth - 4)
                                    .offset(x: labelWidth + CGFloat(layout.0) * colWidth)
                            }
                        }
                        nowLine
                    }
                    .frame(height: CGFloat(hourRange.count) * Self.hourHeight)
                    .padding(.bottom, 150)
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    let target = Calendar.current.isDateInToday(day)
                        ? max(hourRange.lowerBound, Calendar.current.component(.hour, from: Date()) - 1)
                        : (blocks.first.map { Calendar.current.component(.hour, from: $0.start) } ?? 8)
                    proxy.scrollTo("hour-\(target)", anchor: .top)
                }
            }
            if blocks.isEmpty {
                Text("Mantén pulsado un bloque para moverlo · Toca una hora vacía para crear uno")
                    .font(.caption2).foregroundStyle(Palette.textTertiary).padding(.bottom, 100)
            }
        }
        .sheet(item: $editingBlock) { block in
            BlockEditorView(mode: .edit(block)).presentationBackground(Palette.background)
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(hourRange), id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", hour % 24))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: labelWidth - 8, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Rectangle().fill(Palette.stroke).frame(height: 1)
                        Spacer()
                    }
                }
                .frame(height: Self.hourHeight)
                .contentShape(Rectangle())
                .onTapGesture { onCreate(ScheduleService.date(on: day, minutes: hour * 60)) }
                .id("hour-\(hour)")
            }
        }
    }

    @ViewBuilder
    private var nowLine: some View {
        if Calendar.current.isDateInToday(day) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 0) {
                    Circle().fill(Palette.accent).frame(width: 9, height: 9)
                    Rectangle().fill(Palette.accent).frame(height: 1.5)
                }
                .padding(.leading, labelWidth - 4)
                .offset(y: y(for: context.date) - 4.5)
                .allowsHitTesting(false)
            }
        }
    }

    /// Reparte bloques solapados en columnas.
    static func columnLayout(_ blocks: [WorkBlock]) -> [UUID: (Int, Int)] {
        let sorted = blocks.sorted { $0.start < $1.start }
        var result: [UUID: (Int, Int)] = [:]
        var group: [WorkBlock] = []
        var groupEnd = Date.distantPast
        var columnsEnd: [Date] = []

        func flush() {
            let count = max(1, columnsEnd.count)
            for b in group { result[b.id] = (result[b.id]?.0 ?? 0, count) }
            group.removeAll(); columnsEnd.removeAll()
        }

        for block in sorted {
            if block.start >= groupEnd { flush() }
            if let index = columnsEnd.firstIndex(where: { $0 <= block.start }) {
                columnsEnd[index] = block.end
                result[block.id] = (index, 1)
            } else {
                columnsEnd.append(block.end)
                result[block.id] = (columnsEnd.count - 1, 1)
            }
            group.append(block)
            groupEnd = max(groupEnd, block.end)
        }
        flush()
        return result
    }
}

/// Bloque arrastrable (mantener pulsado + arrastrar para mover; tirador inferior para cambiar duración).
struct DraggableBlock: View {
    @Bindable var block: WorkBlock
    let hourHeight: CGFloat
    let minuteOrigin: Int
    let isOverlapping: Bool
    var onTap: () -> Void
    var onCommit: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var resizeOffset: CGFloat = 0
    @State private var isDragging = false

    private var pointsPerMinute: CGFloat { hourHeight / 60 }

    private func snapped(_ points: CGFloat) -> Int {
        let minutes = Int((points / pointsPerMinute).rounded())
        return (minutes / 5) * 5
    }

    var body: some View {
        let top = CGFloat(ScheduleService.minutes(of: block.start) - minuteOrigin) * pointsPerMinute
        // Altura exacta (mín. 12 pt) para que un bloque corto nunca invada el siguiente.
        let height = max(12, CGFloat(block.plannedSeconds / 60) * pointsPerMinute + resizeOffset - 2)
        let color = Color(hex: block.colorHex)
        let previewStart = block.start.addingTimeInterval(Double(snapped(dragOffset) * 60))
        let previewEnd = block.end.addingTimeInterval(Double(snapped(dragOffset) * 60 + snapped(resizeOffset) * 60))
        let locked = block.status == .inProgress

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(block.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: block.status.icon).font(.system(size: 11)).foregroundStyle(block.status.color)
            }
            if height > 38 {
                Text("\(TimeFormat.hhmm(previewStart))–\(TimeFormat.hhmm(previewEnd)) · \(block.kind.label)")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            if height > 64 && !block.objective.isEmpty {
                Text(block.objective).font(.system(size: 11)).foregroundStyle(Palette.textTertiary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(block.kind == .breakTime ? 0.12 : 0.22))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOverlapping ? Palette.warning : (isDragging ? color : .clear), lineWidth: isDragging ? 2 : 1)
        )
        .overlay(alignment: .bottom) {
            if !locked {
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 28, height: 4).padding(.bottom, 3)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .bottom)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                resizeOffset = max(-(CGFloat(block.plannedSeconds / 60) - 5) * pointsPerMinute, value.translation.height)
                            }
                            .onEnded { _ in
                                let delta = snapped(resizeOffset)
                                resizeOffset = 0
                                guard delta != 0 else { return }
                                block.reschedule(start: block.start, end: block.end.addingTimeInterval(Double(delta * 60)))
                                Haptics.tap()
                                onCommit()
                            }
                    )
            }
        }
        .opacity(block.status == .missed ? 0.55 : 1)
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(color: isDragging ? color.opacity(0.4) : .clear, radius: 12)
        .offset(y: top + dragOffset)
        .zIndex(isDragging ? 10 : 0)
        .onTapGesture { onTap() }
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture())
                .onChanged { value in
                    guard !locked else { return }
                    switch value {
                    case .first(true):
                        if !isDragging { isDragging = true; Haptics.firm() }
                    case .second(true, let drag):
                        isDragging = true
                        dragOffset = drag?.translation.height ?? 0
                    default: break
                    }
                }
                .onEnded { _ in
                    let delta = snapped(dragOffset)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isDragging = false
                        dragOffset = 0
                    }
                    guard delta != 0, !locked else { return }
                    let newStart = block.start.addingTimeInterval(Double(delta * 60))
                    // Mantener el bloque dentro del mismo día.
                    guard Calendar.current.isDate(newStart, inSameDayAs: block.start) else { return }
                    block.reschedule(start: newStart, end: block.end.addingTimeInterval(Double(delta * 60)))
                    Haptics.success()
                    onCommit()
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: block.start)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toca para editar. Mantén pulsado y arrastra para mover.")
    }
}
