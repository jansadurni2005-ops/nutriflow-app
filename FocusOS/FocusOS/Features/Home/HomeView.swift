import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var dayKey = Calendar.current.startOfDay(for: Date())
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeContent(day: dayKey)
            .id(dayKey)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { dayKey = Calendar.current.startOfDay(for: Date()) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dayKey = Calendar.current.startOfDay(for: Date())
            }
    }
}

private struct HomeContent: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Query private var blocks: [WorkBlock]
    @Query private var sessions: [FocusSession]

    @State private var showBreakdown = false
    @State private var editingBlock: WorkBlock?
    @State private var showNewBlock = false

    let day: Date

    init(day: Date) {
        self.day = day
        let (start, end) = DayDataService.dayRange(day)
        _blocks = Query(filter: #Predicate<WorkBlock> { $0.start >= start && $0.start < end }, sort: \.start)
        _sessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= start && $0.startedAt < end }, sort: \.startedAt)
    }

    private func score(at now: Date) -> ScoreResult {
        let input = ScoreInput(blocks: DayDataService.facts(blocks: blocks, activeSession: coordinator.activeSession, now: now),
                               freeSessions: DayDataService.freeSessionFacts(sessions, now: now),
                               now: now, weights: coordinator.settings.weights,
                               punctualityGrace: TimeInterval(coordinator.settings.punctualityGraceMinutes * 60),
                               punctualityZero: TimeInterval(coordinator.settings.punctualityZeroMinutes * 60),
                               automaticDistractionTracking: coordinator.screenTime.automaticTrackingActive)
        return ScoringEngine.evaluate(input)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let warning = coordinator.storageWarning {
                    Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(Palette.warning).card()
                }
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let result = score(at: context.date)
                    VStack(spacing: 16) {
                        effectivenessCard(result)
                        currentBlockSection
                        dayStatusCard(result)
                    }
                }
                upcomingSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .sheet(isPresented: $showBreakdown) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScoreBreakdownSheet(result: score(at: context.date))
            }
            .presentationDetents([.large])
            .presentationBackground(Palette.background)
        }
        .sheet(item: $editingBlock) { block in
            BlockEditorView(mode: .edit(block)).presentationBackground(Palette.background)
        }
        .sheet(isPresented: $showNewBlock) {
            BlockEditorView(mode: .create(day: day)).presentationBackground(Palette.background)
        }
    }

    // MARK: Cabecera

    private var header: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 13 ? "Buenos días" : hour < 20 ? "Buenas tardes" : "Buenas noches"
        return ScreenHeader(overline: day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)), title: greeting) {
            Button { showNewBlock = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Palette.accent))
            }
            .accessibilityLabel("Nuevo bloque")
        }
    }

    // MARK: Efectividad

    private func effectivenessCard(_ r: ScoreResult) -> some View {
        VStack(spacing: 18) {
            HStack {
                Text("EFECTIVIDAD").overlineStyle()
                Spacer()
                ConfidenceBadge(confidence: r.confidence)
            }

            Button { showBreakdown = true } label: {
                RingGauge(value: r.score, lineWidth: 18, tint: Palette.scoreColor(r.score),
                          dashed: r.confidence == .estimated) {
                    VStack(spacing: 2) {
                        Text(r.score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                            .font(.metric(64, weight: .heavy))
                            .foregroundStyle(Palette.textPrimary)
                            .contentTransition(.numericText())
                        Text(r.score == nil ? "SIN DATOS" : "%  ·  VER DETALLE")
                            .font(.overline).tracking(1.2)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(width: 210, height: 210)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Efectividad \(TimeFormat.percent(r.score)). Ver detalle del cálculo.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                MetricTile(title: "Efectivo", value: TimeFormat.duration(r.effectiveSeconds), icon: "bolt.fill", tint: Palette.accent)
                MetricTile(title: "Planificado", value: TimeFormat.duration(r.plannedSeconds), icon: "calendar", tint: Palette.info)
                MetricTile(title: "Distracciones", value: TimeFormat.duration(r.distractionSeconds), icon: "iphone.radiowaves.left.and.right",
                           tint: Palette.danger, footnote: r.automaticDistractionTracking ? "Screen Time + manual" : "Solo registro manual")
                MetricTile(title: "Restante", value: TimeFormat.duration(r.remainingDaySeconds), icon: "hourglass", tint: Palette.warning,
                           footnote: "hasta fin de jornada")
            }
            HStack {
                Label("\(r.blocksCompleted)/\(r.blocksTotal) bloques completados", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(r.deepWorkBlocksCompleted)/\(coordinator.settings.goals.dailyDeepWorkBlocks) profundo")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary)
            }
        }
        .card()
    }

    // MARK: Bloque actual

    @ViewBuilder
    private var currentBlockSection: some View {
        let now = Date()
        if coordinator.activeSession != nil {
            SessionControlCard()
        } else if let current = blocks.first(where: { $0.start <= now && now < $0.end && $0.status != .completed }) {
            pendingCurrentCard(current, now: now)
        } else if blocks.isEmpty {
            EmptyStateView(icon: "calendar.badge.plus", title: "Tu día está en blanco",
                           message: "Planifica tus bloques o duplica la jornada de ayer para empezar a medir tu efectividad.",
                           actionTitle: "Planificar hoy") { coordinator.selectedTab = .schedule }
        } else {
            idleCard
        }
    }

    private func pendingCurrentCard(_ block: WorkBlock, now: Date) -> some View {
        let late = now.timeIntervalSince(block.start)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AHORA · \(block.kind.upperLabel)").overlineStyle(Color(hex: block.colorHex))
                Spacer()
                Text("\(TimeFormat.hhmm(block.start))–\(TimeFormat.hhmm(block.end))").font(.caption.monospacedDigit()).foregroundStyle(Palette.textSecondary)
            }
            Text(block.title).font(.title2.weight(.bold)).foregroundStyle(Palette.textPrimary)
            if !block.objective.isEmpty {
                Label(block.objective, systemImage: "target").font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            if block.kind != .breakTime && late > 60 {
                Label("Llevas \(TimeFormat.duration(late)) de retraso. Se está registrando.", systemImage: "clock.badge.exclamationmark")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.warning)
            }
            if block.kind == .breakTime {
                Text("Descanso programado: no penaliza. Vuelves a las \(TimeFormat.hhmm(block.end)).")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            } else {
                Button {
                    coordinator.startSession(block: block)
                } label: {
                    Label(block.actualStart == nil ? "Empezar bloque" : "Reanudar bloque", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card(highlight: Color(hex: block.colorHex))
    }

    private var idleCard: some View {
        let next = blocks.first { $0.start > Date() && $0.kind != .breakTime }
        return VStack(alignment: .leading, spacing: 12) {
            Text("SIN BLOQUE EN CURSO").overlineStyle()
            if let next {
                Text("Siguiente: \(next.title)").font(.title3.weight(.bold)).foregroundStyle(Palette.textPrimary)
                Text("Empieza a las \(TimeFormat.hhmm(next.start)) · \(next.kind.label)")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
                Button { coordinator.startSession(block: next) } label: {
                    Label("Adelantar y empezar ahora", systemImage: "forward.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Text("Jornada planificada completada").font(.title3.weight(.bold)).foregroundStyle(Palette.textPrimary)
                HStack(spacing: 10) {
                    Button("Revisión diaria") { coordinator.reviewDay = day }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Sesión libre") { coordinator.selectedTab = .focus }
                        .buttonStyle(SecondaryButtonStyle(tint: Palette.accent))
                }
            }
        }
        .card()
    }

    // MARK: Estado del día

    private func dayStatusCard(_ r: ScoreResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ESTADO DEL DÍA").overlineStyle()
                Spacer()
                Text(TimeFormat.percent(r.dayProgress)).font(.metric(18)).foregroundStyle(Palette.textPrimary)
            }
            ProgressBar(value: r.dayProgress, height: 10)
            // Mini línea temporal de bloques.
            GeometryReader { geo in
                let sorted = blocks.sorted { $0.start < $1.start }
                if let first = sorted.first?.start, let last = sorted.map(\.end).max(), last > first {
                    let total = last.timeIntervalSince(first)
                    ZStack(alignment: .leading) {
                        ForEach(sorted) { block in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: block.colorHex).opacity(block.status == .completed ? 1 : block.status == .missed ? 0.2 : 0.5))
                                .frame(width: max(3, geo.size.width * block.plannedSeconds / total - 2), height: 6)
                                .offset(x: geo.size.width * block.start.timeIntervalSince(first) / total)
                        }
                    }
                }
            }
            .frame(height: 6)
            HStack {
                Text(blocks.first.map { TimeFormat.hhmm($0.start) } ?? "--:--")
                Spacer()
                Text(blocks.map(\.end).max().map { TimeFormat.hhmm($0) } ?? "--:--")
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(Palette.textTertiary)
        }
        .card()
    }

    // MARK: Próximos bloques

    private var upcomingSection: some View {
        let now = Date()
        let upcoming = blocks.filter { $0.start > now }.prefix(4)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Próximos bloques", actionTitle: "Ver agenda") { coordinator.selectedTab = .schedule }
            if upcoming.isEmpty {
                Text(blocks.isEmpty ? "Nada planificado todavía." : "No quedan más bloques hoy.")
                    .font(.subheadline).foregroundStyle(Palette.textTertiary)
                    .card()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(upcoming)) { block in
                        Button { editingBlock = block } label: { BlockRow(block: block) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Fila compacta de un bloque.
struct BlockRow: View {
    let block: WorkBlock
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: block.colorHex)).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: block.kind.icon)
                    Text(block.kind.label)
                    if block.isRepeating { Image(systemName: "repeat") }
                    if block.externalEventID != nil { Image(systemName: "calendar") }
                }
                .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(TimeFormat.hhmm(block.start))").font(.metric(17)).foregroundStyle(Palette.textPrimary)
                Text(TimeFormat.duration(block.plannedSeconds)).font(.caption2).foregroundStyle(Palette.textTertiary)
            }
            Image(systemName: block.status.icon).foregroundStyle(block.status.color)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.stroke))
    }
}
