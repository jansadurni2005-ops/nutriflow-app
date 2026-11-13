import SwiftUI
import SwiftData

/// Revisión diaria + "¿Quieres preparar tu jornada de mañana?"
struct DailyReviewView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let day: Date

    @State private var blocks: [WorkBlock] = []
    @State private var stats: DayStats?
    @State private var note = ""
    @State private var journal: DayJournal?
    @State private var step = 0

    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if step == 0 { review } else { planTomorrow }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle(step == 0 ? "Revisión diaria" : "Mañana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { saveNote(); dismiss() } } }
        }
        .task { load() }
    }

    // MARK: Revisión

    @ViewBuilder
    private var review: some View {
        if let stats {
            let r = stats.result
            VStack(spacing: 12) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()).overlineStyle(Palette.accent)
                RingGauge(value: r.score, lineWidth: 14, tint: Palette.scoreColor(r.score), dashed: r.confidence == .estimated) {
                    VStack(spacing: 0) {
                        Text(TimeFormat.percent(r.score)).font(.metric(44, weight: .heavy)).foregroundStyle(Palette.textPrimary)
                        Text("EFECTIVIDAD").font(.overline).foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(width: 170, height: 170)
                ConfidenceBadge(confidence: r.confidence)
            }
            .frame(maxWidth: .infinity)
            .card()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: "Horas trabajadas", value: TimeFormat.duration(r.effectiveSeconds), icon: "bolt.fill", tint: Palette.accent,
                           footnote: "de \(TimeFormat.duration(r.plannedSeconds)) planificadas")
                MetricTile(title: "Distracciones", value: TimeFormat.duration(r.distractionSeconds), icon: "exclamationmark.triangle", tint: Palette.danger)
            }

            let done = blocks.filter { $0.status == .completed && $0.kind.countsAsWork }
            let pending = blocks.filter { ($0.status == .missed || $0.status == .pending) && $0.kind.countsAsWork }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Qué has conseguido")
                if done.isEmpty {
                    Text("Ningún bloque completado.").font(.subheadline).foregroundStyle(Palette.textTertiary)
                }
                ForEach(done) { block in
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                        Text(block.title).foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Text(TimeFormat.duration(block.workedSeconds > 0 ? block.workedSeconds : (block.kind == .meeting ? block.plannedSeconds : 0)))
                            .font(.caption.monospacedDigit()).foregroundStyle(Palette.textSecondary)
                    }
                    .font(.subheadline)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Pendiente")
                if pending.isEmpty {
                    Text("Nada pendiente. Día cerrado.").font(.subheadline).foregroundStyle(Palette.textTertiary)
                }
                ForEach(pending) { block in
                    HStack {
                        Image(systemName: block.status.icon).foregroundStyle(block.status.color)
                        Text(block.title).foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Button("Mover a mañana") {
                            ScheduleService.moveToNextDay(block, context: context)
                            coordinator.didChangeData()
                            load()
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.accent)
                    }
                    .font(.subheadline)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Qué puedo mejorar mañana")
                ForEach(InsightsEngine.insights(stats: stats, blocks: blocks, goals: coordinator.settings.goals)) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .foregroundStyle(insight.tone == .positive ? Palette.success : insight.tone == .warning ? Palette.danger : Palette.warning)
                            .frame(width: 22)
                        Text(insight.text).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                }
                TextField("Tu nota para mañana…", text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardElevated))
            }
            .card()

            Button {
                saveNote()
                withAnimation { step = 1 }
            } label: { Label("¿Quieres preparar tu jornada de mañana?", systemImage: "arrow.right") }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            ProgressView().tint(Palette.accent).padding(40)
        }
    }

    // MARK: Plan de mañana

    @ViewBuilder
    private var planTomorrow: some View {
        let tomorrowBlocks = DayDataService.blocks(on: tomorrow, context: context)
        VStack(alignment: .leading, spacing: 12) {
            Text(tomorrow.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()).overlineStyle(Palette.accent)
            Text(tomorrowBlocks.isEmpty ? "Mañana está vacío" : "Mañana tiene \(tomorrowBlocks.count) bloques")
                .font(.title2.weight(.bold)).foregroundStyle(Palette.textPrimary)
            ForEach(tomorrowBlocks) { BlockRow(block: $0) }
        }
        .card()

        VStack(spacing: 10) {
            Button {
                let n = ScheduleService.duplicate(day: day, to: tomorrow, context: context)
                coordinator.didChangeData()
                coordinator.showToast(n > 0 ? "\(n) bloques copiados a mañana." : "Mañana ya tenía esa planificación.", style: .success)
                markPlanned()
            } label: { Label("Duplicar la planificación de hoy", systemImage: "doc.on.doc") }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                ScheduleService.ensureRoutines(for: tomorrow, context: context, force: true)
                coordinator.didChangeData()
                coordinator.showToast("Rutina aplicada a mañana.", style: .success)
                markPlanned()
            } label: { Label("Aplicar mi rutina semanal", systemImage: "repeat") }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                markPlanned()
                dismiss()
                coordinator.selectedTab = .schedule
            } label: { Label("Planificar a mano en Schedule", systemImage: "calendar") }
            .buttonStyle(SecondaryButtonStyle())

            Button("Ahora no") { dismiss() }
                .font(.subheadline).foregroundStyle(Palette.textTertiary).padding(.top, 4)
        }
    }

    // MARK: Datos

    private func load() {
        blocks = DayDataService.blocks(on: day, context: context)
        stats = DayDataService.stats(for: day, context: context, settings: coordinator.settings,
                                     automaticTracking: coordinator.screenTime.automaticTrackingActive)
        let start = Calendar.current.startOfDay(for: day)
        let descriptor = FetchDescriptor<DayJournal>(predicate: #Predicate { $0.day == start })
        if let existing = try? context.fetch(descriptor).first {
            journal = existing
            if note.isEmpty { note = existing.improvementNote }
        }
    }

    private func saveNote() {
        let entry: DayJournal
        if let journal { entry = journal } else {
            entry = DayJournal(day: day)
            context.insert(entry)
            journal = entry
        }
        entry.improvementNote = note
        entry.reviewedAt = Date()
        try? context.save()
    }

    private func markPlanned() {
        saveNote()
        journal?.plannedTomorrow = true
        try? context.save()
    }
}
