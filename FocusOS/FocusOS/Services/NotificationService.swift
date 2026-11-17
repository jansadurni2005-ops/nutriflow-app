import Foundation
import UserNotifications

/// Notificaciones locales. Funcionan con la app cerrada porque iOS las entrega
/// por sí mismo a partir de disparadores de calendario/tiempo programados de antemano.
///
/// Límite del sistema: 64 notificaciones pendientes por app. Por eso se programa una
/// ventana rodante (próximas ~36 h, máx. 56) que se recalcula cada vez que la app se abre,
/// cambia la planificación o se ejecuta la tarea en segundo plano.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    enum Category {
        static let blockStart = "BLOCK_START"
        static let session = "SESSION"
        static let review = "REVIEW"
    }

    enum Action {
        static let startBlock = "START_BLOCK"
        static let snooze = "SNOOZE_5"
        static let openReview = "OPEN_REVIEW"
    }

    private let center = UNUserNotificationCenter.current()
    private let maxScheduled = 56
    private let horizon: TimeInterval = 36 * 3600

    private(set) var status: UNAuthorizationStatus = .notDetermined

    func registerCategories() {
        let start = UNNotificationAction(identifier: Action.startBlock, title: "Empezar ahora", options: [.foreground])
        let snooze = UNNotificationAction(identifier: Action.snooze, title: "Recordar en 5 min", options: [])
        let review = UNNotificationAction(identifier: Action.openReview, title: "Ver revisión", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.blockStart, actions: [start, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.session, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.review, actions: [review], intentIdentifiers: [])
        ])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        return granted
    }

    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
    }

    var isAuthorized: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    // MARK: Planificación de bloques

    struct PlannedNotification {
        var id: String
        var date: Date
        var title: String
        var body: String
        var sound: AlarmSound
        var category: String?
        var userInfo: [String: String]
        var timeSensitive: Bool
    }

    /// Recalcula todas las notificaciones de bloques y de jornada.
    func reschedule(blocks: [WorkBlock], prefs: NotificationPrefs, activeBlockID: UUID?, summary: String?) async {
        await refreshStatus()
        guard isAuthorized else { return }

        let now = Date()
        let limit = now.addingTimeInterval(horizon)
        var planned: [PlannedNotification] = []
        let upcoming = blocks.filter { $0.end > now && $0.start < limit }.sorted { $0.start < $1.start }

        for block in upcoming {
            let id = block.id.uuidString
            let sound = block.sound
            let isBreak = block.kind == .breakTime
            let info = ["blockID": id]
            let timeLabel = "\(TimeFormat.hhmm(block.start))–\(TimeFormat.hhmm(block.end))"

            if prefs.notifyBefore && block.alarmBefore && !isBreak {
                planned.append(.init(id: "block.\(id).before", date: block.start.addingTimeInterval(-Double(prefs.preAlertMinutes * 60)),
                                     title: "En \(prefs.preAlertMinutes) min: \(block.title)",
                                     body: block.objective.isEmpty ? "\(block.kind.label) · \(timeLabel)" : "Objetivo: \(block.objective)",
                                     sound: sound, category: Category.blockStart, userInfo: info, timeSensitive: false))
            }
            if prefs.breakApproaching && isBreak {
                planned.append(.init(id: "block.\(id).breaksoon", date: block.start.addingTimeInterval(-5 * 60),
                                     title: "Descanso en 5 minutos",
                                     body: "Cierra lo que tienes entre manos. Descanso \(timeLabel).",
                                     sound: sound, category: nil, userInfo: info, timeSensitive: false))
            }
            if prefs.notifyStart && block.alarmStart && block.id != activeBlockID {
                planned.append(.init(id: "block.\(id).start", date: block.start,
                                     title: isBreak ? "Descanso" : "Empieza: \(block.title)",
                                     body: isBreak ? "Desconecta. Vuelves a las \(TimeFormat.hhmm(block.end))."
                                     : "\(block.kind.label) hasta las \(TimeFormat.hhmm(block.end)). Pulsa para empezar.",
                                     sound: sound, category: isBreak ? nil : Category.blockStart, userInfo: info,
                                     timeSensitive: prefs.timeSensitive && !isBreak))
            }
            if prefs.notStartedReminder && !isBreak && block.actualStart == nil && block.status == .pending {
                planned.append(.init(id: "block.\(id).notstarted", date: block.start.addingTimeInterval(Double(prefs.notStartedDelayMinutes * 60)),
                                     title: "Aún no has empezado «\(block.title)»",
                                     body: "El retraso se está registrando. Empieza ahora para salvar el bloque.",
                                     sound: sound, category: Category.blockStart, userInfo: info,
                                     timeSensitive: prefs.timeSensitive))
            }
            if prefs.notifyEnd && block.alarmEnd {
                planned.append(.init(id: "block.\(id).end", date: block.end,
                                     title: isBreak ? "Fin del descanso" : "Fin del bloque: \(block.title)",
                                     body: isBreak ? "Hora de volver al trabajo." : "Marca el bloque como terminado y revisa tu objetivo.",
                                     sound: sound, category: nil, userInfo: info, timeSensitive: prefs.timeSensitive))
            }
        }

        // Fin de jornada: final del último bloque de trabajo de cada día dentro del horizonte.
        if prefs.dayEnd {
            let byDay = Dictionary(grouping: upcoming.filter { $0.kind.countsAsWork }) { Calendar.current.startOfDay(for: $0.start) }
            for (day, dayBlocks) in byDay {
                guard let last = dayBlocks.map(\.end).max(), last > now else { continue }
                planned.append(.init(id: "day.\(Int(day.timeIntervalSince1970)).end", date: last.addingTimeInterval(60),
                                     title: "Jornada terminada",
                                     body: "Abre tu revisión diaria y prepara la jornada de mañana.",
                                     sound: prefs.defaultSound, category: Category.review, userInfo: ["route": "review"],
                                     timeSensitive: false))
            }
        }

        // Resumen diario a la hora configurada (hoy si aún no ha pasado, si no mañana).
        if prefs.dailySummary {
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = prefs.dailySummaryHour
            comps.minute = prefs.dailySummaryMinute
            if var fire = cal.date(from: comps) {
                if fire <= now { fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire }
                let isToday = cal.isDateInToday(fire)
                planned.append(.init(id: "day.summary", date: fire, title: "Resumen del día",
                                     body: (isToday ? summary : nil) ?? "Revisa tu efectividad, horas efectivas y tareas pendientes.",
                                     sound: prefs.defaultSound, category: Category.review, userInfo: ["route": "review"],
                                     timeSensitive: false))
            }
        }

        let finalList = planned.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(maxScheduled)

        // Reemplazar solo nuestras notificaciones de bloque/jornada (no las de sesión).
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("block.") || $0.hasPrefix("day.") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for item in finalList {
            await add(item)
        }
    }

    private func add(_ item: PlannedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = Self.sound(for: item.sound, timeSensitive: item.timeSensitive)
        if let category = item.category { content.categoryIdentifier = category }
        content.userInfo = item.userInfo
        content.interruptionLevel = item.timeSensitive ? .timeSensitive : .active
        content.threadIdentifier = "focusos"

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
    }

    static func sound(for sound: AlarmSound, timeSensitive: Bool) -> UNNotificationSound? {
        switch sound {
        case .system: return .default
        case .silent: return nil
        default:
            if let file = sound.fileName { return UNNotificationSound(named: UNNotificationSoundName(file)) }
            return .default
        }
    }

    // MARK: Sesión de concentración

    /// Motivación a los N minutos de concentración, fin de sesión libre.
    func scheduleSession(_ session: FocusSession, prefs: NotificationPrefs) async {
        cancelSessionNotifications()
        guard isAuthorized else { return }
        let now = Date()
        if prefs.motivational {
            // Se programa respecto al tiempo concentrado acumulado: si hay pausas se reprograma al reanudar.
            let focused = session.focused(at: now)
            for multiple in 1...3 {
                let target = Double(prefs.motivationalMinutes * 60 * multiple)
                let fire = now.addingTimeInterval(target - focused)
                guard fire > now.addingTimeInterval(30), fire < session.plannedEnd.addingTimeInterval(3600) else { continue }
                let minutes = prefs.motivationalMinutes * multiple
                await addSession(id: "session.motivation.\(multiple)", date: fire,
                                 title: "Llevas \(minutes) minutos concentrado",
                                 body: multiple == 1 ? "Sigue así. Este es el trabajo que mueve la aguja." : "Ritmo de élite. Valora un descanso breve si lo necesitas.",
                                 sound: prefs.defaultSound)
            }
        }
        if session.blockID == nil && prefs.notifyEnd && session.plannedEnd > now {
            await addSession(id: "session.end", date: session.plannedEnd, title: "Sesión completada",
                             body: "\(session.title): tiempo cumplido. Marca «He terminado» para registrarla.",
                             sound: prefs.defaultSound)
        }
    }

    func cancelSessionNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [
            "session.motivation.1", "session.motivation.2", "session.motivation.3", "session.end", "session.refocus"
        ])
    }

    /// Aviso para recuperar la concentración si se sale de la app durante una sesión.
    func scheduleRefocusNudge(session: FocusSession, prefs: NotificationPrefs) async {
        guard prefs.refocusNudge, isAuthorized, !session.isPaused, !session.isOnBreak else { return }
        let remaining = max(0, session.remaining())
        await addSession(id: "session.refocus", date: Date().addingTimeInterval(Double(max(15, prefs.refocusNudgeSeconds))),
                         title: "¿Sigues en «\(session.title)»?",
                         body: "Quedan \(TimeFormat.duration(remaining)) de bloque. Si te has desviado, vuelve ahora: un minuto perdido no es una sesión perdida.",
                         sound: prefs.defaultSound)
    }

    func cancelRefocusNudge() {
        center.removePendingNotificationRequests(withIdentifiers: ["session.refocus"])
    }

    func cancelNotStarted(blockID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "block.\(blockID.uuidString).notstarted", "block.\(blockID.uuidString).start"
        ])
    }

    /// Repetición a 5 minutos (acción de la notificación).
    func snooze(originalTitle: String, body: String, userInfo: [AnyHashable: Any]) async {
        let content = UNMutableNotificationContent()
        content.title = originalTitle
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Category.blockStart
        content.userInfo = userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 * 60, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "snooze.\(UUID().uuidString)", content: content, trigger: trigger))
    }

    private func addSession(id: String, date: Date, title: String, body: String, sound: AlarmSound) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = Self.sound(for: sound, timeSensitive: false)
        content.categoryIdentifier = Category.session
        content.threadIdentifier = "focusos.session"
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Prueba de sonido desde Ajustes.
    func sendTest(sound: AlarmSound) async {
        await addSession(id: "test.\(UUID().uuidString)", date: Date().addingTimeInterval(3),
                         title: "FOCUS OS", body: "Así sonarán tus alarmas (\(sound.label)).", sound: sound)
    }
}
