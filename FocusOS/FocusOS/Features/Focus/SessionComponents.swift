import SwiftUI
import SwiftData

/// Tarjeta del temporizador central con los controles de la sesión (Home y Focus).
struct SessionControlCard: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var showDistraction = false
    @State private var showSwitch = false
    @State private var confirmFinish = false

    var body: some View {
        if let session = coordinator.activeSession {
            VStack(spacing: 18) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = session.remaining(at: context.date)
                    VStack(spacing: 6) {
                        HStack {
                            Text(session.kind.upperLabel).overlineStyle(Palette.accent)
                            Spacer()
                            if session.isOnBreak {
                                Chip(text: "Descanso", icon: "cup.and.saucer.fill", tint: Palette.info)
                            } else if session.isPaused {
                                Chip(text: "En pausa", icon: "pause.fill", tint: Palette.warning)
                            } else if session.appBlockingEnabled && coordinator.screenTime.isAuthorized {
                                Chip(text: "Apps bloqueadas", icon: "lock.fill", tint: Palette.accent)
                            }
                        }
                        Text(remaining >= 0 ? TimeFormat.clock(remaining) : "+" + TimeFormat.clock(-remaining))
                            .font(.metric(54, weight: .heavy))
                            .foregroundStyle(remaining >= 0 ? Palette.textPrimary : Palette.accent)
                            .contentTransition(.numericText(countsDown: true))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(remaining >= 0 ? "restantes" : "tiempo extra sobre el plan")
                            .font(.subheadline).foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProgressBar(value: session.progress(at: context.date), height: 6).padding(.top, 6)
                        HStack {
                            Label(TimeFormat.duration(session.focused(at: context.date)) + " concentrado", systemImage: "bolt.fill")
                            Spacer()
                            if session.distractionSeconds > 0 {
                                Label(TimeFormat.duration(session.distractionSeconds), systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Palette.danger)
                            }
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                        .padding(.top, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tarea").font(.caption).foregroundStyle(Palette.textTertiary)
                    Text(session.title).font(.title3.weight(.bold)).foregroundStyle(Palette.textPrimary)
                    if !session.objective.isEmpty {
                        Label(session.objective, systemImage: "target").font(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    if session.isPaused || session.isOnBreak {
                        ControlButton(icon: "play.fill", label: "Reanudar", tint: Palette.accent, filled: true) { coordinator.resumeSession() }
                    } else {
                        ControlButton(icon: "pause.fill", label: "Pausar") { coordinator.pauseSession() }
                    }
                    ControlButton(icon: "flag.checkered", label: "Finalizar", tint: Palette.success) { confirmFinish = true }
                    ControlButton(icon: "exclamationmark.triangle", label: "Distracción", tint: Palette.danger) { showDistraction = true }
                    ControlButton(icon: "arrow.triangle.swap", label: "Cambiar") { showSwitch = true }
                }

                Button { coordinator.showDeepWork = true } label: {
                    Label("Abrir modo DEEP WORK", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Palette.accent))
            }
            .card(highlight: Palette.accent)
            .sheet(isPresented: $showDistraction) {
                DistractionSheet().presentationDetents([.medium]).presentationBackground(Palette.background)
            }
            .sheet(isPresented: $showSwitch) {
                SwitchTaskSheet().presentationDetents([.medium, .large]).presentationBackground(Palette.background)
            }
            .confirmationDialog("¿Finalizar el bloque?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finalizar y marcar completado") { coordinator.finishSession(reason: .completed) }
                Button("Abandonar (queda pendiente)", role: .destructive) { coordinator.finishSession(reason: .abandoned) }
                Button("Seguir trabajando", role: .cancel) {}
            } message: {
                Text("Se registrará el tiempo real trabajado.")
            }
        }
    }
}

// MARK: - Marcar distracción

struct DistractionSheet: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double = 5
    @State private var reason: DistractionReason = .socialMedia

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("MARCAR DISTRACCIÓN").overlineStyle(Palette.danger)
            Text("¿Cuánto tiempo te has desviado?").font(.title3.weight(.bold)).foregroundStyle(Palette.textPrimary)

            HStack(spacing: 8) {
                ForEach([1.0, 3, 5, 10, 15, 30], id: \.self) { value in
                    Button { minutes = value; Haptics.selection() } label: {
                        Text("\(Int(value))m")
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundStyle(minutes == value ? .black : Palette.textPrimary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(minutes == value ? Palette.danger : Palette.cardElevated))
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DistractionReason.allCases) { r in
                        Button { reason = r; Haptics.selection() } label: {
                            Chip(text: r.label, icon: r.icon, tint: Palette.textSecondary, selected: reason == r)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Se descuenta del tiempo concentrado y reduce tu efectividad. Registrarlo con honestidad es lo que hace que la puntuación sea real.")
                .font(.footnote).foregroundStyle(Palette.textTertiary)

            Button("Registrar \(Int(minutes)) min") {
                coordinator.markDistraction(minutes: minutes, reason: reason)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(tint: Palette.danger))
        }
        .padding(20)
    }
}

// MARK: - Cambiar tarea

struct SwitchTaskSheet: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Query private var blocks: [WorkBlock]
    @State private var newTitle = ""
    @State private var newObjective = ""

    init() {
        let (start, end) = DayDataService.dayRange(Date())
        _blocks = Query(filter: #Predicate<WorkBlock> { $0.start >= start && $0.start < end }, sort: \.start)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Renombrar la tarea actual") {
                    TextField("Nuevo nombre", text: $newTitle)
                    TextField("Objetivo", text: $newObjective)
                    Button("Guardar sin cortar la sesión") {
                        coordinator.renameActiveTask(newTitle.isEmpty ? (coordinator.activeSession?.title ?? "") : newTitle,
                                                     objective: newObjective)
                        dismiss()
                    }
                    .disabled(newTitle.isEmpty && newObjective.isEmpty)
                }
                .listRowBackground(Palette.card)

                Section("Cambiar a otro bloque de hoy") {
                    let candidates = blocks.filter { $0.status != .completed && $0.kind != .breakTime && $0.id != coordinator.activeSession?.blockID }
                    if candidates.isEmpty {
                        Text("No hay otros bloques pendientes hoy.").foregroundStyle(Palette.textTertiary)
                    }
                    ForEach(candidates) { block in
                        Button {
                            coordinator.switchTask(to: block)
                            dismiss()
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: block.colorHex)).frame(width: 8, height: 8)
                                Text(block.title).foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text("\(TimeFormat.hhmm(block.start))–\(TimeFormat.hhmm(block.end))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    Button {
                        coordinator.switchTask(to: nil)
                        dismiss()
                    } label: {
                        Label("Tarea libre (sin bloque)", systemImage: "sparkles")
                    }
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Cambiar tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear {
                newObjective = coordinator.activeSession?.objective ?? ""
            }
        }
    }
}

// MARK: - Desglose de la puntuación

struct ScoreBreakdownSheet: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    let result: ScoreResult

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(TimeFormat.percent(result.score)).font(.metric(56, weight: .heavy)).foregroundStyle(Palette.scoreColor(result.score))
                        Spacer()
                        ConfidenceBadge(confidence: result.confidence)
                    }

                    ForEach(result.components) { component in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(component.title).font(.cardTitle).foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text("peso \(Int((component.weight / max(0.0001, coordinator.settings.weights.total)) * 100))%")
                                    .font(.caption).foregroundStyle(Palette.textTertiary)
                                Text(TimeFormat.percent(component.value)).font(.metric(20)).foregroundStyle(Palette.textPrimary)
                            }
                            ProgressBar(value: component.value ?? 0, tint: component.value == nil ? Palette.textTertiary : Palette.accent)
                            Text(component.detail).font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CÓMO SE CALCULA").overlineStyle(Palette.accent)
                        explanation("Concentración", "Tiempo concentrado ÷ (concentrado + distracciones + pausas). Los descansos autorizados («Necesito descansar») y las reuniones/llamadas no penalizan.")
                        explanation("Cumplimiento del horario", "Tiempo trabajado ÷ tiempo planificado que ya debería haber ocurrido. Los descansos programados no cuentan.")
                        explanation("Tareas completadas", "Bloques completados ÷ bloques ya vencidos.")
                        explanation("Puntualidad", "100 % si empiezas con ≤ \(coordinator.settings.punctualityGraceMinutes) min de retraso, 0 % con ≥ \(coordinator.settings.punctualityZeroMinutes) min.")
                        explanation("Datos incompletos", "Si un componente no tiene datos se excluye y se reparte su peso: la puntuación aparece como «Estimada». Sin datos no hay puntuación.")
                        explanation("Distracciones", result.automaticDistractionTracking
                                    ? "Se combinan los minutos medidos por Screen Time en tus apps distractoras con los que registras a mano."
                                    : "Solo se cuentan las distracciones que registras a mano. Autoriza Screen Time en Ajustes para medirlas automáticamente.")
                    }
                    .card()
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("Efectividad de hoy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }

    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Text(text).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Resumen de sesión

struct SessionSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: SessionSummary

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundStyle(Palette.accent)
                .padding(.top, 24)
            Text("BLOQUE TERMINADO").overlineStyle(Palette.accent)
            Text(summary.title).font(.title2.weight(.bold)).foregroundStyle(Palette.textPrimary).multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: "Concentrado", value: TimeFormat.duration(summary.focused), icon: "bolt.fill", tint: Palette.accent)
                MetricTile(title: "Concentración", value: TimeFormat.percent(summary.concentration), icon: "scope", tint: Palette.success)
                MetricTile(title: "Distracciones", value: TimeFormat.duration(summary.distraction), icon: "exclamationmark.triangle", tint: Palette.danger)
                MetricTile(title: "Pausas + descanso", value: TimeFormat.duration(summary.paused + summary.breaks), icon: "pause", tint: Palette.warning)
            }
            VStack(spacing: 4) {
                if let delay = summary.delay, delay > 60 {
                    Text("Empezaste con \(TimeFormat.duration(delay)) de retraso.").foregroundStyle(Palette.warning)
                }
                if let early = summary.finishedEarlyBy, early > 60 {
                    Text("Terminaste \(TimeFormat.duration(early)) antes de lo previsto: se registra el tiempo real.")
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(.footnote).multilineTextAlignment(.center)
            Button("Continuar") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
    }
}

