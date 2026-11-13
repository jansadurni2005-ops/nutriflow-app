import SwiftUI
import SwiftData
import FamilyControls

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScreenHeader(overline: "Configuración", title: "Settings")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    link("Objetivos", icon: "target", tint: Palette.accent) { GoalsSettingsView() }
                    link("Puntuación de efectividad", icon: "gauge.with.dots.needle.67percent", tint: Palette.success) { ScoreSettingsView() }
                    link("Alarmas y notificaciones", icon: "bell.badge.fill", tint: Palette.danger) { NotificationSettingsView() }
                    link("Distracciones (Screen Time)", icon: "hourglass.badge.lock", tint: Palette.warning) { ScreenTimeSettingsView() }
                } header: { Text("Productividad") }
                .listRowBackground(Palette.card)

                Section {
                    link("Calendario y Google Calendar", icon: "calendar", tint: Palette.info) { CalendarSettingsView() }
                    link("Datos, iCloud y exportación", icon: "externaldrive.fill", tint: Color(hex: "8E8E93")) { DataSettingsView() }
                } header: { Text("Integraciones") }
                .listRowBackground(Palette.card)

                Section {
                    link("Permisos y límites de iOS", icon: "lock.shield", tint: Color(hex: "7D5CFF")) { CapabilitiesView() }
                    Button {
                        coordinator.settings.onboardingCompleted = false
                    } label: {
                        Label("Repetir la bienvenida", systemImage: "sparkles")
                    }
                    .foregroundStyle(Palette.textPrimary)
                } header: { Text("Ayuda") }
                .listRowBackground(Palette.card)

                Section {
                    HStack {
                        Text("FOCUS OS")
                        Spacer()
                        Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .font(.footnote)
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 110) }
        }
    }

    private func link<Destination: View>(_ title: String, icon: String, tint: Color, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
                .scrollContentBackground(.hidden)
                .background(Palette.background)
                .toolbar(.visible, for: .navigationBar)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(tint))
                Text(title).foregroundStyle(Palette.textPrimary)
            }
        }
    }
}

// MARK: - Objetivos

struct GoalsSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.settingsStore
        Form {
            Section {
                Stepper(value: $store.settings.goals.weeklyEffectiveHours, in: 5...80, step: 1) {
                    row("Horas efectivas / semana", "\(Int(store.settings.goals.weeklyEffectiveHours)) h")
                }
                Stepper(value: $store.settings.goals.targetEffectiveness, in: 0.5...1, step: 0.05) {
                    row("Efectividad objetivo", TimeFormat.percent(store.settings.goals.targetEffectiveness))
                }
                Stepper(value: $store.settings.goals.dailyDeepWorkBlocks, in: 0...10) {
                    row("Bloques profundos / día", "\(store.settings.goals.dailyDeepWorkBlocks)")
                }
                Stepper(value: $store.settings.goals.maxDailyDistractionMinutes, in: 0...240, step: 5) {
                    row("Máx. distracción / día", "\(store.settings.goals.maxDailyDistractionMinutes) min")
                }
                Stepper(value: $store.settings.goals.weeklyPlanAdherence, in: 0.5...1, step: 0.05) {
                    row("Cumplimiento semanal", TimeFormat.percent(store.settings.goals.weeklyPlanAdherence))
                }
            } footer: {
                Text("Los objetivos alimentan las rachas, los logros y el XP. Un día cuenta para la racha si alcanzas la efectividad objetivo; los días sin nada planificado no la rompen.")
            }
            .listRowBackground(Palette.card)

            Section {
                Toggle("Proponer revisión y plan de mañana al terminar la jornada", isOn: $store.settings.askPlanTomorrow)
                    .tint(Palette.accent)
            }
            .listRowBackground(Palette.card)
        }
        .navigationTitle("Objetivos")
        .onDisappear { coordinator.didChangeData() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).font(.metric(16)).foregroundStyle(Palette.accent) }
    }
}

// MARK: - Puntuación

