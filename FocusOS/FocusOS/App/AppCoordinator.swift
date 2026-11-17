import SwiftUI
import SwiftData
import Observation
import UserNotifications
import BackgroundTasks

enum AppTab: String, CaseIterable, Identifiable {
    case home, schedule, focus, analytics, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .schedule: return "Schedule"
        case .focus: return "Focus"
        case .analytics: return "Analytics"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "circle.hexagongrid.fill"
        case .schedule: return "calendar.day.timeline.left"
        case .focus: return "scope"
        case .analytics: return "chart.bar.xaxis"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case info, success, warning }
    var id = UUID()
    var message: String
    var style: Style = .info
}

/// Resumen mostrado al terminar una sesión.
struct SessionSummary: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var focused: Double
    var distraction: Double
    var paused: Double
    var breaks: Double
    var concentration: Double?
    var delay: Double?
    var finishedEarlyBy: Double?
    var blockStatus: BlockStatus?
}

/// Coordinador central de la app. Orquesta datos, sesiones y servicios del sistema.
@MainActor
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let container: ModelContainer
    let storageWarning: String?
    var context: ModelContext { container.mainContext }

    let settingsStore = SettingsStore.shared
    let screenTime = ScreenTimeService.shared
    let calendarService = CalendarImportService.shared

    // Estado de UI
    var selectedTab: AppTab = .home
    var showDeepWork = false
    var pendingRecovery: FocusSession?
    var sessionSummary: SessionSummary?
    var reviewDay: Date?
    var toast: Toast?
    /// Se incrementa tras cambios para que las vistas derivadas se recalculen.
    var dataVersion = 0

    var activeSession: FocusSession?
    private var syncTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    // MARK: Inicialización

    private init() {
        let schema = Schema(FocusSchema.models)
        let wantsCloud = UserDefaults.standard.bool(forKey: "focusos.iCloudSync")
        var warning: String?
        let made: ModelContainer
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                            cloudKitDatabase: wantsCloud ? .automatic : .none)
            made = try ModelContainer(for: schema, configurations: [config])
        } catch {
            do {
                // iCloud mal configurado → seguir en local.
                let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                made = try ModelContainer(for: schema, configurations: [local])
                if wantsCloud { warning = "No se pudo activar iCloud (\(error.localizedDescription)). Los datos se guardan solo en local." }
            } catch {
                // Último recurso: memoria. Se avisa claramente al usuario.
                let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                made = try! ModelContainer(for: schema, configurations: [memory])
                warning = "No se pudo abrir la base de datos (\(error.localizedDescription)). Los cambios NO se guardarán hasta reiniciar la app."
            }
        }
        container = made
        storageWarning = warning
        activeSession = DayDataService.activeSession(context: made.mainContext)
    }

    /// Llamado una vez al arrancar la interfaz.
    func bootstrap() {
        NotificationService.shared.registerCategories()
        observeSystemEvents()
        Task { await refresh() }
    }

    private func observeSystemEvents() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.significantTimeChangeNotification,
            .NSSystemTimeZoneDidChange,
            .NSSystemClockDidChange,
            .NSCalendarDayChanged
        ]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.dataVersion += 1
                    await self?.refresh()
                }
            })
        }
        // Bloqueo de pantalla durante una sesión: no es una distracción, se cancela el aviso de "vuelve al foco".
        observers.append(nc.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in NotificationService.shared.cancelRefocusNudge() }
        })
    }

    // MARK: Ciclo de vida

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            NotificationService.shared.cancelRefocusNudge()
            screenTime.refreshStatus()
            calendarService.refreshStatus()
            dataVersion += 1
            Task { await refresh() }
        case .background:
            if let session = activeSession {
                session.lastHeartbeat = Date()
                save()
                Task { await NotificationService.shared.scheduleRefocusNudge(session: session, prefs: settings.notifications) }
            }
            scheduleBackgroundRefresh()
        default:
            break
        }
    }

    // MARK: Sincronización

    /// Guarda y programa una sincronización de servicios (notificaciones, widget, Screen Time).
    func didChangeData() {
        save()
        dataVersion += 1
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.syncServices()
        }
    }

    func save() {
        do { try context.save() } catch { showToast("No se pudo guardar: \(error.localizedDescription)", style: .warning) }
    }

    /// Mantenimiento completo: rutinas, bloques vencidos, Screen Time, notificaciones, widget.
    func refresh() async {
        let today = Calendar.current.startOfDay(for: Date())
        ScheduleService.ensureRoutines(for: today, context: context)
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) {
            ScheduleService.ensureRoutines(for: tomorrow, context: context)
        }
        ScheduleService.markMissedBlocks(context: context)
        activeSession = DayDataService.activeSession(context: context)
        ingestScreenTime()
        checkInterruptedSession()
        await syncServices()
        checkEndOfDay()
        dataVersion += 1
    }

    func syncServices() async {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? now
        let upcoming = DayDataService.blocks(from: start, to: end, context: context)
        let stats = todayStats()

        let summary: String? = stats.result.score.map {
            "Efectividad \(TimeFormat.percent($0)) · \(TimeFormat.duration(stats.result.effectiveSeconds)) efectivas · \(stats.result.blocksCompleted)/\(stats.result.blocksTotal) bloques."
        }
        await NotificationService.shared.reschedule(blocks: upcoming, prefs: settings.notifications,
                                                    activeBlockID: activeSession?.blockID, summary: summary)
        screenTime.scheduleMonitoring(blocks: upcoming, settings: settings)
        WidgetBridge.publish(blocks: upcoming, score: stats.result, session: activeSession)
        if let session = activeSession {
            LiveActivityService.shared.update(for: session)
        } else {
            LiveActivityService.shared.end()
        }
    }

    func todayStats(now: Date = Date()) -> DayStats {
        DayDataService.stats(for: now, context: context, settings: settings, now: now,
                             automaticTracking: screenTime.automaticTrackingActive)
    }

    // MARK: Screen Time → distracciones

    private func ingestScreenTime() {
        let (usage, attempts) = screenTime.consumeLogs()
        guard !usage.isEmpty || !attempts.isEmpty else { return }

        for entry in usage {
            let authorized = screenTime.wasInsidePass(entry.detectedAt)
            var blockID: UUID?
            var sessionID: UUID?
            if entry.activityName.hasPrefix(ScreenTimeShared.blockActivityPrefix) {
                blockID = UUID(uuidString: String(entry.activityName.dropFirst(ScreenTimeShared.blockActivityPrefix.count)))
            } else if entry.activityName.hasPrefix(ScreenTimeShared.sessionActivityPrefix) {
                sessionID = UUID(uuidString: String(entry.activityName.dropFirst(ScreenTimeShared.sessionActivityPrefix.count)))
            }
            let event = DistractionEvent(date: entry.detectedAt, durationSeconds: 60, source: .screenTime,
                                         reason: .socialMedia, sessionID: sessionID ?? activeSession?.id, blockID: blockID,
                                         note: "Minuto \(entry.minute) de uso de apps distractoras", isAuthorized: authorized)
            context.insert(event)
            guard !authorized else { continue }

            if let session = activeSession, session.isActive,
               (session.blockID != nil && session.blockID == blockID) || session.id == sessionID {
                session.distractionSeconds += 60
                session.distractionCount += entry.minute == 1 ? 1 : 0
            } else if let blockID, let block = DayDataService.block(id: blockID, context: context) {
                block.distractionSeconds += 60
            }
        }

        for attempt in attempts {
            let event = DistractionEvent(date: attempt.date, durationSeconds: 0, source: .shieldAttempt, reason: .socialMedia,
                                         sessionID: activeSession?.id, blockID: activeSession?.blockID,
                                         note: attempt.action == "needs_for_work" ? "Indicó que la necesitaba para trabajar" : "Volvió al foco")
            context.insert(event)
            activeSession?.blockedAttempts += 1
        }
        save()
        if usage.contains(where: { !screenTime.wasInsidePass($0.detectedAt) }) {
            showToast("Screen Time registró \(usage.count) min de apps distractoras.", style: .warning)
        }
        if attempts.contains(where: { $0.action == "needs_for_work" }) {
            showToast("¿Necesitas una app para trabajar? Activa un pase de trabajo en la sesión.", style: .info)
        }
    }

    // MARK: Sesiones interrumpidas y fin de día

    private func checkInterruptedSession() {
        guard let session = activeSession, pendingRecovery == nil else { return }
        if Date() > session.plannedEnd.addingTimeInterval(30 * 60) {
            pendingRecovery = session
        }
    }

    private func checkEndOfDay() {
        guard settings.askPlanTomorrow, activeSession == nil, reviewDay == nil else { return }
        let now = Date()
        let blocks = DayDataService.blocks(on: now, context: context).filter { $0.kind.countsAsWork }
        guard let last = blocks.map(\.end).max(), now > last else { return }
        let key = now.formatted(.iso8601.year().month().day())
        guard settings.lastPlanPromptDay != key else { return }
        settings.lastPlanPromptDay = key
        reviewDay = Calendar.current.startOfDay(for: now)
    }

    // MARK: Notificaciones

    func handleNotificationResponse(actionIdentifier: String, userInfo: [AnyHashable: Any], title: String, body: String) {
        let blockID = (userInfo["blockID"] as? String).flatMap(UUID.init(uuidString:))
        switch actionIdentifier {
        case NotificationService.Action.startBlock:
            if let blockID, let block = DayDataService.block(id: blockID, context: context) {
                selectedTab = .focus
                startSession(block: block)
            }
        case NotificationService.Action.snooze:
            Task { await NotificationService.shared.snooze(originalTitle: title, body: body, userInfo: userInfo) }
        case NotificationService.Action.openReview:
            reviewDay = Calendar.current.startOfDay(for: Date())
        default:
            if (userInfo["route"] as? String) == "review" {
                reviewDay = Calendar.current.startOfDay(for: Date())
            } else if blockID != nil {
                selectedTab = activeSession != nil ? .focus : .home
            }
        }
    }

    // MARK: Segundo plano

    nonisolated static var refreshTaskID: String { (Bundle.main.bundleIdentifier ?? "focusos") + ".refresh" }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await self.refresh()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    // MARK: Utilidades

    func showToast(_ message: String, style: Toast.Style = .info) {
        toast = Toast(message: message, style: style)
    }
}