// MARK: - Recuperación de sesión interrumpida

struct RecoverySheet: View {
    @Environment(AppCoordinator.self) private var coordinator
    let session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SESIÓN SIN CERRAR").overlineStyle(Palette.warning)
            Text("«\(session.title)» quedó abierta").font(.title3.weight(.bold)).foregroundStyle(Palette.textPrimary)
            Text("Empezó a las \(TimeFormat.hhmm(session.startedAt)) y debía terminar a las \(TimeFormat.hhmm(session.plannedEnd)). ¿Cuándo terminaste realmente? Solo se contará el tiempo que confirmes.")
                .font(.subheadline).foregroundStyle(Palette.textSecondary)
            Button("A la hora prevista (\(TimeFormat.hhmm(session.plannedEnd)))") {
                coordinator.resolveRecovery(endAt: session.plannedEnd)
            }
            .buttonStyle(PrimaryButtonStyle())
            if session.lastHeartbeat > session.startedAt && session.lastHeartbeat < session.plannedEnd {
                Button("Cuando salí de la app (\(TimeFormat.hhmm(session.lastHeartbeat)))") {
                    coordinator.resolveRecovery(endAt: session.lastHeartbeat)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button("Descartar la sesión", role: .destructive) {
                coordinator.resolveRecovery(endAt: nil)
            }
            .buttonStyle(SecondaryButtonStyle(tint: Palette.danger))
        }
        .padding(20)
    }
}