struct ScoreSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.settingsStore
        let total = max(0.0001, store.settings.weights.total)
        Form {
            Section {
                weightSlider("Concentración", value: $store.settings.weights.concentration, total: total)
                weightSlider("Cumplimiento de bloques", value: $store.settings.weights.adherence, total: total)
                weightSlider("Tareas completadas", value: $store.settings.weights.completion, total: total)
                weightSlider("Puntualidad", value: $store.settings.weights.punctuality, total: total)
                Button("Restablecer 40 / 25 / 25 / 10") { store.settings.weights = .default }
                    .foregroundStyle(Palette.accent)
            } header: {
                Text("Pesos")
            } footer: {
                Text("Los pesos se normalizan automáticamente para sumar 100 %. Un componente sin datos se excluye y la puntuación se marca como estimada.")
            }
            .listRowBackground(Palette.card)

            Section {
                Stepper(value: $store.settings.punctualityGraceMinutes, in: 0...15) {
                    HStack { Text("Margen sin penalizar"); Spacer(); Text("\(store.settings.punctualityGraceMinutes) min").foregroundStyle(Palette.accent) }
                }
                Stepper(value: $store.settings.punctualityZeroMinutes, in: (store.settings.punctualityGraceMinutes + 5)...120, step: 5) {
                    HStack { Text("Retraso = 0 %"); Spacer(); Text("\(store.settings.punctualityZeroMinutes) min").foregroundStyle(Palette.accent) }
                }
            } header: { Text("Puntualidad") }
            .listRowBackground(Palette.card)

            Section("Qué no penaliza") {
                Label("Descansos programados", systemImage: "cup.and.saucer")
                Label("«Necesito descansar» durante una sesión", systemImage: "figure.walk")
                Label("Bloques de tipo Reunión / llamada", systemImage: "phone")
                Label("Uso de apps durante un pase de trabajo", systemImage: "briefcase")
            }
            .font(.subheadline)
            .listRowBackground(Palette.card)
        }
        .navigationTitle("Puntuación")
        .onDisappear { coordinator.didChangeData() }
    }

    private func weightSlider(_ title: String, value: Binding<Double>, total: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue / total * 100).rounded())) %").font(.metric(16)).foregroundStyle(Palette.accent)
            }
            Slider(value: value, in: 0...1, step: 0.05).tint(Palette.accent)
        }
    }
}

// MARK: - Notificaciones

