import SwiftUI

/// Pantalla DEEP WORK: temporizador grande, objetivo y lo mínimo imprescindible.
struct DeepWorkView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var showDistraction = false
    @State private var showSwitch = false
    @State private var keepAwake = true
    @State private var breathe = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            // Halo sutil que "respira" mientras estás concentrado.
            Circle()
                .fill(RadialGradient(colors: [Palette.accent.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 260))
                .frame(width: 520, height: 520)
                .scaleEffect(breathe ? 1.08 : 0.92)
                .opacity(coordinator.activeSession?.isPaused == true ? 0.3 : 1)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathe)
                .offset(y: -80)

            if let session = coordinator.activeSession {
                content(session)
            } else {
                VStack(spacing: 16) {
                    Text("No hay ninguna sesión activa").foregroundStyle(Palette.textSecondary)
                    Button("Cerrar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(32)
            }
        }
        .onAppear {
            breathe = true
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
        .sheet(isPresented: $showDistraction) {
            DistractionSheet().presentationDetents([.medium]).presentationBackground(Palette.background)
        }
        .sheet(isPresented: $showSwitch) {
            SwitchTaskSheet().presentationDetents([.medium, .large]).presentationBackground(Palette.background)
        }
        .statusBarHidden()
    }

    @ViewBuilder
    private func content(_ session: FocusSession) -> some View {
        VStack(spacing: 0) {
            // Barra superior
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 40, height: 40).background(Circle().fill(Palette.card))
                }
                .accessibilityLabel("Minimizar")
                Spacer()
                Text("DEEP WORK").font(.system(size: 13, weight: .heavy).width(.expanded)).tracking(3).foregroundStyle(Palette.accent)
                Spacer()
                Button { keepAwake.toggle() } label: {
                    Image(systemName: keepAwake ? "sun.max.fill" : "moon.fill").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(keepAwake ? Palette.accent : Palette.textSecondary)
                        .frame(width: 40, height: 40).background(Circle().fill(Palette.card))
                }
                .accessibilityLabel(keepAwake ? "Pantalla siempre encendida" : "Pantalla normal")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Text(session.kind.upperLabel).overlineStyle()
                Text(session.title).font(.title2.weight(.bold)).foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center).lineLimit(2)
                if !session.objective.isEmpty {
                    Label(session.objective, systemImage: "target")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let remaining = session.remaining(at: now)
                let concentration = session.concentration(at: now)
                VStack(spacing: 26) {
                    RingGauge(value: session.progress(at: now), lineWidth: 10,
                              tint: session.isOnBreak ? Palette.info : session.isPaused ? Palette.warning : Palette.accent) {
                        VStack(spacing: 6) {
                            Text(remaining >= 0 ? TimeFormat.clock(remaining) : "+" + TimeFormat.clock(-remaining))
                                .font(.metric(58, weight: .heavy))
                                .foregroundStyle(remaining >= 0 ? Palette.textPrimary : Palette.accent)
                                .contentTransition(.numericText(countsDown: true))
                                .minimumScaleFactor(0.6).lineLimit(1)
                            Text(session.isOnBreak ? "DESCANSO · \(TimeFormat.compactClock(session.totalBreak(at: now) - session.breakSeconds))"
                                 : session.isPaused ? "EN PAUSA" : (remaining >= 0 ? "RESTANTES" : "TIEMPO EXTRA"))
                                .font(.overline).tracking(1.5)
                                .foregroundStyle(session.isOnBreak ? Palette.info : session.isPaused ? Palette.warning : Palette.textTertiary)
                        }
                        .padding(.horizontal, 24)
                    }
                    .frame(width: 290, height: 290)

                    HStack(spacing: 28) {
                        stat("ACUMULADO", TimeFormat.compactClock(session.focused(at: now)))
                        stat("DISTRACCIÓN", TimeFormat.duration(session.distractionSeconds))
                        stat("FIN", TimeFormat.hhmm(session.plannedEnd))
                    }

                    // Barra de concentración
                    VStack(spacing: 6) {
                        HStack {
                            Text("CONCENTRACIÓN").overlineStyle()
                            Spacer()
                            Text(concentration.map { TimeFormat.percent($0) } ?? "midiendo…")
                                .font(.metric(15)).foregroundStyle(Palette.textPrimary)
                        }
                        ProgressBar(value: concentration ?? 0, tint: Palette.scoreColor(concentration), height: 6)
                    }
                    .padding(.horizontal, 32)
                }
            }

            Spacer(minLength: 12)

            shieldStatus(session).padding(.horizontal, 20)

            // Acciones principales
            VStack(spacing: 10) {
                Button {
                    coordinator.finishSession(reason: .completed)
                    dismiss()
                } label: { Label("He terminado", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())

                if session.isOnBreak {
                    Button { coordinator.endBreak() } label: { Label("Volver al trabajo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(SecondaryButtonStyle(tint: Palette.info))
                } else {
                    Button { coordinator.startBreak() } label: { Label("Necesito descansar", systemImage: "cup.and.saucer") }
                        .buttonStyle(SecondaryButtonStyle())
                }

                HStack(spacing: 4) {
                    if session.isPaused {
                        ControlButton(icon: "play.fill", label: "Reanudar", tint: Palette.accent, filled: true) { coordinator.resumeSession() }
                    } else {
                        ControlButton(icon: "pause.fill", label: "Pausar") { coordinator.pauseSession() }
                    }
                    ControlButton(icon: "exclamationmark.triangle", label: "Distracción", tint: Palette.danger) { showDistraction = true }
                    ControlButton(icon: "arrow.triangle.swap", label: "Cambiar") { showSwitch = true }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.metric(20)).foregroundStyle(Palette.textPrimary)
            Text(title).font(.system(size: 9, weight: .bold).width(.expanded)).tracking(1).foregroundStyle(Palette.textTertiary)
        }
    }

    @ViewBuilder
    private func shieldStatus(_ session: FocusSession) -> some View {
        let st = coordinator.screenTime
        if session.kind.tracksDistractions {
            HStack(spacing: 10) {
                if !st.isAuthorized {
                    Image(systemName: "lock.open").foregroundStyle(Palette.textTertiary)
                    Text("Bloqueo de apps no activo: autoriza Screen Time en Ajustes.")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                    Spacer()
                } else if let until = st.workPassUntil {
                    Image(systemName: "briefcase.fill").foregroundStyle(Palette.info)
                    Text("Pase de trabajo hasta las \(TimeFormat.hhmm(until)). Uso registrado como profesional.")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button("Terminar") { coordinator.endWorkPass() }.font(.caption.weight(.bold))
                } else if session.appBlockingEnabled && st.hasSelection(session.kind.selectionKind) {
                    Image(systemName: "lock.fill").foregroundStyle(Palette.accent)
                    Text("Apps distractoras bloqueadas").font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button("Pase de trabajo") { coordinator.startWorkPass() }.font(.caption.weight(.bold))
                } else if session.appBlockingEnabled {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.warning)
                    Text("Elige tus apps distractoras en Ajustes › Distracciones.").font(.caption).foregroundStyle(Palette.textTertiary)
                    Spacer()
                } else {
                    Image(systemName: "eye").foregroundStyle(Palette.textTertiary)
                    Text("Bloqueo desactivado en esta sesión.").font(.caption).foregroundStyle(Palette.textTertiary)
                    Spacer()
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
            .padding(.bottom, 12)
        }
    }
}
