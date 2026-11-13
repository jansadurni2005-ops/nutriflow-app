import SwiftUI
import SwiftData

/// Pestaña FOCUS: sesión activa, sesión libre y bloques pendientes de hoy.
struct FocusHubView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Query private var todayBlocks: [WorkBlock]
    @Query private var todaySessions: [FocusSession]

    @State private var title = ""
    @State private var objective = ""
    @State private var minutes = 50
    @State private var kind: BlockKind = .deepWork
    @State private var category: BlockCategory = .business
    @State private var blockApps = true

    init() {
        let (start, end) = DayDataService.dayRange(Date())
        _todayBlocks = Query(filter: #Predicate<WorkBlock> { $0.start >= start && $0.start < end }, sort: \.start)
        _todaySessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= start && $0.startedAt < end },
                               sort: \.startedAt, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(overline: "Sesiones de concentración", title: "Focus")
                if coordinator.activeSession != nil {
                    SessionControlCard()
                } else {
                    newSessionCard
                    plannedBlocksSection
                }
                historySection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
    }

    // MARK: Nueva sesión libre

    private var newSessionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NUEVA SESIÓN").overlineStyle(Palette.accent)
            TextField("", text: $title, prompt: Text("¿En qué vas a trabajar?").foregroundColor(Palette.textTertiary))
                .font(.title3.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            TextField("", text: $objective, prompt: Text("Objetivo concreto (opcional)").foregroundColor(Palette.textTertiary))
                .font(.subheadline).foregroundStyle(Palette.textSecondary)

            Divider().overlay(Palette.stroke)

            HStack(spacing: 8) {
                ForEach([25, 50, 90, 120], id: \.self) { value in
                    Button { minutes = value; Haptics.selection() } label: {
                        Text("\(value)").font(.metric(18))
                            .foregroundStyle(minutes == value ? .black : Palette.textPrimary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(minutes == value ? Palette.accent : Palette.cardElevated))
                    }
                    .buttonStyle(.plain)
                }
            }
            Stepper(value: $minutes, in: 5...240, step: 5) {
                Text("Duración: \(minutes) min").font(.subheadline).foregroundStyle(Palette.textSecondary)
            }

            Picker("Tipo", selection: $kind) {
                Text("Trabajo profundo").tag(BlockKind.deepWork)
                Text("Trabajo").tag(BlockKind.work)
            }
            .pickerStyle(.segmented)

            Picker("Categoría", selection: $category) {
                ForEach(BlockCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
            }
            .tint(Palette.textPrimary)

            Toggle(isOn: $blockApps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bloquear apps distractoras").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                    Text(blockingHint).font(.caption).foregroundStyle(Palette.textTertiary)
                }
            }
            .disabled(!coordinator.screenTime.isAuthorized)
            .tint(Palette.accent)

            Button {
                coordinator.startFreeSession(title: title, objective: objective, minutes: minutes, kind: kind,
                                             category: category, blockApps: blockApps && coordinator.screenTime.isAuthorized)
                title = ""; objective = ""
            } label: {
                Label("Empezar \(minutes) min", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }

    private var blockingHint: String {
        let st = coordinator.screenTime
        if !st.isAuthorized { return "Requiere autorizar Screen Time (Ajustes › Distracciones)." }
        let summary = st.selectionSummary(kind.selectionKind)
        return st.hasSelection(kind.selectionKind) ? "Se bloquearán: \(summary)" : "Aún no has elegido apps para este tipo de bloque."
    }

    // MARK: Bloques planificados

    private var plannedBlocksSection: some View {
        let pending = todayBlocks.filter { $0.status != .completed && $0.kind != .breakTime && $0.end > Date() }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Empezar un bloque de hoy")
            if pending.isEmpty {
                Text("No hay bloques pendientes hoy.").font(.subheadline).foregroundStyle(Palette.textTertiary).card()
            }
            ForEach(pending) { block in
                HStack {
                    BlockRow(block: block)
                    Button { coordinator.startSession(block: block) } label: {
                        Image(systemName: "play.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 44, height: 44).background(Circle().fill(Palette.accent))
                    }
                    .accessibilityLabel("Empezar \(block.title)")
                }
            }
        }
    }

    // MARK: Historial

    private var historySection: some View {
        let finished = todaySessions.filter { !$0.isActive }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sesiones de hoy")
            if finished.isEmpty {
                Text("Aún no has terminado ninguna sesión hoy.").font(.subheadline).foregroundStyle(Palette.textTertiary).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(finished) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                                Text("\(TimeFormat.hhmm(session.startedAt))–\(session.endedAt.map(TimeFormat.hhmm) ?? "--") · \(session.kind.label)")
                                    .font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(TimeFormat.duration(session.focused())).font(.metric(17)).foregroundStyle(Palette.textPrimary)
                                Text(TimeFormat.percent(session.concentration())).font(.caption2).foregroundStyle(Palette.scoreColor(session.concentration()))
                            }
                        }
                        .padding(.vertical, 10)
                        if session.id != finished.last?.id { Divider().overlay(Palette.stroke) }
                    }
                }
                .card()
            }
        }
    }
}