struct NotificationSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var authorized = NotificationService.shared.isAuthorized
    @State private var status: String = ""

    var body: some View {
        @Bindable var store = coordinator.settingsStore
        Form {
            Section {
                HStack {
                    Label(authorized ? "Notificaciones permitidas" : "Notificaciones desactivadas",
                          systemImage: authorized ? "checkmark.circle.fill" : "bell.slash")
                        .foregroundStyle(authorized ? Palette.success : Palette.warning)
                    Spacer()
                }
                if !authorized {
                    Button("Permitir notificaciones") {
                        Task {
                            await NotificationService.shared.requestAuthorization()
                            authorized = NotificationService.shared.isAuthorized
                            if !authorized, let url = URL(string: UIApplication.openSettingsURLString) {
                                await UIApplication.shared.open(url)
                            }
                            coordinator.didChangeData()
                        }
                    }
                    .foregroundStyle(Palette.accent)
                }
            } footer: {
                Text("Las alarmas se programan en iOS con antelación, así que suenan aunque FOCUS OS esté cerrada. iOS permite 64 avisos pendientes por app: FOCUS OS mantiene una ventana rodante de ~36 h que se renueva al abrir la app y en segundo plano.")
            }
            .listRowBackground(Palette.card)

            Section("Bloques") {
                Toggle("Aviso previo", isOn: $store.settings.notifications.notifyBefore)
                Stepper(value: $store.settings.notifications.preAlertMinutes, in: 1...30) {
                    Text("Minutos antes: \(store.settings.notifications.preAlertMinutes)")
                }
                Toggle("Al empezar", isOn: $store.settings.notifications.notifyStart)
                Toggle("Al terminar", isOn: $store.settings.notifications.notifyEnd)
                Toggle("Recordatorio si no he empezado", isOn: $store.settings.notifications.notStartedReminder)
                Stepper(value: $store.settings.notifications.notStartedDelayMinutes, in: 1...30) {
                    Text("Recordar a los \(store.settings.notifications.notStartedDelayMinutes) min")
                }
                Toggle("Aviso antes del descanso", isOn: $store.settings.notifications.breakApproaching)
                Toggle("Urgentes (Time Sensitive)", isOn: $store.settings.notifications.timeSensitive)
            }
            .listRowBackground(Palette.card)

            Section("Jornada") {
                Toggle("Aviso al finalizar la jornada", isOn: $store.settings.notifications.dayEnd)
                Toggle("Resumen diario", isOn: $store.settings.notifications.dailySummary)
                DatePicker("Hora del resumen", selection: Binding(
                    get: { ScheduleService.date(on: Date(), minutes: store.settings.notifications.dailySummaryHour * 60 + store.settings.notifications.dailySummaryMinute) },
                    set: {
                        let m = ScheduleService.minutes(of: $0)
                        store.settings.notifications.dailySummaryHour = m / 60
                        store.settings.notifications.dailySummaryMinute = m % 60
                    }), displayedComponents: .hourAndMinute)
            }
            .listRowBackground(Palette.card)

            Section {
                Toggle("Mensaje motivador", isOn: $store.settings.notifications.motivational)
                Stepper(value: $store.settings.notifications.motivationalMinutes, in: 15...180, step: 15) {
                    Text("Cada \(store.settings.notifications.motivationalMinutes) min de concentración")
                }
                Toggle("«Vuelve al foco» al salir de la app", isOn: $store.settings.notifications.refocusNudge)
                Stepper(value: $store.settings.notifications.refocusNudgeSeconds, in: 15...600, step: 15) {
                    Text("Tras \(store.settings.notifications.refocusNudgeSeconds) s fuera")
                }
            } header: {
                Text("Durante las sesiones")
            } footer: {
                Text("El aviso «vuelve al foco» se cancela si bloqueas el iPhone (no es una distracción) o si vuelves a la app.")
            }
            .listRowBackground(Palette.card)

            Section {
                Picker("Sonido por defecto", selection: $store.settings.notifications.defaultSound) {
                    ForEach(AlarmSound.allCases) { Text($0.label).tag($0) }
                }
                Button("Probar sonido (llega en 3 s)") {
                    Task { await NotificationService.shared.sendTest(sound: store.settings.notifications.defaultSound) }
                }
                .foregroundStyle(Palette.accent)
                Toggle("Vibración háptica en la app", isOn: $store.settings.notifications.hapticsEnabled)
            } header: {
                Text("Sonido y vibración")
            } footer: {
                Text("La vibración de las notificaciones la controla iOS (Ajustes › Sonidos y vibraciones). En modo silencio, solo vibran.")
            }
            .listRowBackground(Palette.card)
        }
        .tint(Palette.accent)
        .navigationTitle("Notificaciones")
        .task { await NotificationService.shared.refreshStatus(); authorized = NotificationService.shared.isAuthorized }
        .onDisappear { coordinator.didChangeData() }
    }
}

// MARK: - Screen Time

struct ScreenTimeSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var pickDeep = false
    @State private var pickWork = false
    @State private var deepSelection = FamilyActivitySelection()
    @State private var workSelection = FamilyActivitySelection()
    @State private var requesting = false
    @State private var confirmRevoke = false

    var body: some View {
        @Bindable var store = coordinator.settingsStore
        let st = coordinator.screenTime
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: st.isAuthorized ? "checkmark.shield.fill" : "shield.slash")
                        .font(.title2)
                        .foregroundStyle(st.isAuthorized ? Palette.success : Palette.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.isAuthorized ? "Screen Time autorizado" : statusText(st.authorizationStatus)).font(.headline)
                        Text(st.isAuthorized ? "FOCUS OS puede medir y bloquear las apps que elijas." : "Sin autorización solo se registran distracciones manuales.")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                if !st.isAuthorized {
                    Button {
                        requesting = true
                        Task { await st.requestAuthorization(); requesting = false; coordinator.didChangeData() }
                    } label: {
                        HStack { Text("Autorizar Screen Time"); if requesting { Spacer(); ProgressView() } }
                    }
                    .foregroundStyle(Palette.accent)
                }
                if let error = st.lastError {
                    Text(error).font(.caption).foregroundStyle(Palette.danger)
                }
            } footer: {
                Text("Usa la API oficial FamilyControls con autorización individual. Apple nunca muestra a FOCUS OS qué apps eliges ni tu historial: solo tokens anónimos.")
            }
            .listRowBackground(Palette.card)

            if st.isAuthorized {
                Section {
                    Button { deepSelection = st.deepWorkSelection; pickDeep = true } label: {
                        selectionRow("Trabajo profundo", st.selectionSummary(.deepWork))
                    }
                    Picker("Política", selection: $store.settings.policyDeepWork) { policyOptions }
                } header: { Text("Apps distractoras · Trabajo profundo") }
                .listRowBackground(Palette.card)

                Section {
                    Button { workSelection = st.workSelection; pickWork = true } label: {
                        selectionRow("Trabajo", st.selectionSummary(.work))
                    }
                    Picker("Política", selection: $store.settings.policyWork) { policyOptions }
                } header: {
                    Text("Apps distractoras · Trabajo")
                } footer: {
                    Text("Ej.: bloquea TikTok, Instagram, YouTube y X en trabajo profundo, y solo mide su uso en bloques normales. En bloques como «Creación de contenido» puedes elegir «No medir ni bloquear» para usar Instagram profesionalmente.")
                }
                .listRowBackground(Palette.card)

                Section {
                    Stepper(value: $store.settings.workPassMinutes, in: 15...60, step: 5) {
                        Text("Duración del pase: \(store.settings.workPassMinutes) min")
                    }
                } header: {
                    Text("Pase de trabajo")
                } footer: {
                    Text("Durante una sesión puedes activar un pase para usar una app bloqueada por trabajo (p. ej. responder clientes en Instagram). Su uso queda registrado como autorizado y no penaliza. Mínimo 15 min por exigencia de la API DeviceActivity.")
                }
                .listRowBackground(Palette.card)

                Section {
                    Button("Revocar autorización", role: .destructive) { confirmRevoke = true }
                }
                .listRowBackground(Palette.card)
            }

            Section("Qué puede y qué no puede medir iOS") {
                info("checkmark.circle.fill", Palette.success, "Bloquear apps/categorías/webs elegidas durante bloques y sesiones, incluso con la app cerrada.")
                info("checkmark.circle.fill", Palette.success, "Medir minutos de uso acumulado de esas apps dentro de cada bloque (umbrales de 1 min).")
                info("checkmark.circle.fill", Palette.success, "Registrar cada intento de abrir una app bloqueada.")
                info("xmark.circle.fill", Palette.danger, "Saber qué haces dentro de una app (Reels vs. publicar). Para eso existen el pase de trabajo y la política por bloque.")
                info("xmark.circle.fill", Palette.danger, "Leer el historial de Tiempo de uso o el nombre de las apps elegidas.")
                info("exclamationmark.circle.fill", Palette.warning, "La medición solo funciona en bloques de ≥ 15 min y para los próximos ~12 bloques (se reprograma solo).")
            }
            .listRowBackground(Palette.card)
        }
        .tint(Palette.accent)
        .navigationTitle("Screen Time")
        .familyActivityPicker(isPresented: $pickDeep, selection: $deepSelection)
        .familyActivityPicker(isPresented: $pickWork, selection: $workSelection)
        .onChange(of: deepSelection) { _, value in
            guard value != st.deepWorkSelection else { return }
            st.save(value, for: .deepWork); coordinator.didChangeData()
        }
        .onChange(of: workSelection) { _, value in
            guard value != st.workSelection else { return }
            st.save(value, for: .work); coordinator.didChangeData()
        }
        .onAppear { st.refreshStatus() }
        .onDisappear { coordinator.didChangeData() }
        .confirmationDialog("¿Revocar la autorización de Screen Time?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Revocar", role: .destructive) { st.revokeAuthorization() }
        } message: {
            Text("Se retirarán los bloqueos y dejará de medirse el uso de apps.")
        }
    }

    @ViewBuilder
    private var policyOptions: some View {
        Text("Bloquear").tag(ScreenTimeShared.Policy.block)
        Text("Solo medir").tag(ScreenTimeShared.Policy.measure)
        Text("Nada").tag(ScreenTimeShared.Policy.off)
    }

    private func selectionRow(_ title: String, _ summary: String) -> some View {
        HStack {
            Text("Elegir apps").foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(summary).font(.caption).foregroundStyle(Palette.textSecondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.textTertiary)
        }
        .accessibilityLabel("Elegir apps para \(title). \(summary)")
    }

    private func info(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
    }

    private func statusText(_ status: AuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Sin autorizar"
        case .denied: return "Autorización denegada"
        case .approved: return "Autorizado"
        @unknown default: return "Estado desconocido"
        }
    }
}

// MARK: - Calendario

struct CalendarSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var showImport = false

    var body: some View {
        let service = coordinator.calendarService
        Form {
            Section {
                Label(service.hasReadAccess ? "Acceso de lectura concedido" : "Sin acceso a calendarios",
                      systemImage: service.hasReadAccess ? "checkmark.circle.fill" : "calendar.badge.exclamationmark")
                    .foregroundStyle(service.hasReadAccess ? Palette.success : Palette.warning)
                Button("Importar eventos de hoy…") { showImport = true }.foregroundStyle(Palette.accent)
            }
            .listRowBackground(Palette.card)

            Section("Google Calendar") {
                Text("1. Ajustes de iOS › Calendario › Cuentas › Añadir cuenta › Google.\n2. Activa «Calendarios» para esa cuenta.\n3. Vuelve aquí e importa: tus eventos de Google aparecerán junto al resto.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
                Text("FOCUS OS solo lee. Nunca crea, edita ni borra eventos, y no duplica eventos ya importados.")
                    .font(.footnote).foregroundStyle(Palette.textTertiary)
            }
            .listRowBackground(Palette.card)
        }
        .navigationTitle("Calendario")
        .sheet(isPresented: $showImport) {
            CalendarImportView(day: Date()).presentationBackground(Palette.background)
        }
        .onAppear { service.refreshStatus() }
    }
}

// MARK: - Datos

struct DataSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var exportDays = 30
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?
    @State private var confirmWipe = false

    var body: some View {
        @Bindable var store = coordinator.settingsStore
        Form {
            Section {
                Toggle("Sincronizar con iCloud", isOn: $store.settings.iCloudSync).tint(Palette.accent)
            } header: {
                Text("Almacenamiento")
            } footer: {
                Text("Por defecto todo se guarda solo en este iPhone. iCloud (CloudKit privado) requiere cuenta de desarrollador de pago y añadir la capacidad iCloud en Xcode (ver README). El cambio se aplica al reiniciar la app.")
            }
            .listRowBackground(Palette.card)

            Section {
                Picker("Periodo", selection: $exportDays) {
                    Text("7 días").tag(7)
                    Text("30 días").tag(30)
                    Text("90 días").tag(90)
                    Text("365 días").tag(365)
                }
                Button("Generar CSV") {
                    do {
                        exportURLs = try CSVExporter.export(days: exportDays, context: context, settings: coordinator.settings,
                                                            automaticTracking: coordinator.screenTime.automaticTrackingActive)
                        exportError = nil
                    } catch {
                        exportError = error.localizedDescription
                    }
                }
                .foregroundStyle(Palette.accent)
                ForEach(exportURLs, id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                }
                if let exportError { Text(exportError).font(.caption).foregroundStyle(Palette.danger) }
            } header: {
                Text("Exportar estadísticas")
            } footer: {
                Text("Dos archivos: resumen diario y detalle por bloque. Separador «;» para abrirlos directamente en Excel o Numbers.")
            }
            .listRowBackground(Palette.card)

            Section {
                Button("Borrar todos los datos", role: .destructive) { confirmWipe = true }
            } footer: {
                Text("Elimina bloques, rutinas, sesiones y distracciones de este dispositivo (y de iCloud si está activo).")
            }
            .listRowBackground(Palette.card)
        }
        .navigationTitle("Datos")
        .confirmationDialog("¿Borrar todos los datos?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Borrar definitivamente", role: .destructive) { wipe() }
        } message: {
            Text("No se puede deshacer.")
        }
    }

    private func wipe() {
        if coordinator.activeSession != nil { coordinator.finishSession(reason: .abandoned) }
        try? context.delete(model: WorkBlock.self)
        try? context.delete(model: RoutineItem.self)
        try? context.delete(model: FocusSession.self)
        try? context.delete(model: DistractionEvent.self)
        try? context.delete(model: DayJournal.self)
        UserDefaults.standard.removeObject(forKey: "schedule.generatedDays")
        coordinator.didChangeData()
        coordinator.showToast("Datos borrados.", style: .success)
    }
}
