import SwiftUI
import SwiftData

/// Máquina de estados de las sesiones de concentración.
///
/// Estados: inactiva → activa ⇄ pausa / descanso → terminada.
/// Todo se calcula con marcas temporales persistidas (inicio, inicio de pausa, inicio de descanso),
/// así que el temporizador es exacto aunque la app se suspenda, se cierre o el iPhone se reinicie.
extension AppCoordinator {

    // MARK: Inicio

    /// Empieza (o reanuda) el bloque planificado. Registra el retraso respecto a la hora prevista.
    func startSession(block: WorkBlock, blockApps: Bool? = nil) {
        let now = Date()
        if let current = activeSession {
            if current.blockID == block.id { showDeepWork = true; return }
            finishSession(reason: .switched)
        }
        // Si el bloque ya terminó (empezado muy tarde), se respeta su duración desde ahora.
        let plannedEnd = block.end > now.addingTimeInterval(5 * 60) ? block.end : now.addingTimeInterval(max(block.plannedSeconds, 15 * 60))
        let session = FocusSession(title: block.title, kind: block.kind, plannedEnd: plannedEnd, blockID: block.id,
                                   objective: block.objective, category: block.category, colorHex: block.colorHex,
                                   startedAt: now)
        let policy = block.effectivePolicy(settings)
        session.appBlockingEnabled = (blockApps ?? (policy == .block)) && screenTime.isAuthorized
        context.insert(session)

        if block.actualStart == nil { block.actualStart = now }
        block.status = .inProgress
        activateSession(session, blockID: block.id)
    }

    /// Sesión libre (sin bloque planificado), desde la pestaña FOCUS.
    func startFreeSession(title: String, objective: String, minutes: Int, kind: BlockKind,
                          category: BlockCategory, blockApps: Bool) {
        if activeSession != nil { finishSession(reason: .switched) }
        let now = Date()
        let session = FocusSession(title: title.isEmpty ? "Sesión de concentración" : title, kind: kind,
                                   plannedEnd: now.addingTimeInterval(Double(max(5, minutes) * 60)), blockID: nil,
                                   objective: objective, category: category, colorHex: "FF6500", startedAt: now)
        session.appBlockingEnabled = blockApps
        context.insert(session)
        activateSession(session, blockID: nil)
    }

    private func activateSession(_ session: FocusSession, blockID: UUID?) {
        activeSession = session
        save()
        if let blockID { NotificationService.shared.cancelNotStarted(blockID: blockID) }
        if session.appBlockingEnabled && session.kind.tracksDistractions {
            screenTime.startSessionShield(sessionID: session.id, kind: session.kind.selectionKind,
                                          title: session.title, until: session.plannedEnd)
        }
        LiveActivityService.shared.start(for: session)
        Task { await NotificationService.shared.scheduleSession(session, prefs: settings.notifications) }
        Haptics.firm()
        showDeepWork = true
        didChangeData()
    }

    // MARK: Pausa / descanso

    func pauseSession() {
        guard let session = activeSession, !session.isPaused else { return }
        if session.isOnBreak { endBreak() }
        session.pauseStartedAt = Date()
        NotificationService.shared.cancelSessionNotifications()
        Haptics.tap()
        LiveActivityService.shared.update(for: session)
        didChangeData()
    }

    func resumeSession() {
        guard let session = activeSession else { return }
        let now = Date()
        if let pause = session.pauseStartedAt {
            session.pausedSeconds += max(0, now.timeIntervalSince(pause))
            session.pauseStartedAt = nil
        }
        if let breakStart = session.breakStartedAt {
            session.breakSeconds += max(0, now.timeIntervalSince(breakStart))
            session.breakStartedAt = nil
        }
        Task { await NotificationService.shared.scheduleSession(session, prefs: settings.notifications) }
        Haptics.tap()
        LiveActivityService.shared.update(for: session)
        didChangeData()
    }

    /// "Necesito descansar": descanso autorizado, no penaliza la concentración.
    func startBreak() {
        guard let session = activeSession, !session.isOnBreak else { return }
        let now = Date()
        if let pause = session.pauseStartedAt {
            session.pausedSeconds += max(0, now.timeIntervalSince(pause))
            session.pauseStartedAt = nil
        }
        session.breakStartedAt = now
        NotificationService.shared.cancelSessionNotifications()
        Haptics.tap()
        LiveActivityService.shared.update(for: session)
        didChangeData()
    }

    func endBreak() {
        guard let session = activeSession, let start = session.breakStartedAt else { return }
        session.breakSeconds += max(0, Date().timeIntervalSince(start))
        session.breakStartedAt = nil
        Task { await NotificationService.shared.scheduleSession(session, prefs: settings.notifications) }
        LiveActivityService.shared.update(for: session)
        didChangeData()
    }

    // MARK: Distracciones

    /// Registro manual de una distracción ("Marcar distracción").
    func markDistraction(minutes: Double, reason: DistractionReason, note: String = "") {
        let now = Date()
        var seconds = max(0, minutes * 60)
        if let session = activeSession {
            // No se puede registrar más distracción que el tiempo disponible de la sesión.
            seconds = min(seconds, session.focused(at: now))
            session.distractionSeconds += seconds
            session.distractionCount += 1
            context.insert(DistractionEvent(date: now, durationSeconds: seconds, source: .manual, reason: reason,
                                            sessionID: session.id, blockID: session.blockID, note: note))
        } else {
            let current = DayDataService.blocks(on: now, context: context).first { $0.start <= now && now < $0.end && $0.kind.tracksDistractions }
            current?.distractionSeconds += seconds
            context.insert(DistractionEvent(date: now, durationSeconds: seconds, source: .manual, reason: reason,
                                            sessionID: nil, blockID: current?.id, note: note))
        }
        Haptics.warning()
        showToast("Distracción registrada: \(TimeFormat.duration(seconds)). Vuelve al objetivo.", style: .warning)
        if let session = activeSession {
            Task { await NotificationService.shared.scheduleSession(session, prefs: settings.notifications) }
        }
        didChangeData()
    }

    // MARK: Pase de trabajo

    func startWorkPass() {
        guard screenTime.isAuthorized else {
            showToast("Autoriza Screen Time en Ajustes para usar pases de trabajo.", style: .warning)
            return
        }
        let minutes = max(15, settings.workPassMinutes)
        screenTime.startWorkPass(minutes: minutes)
        showToast("Pase de trabajo activo \(minutes) min. El uso queda registrado como profesional.", style: .info)
        Haptics.tap()
        dataVersion += 1
    }

    func endWorkPass() {
        screenTime.endWorkPass()
        dataVersion += 1
    }

    // MARK: Fin

    /// Finaliza la sesión activa y vuelca los tiempos reales en el bloque.
    @discardableResult
    func finishSession(reason: SessionEndReason, at endDate: Date? = nil) -> SessionSummary? {
        guard let session = activeSession else { return nil }
        let end = min(endDate ?? Date(), Date())
        let finalEnd = max(end, session.startedAt)

        // Cerrar pausa/descanso en curso hasta el momento final.
        if let pause = session.pauseStartedAt {
            session.pausedSeconds += max(0, finalEnd.timeIntervalSince(pause))
            session.pauseStartedAt = nil
        }
        if let breakStart = session.breakStartedAt {
            session.breakSeconds += max(0, finalEnd.timeIntervalSince(breakStart))
            session.breakStartedAt = nil
        }
        session.endedAt = finalEnd
        session.isActive = false
        session.endReasonRaw = reason.rawValue

        let focused = session.focused(at: finalEnd)
        var summary = SessionSummary(title: session.title, focused: focused, distraction: session.distractionSeconds,
                                     paused: session.pausedSeconds, breaks: session.breakSeconds,
                                     concentration: session.concentration(at: finalEnd))

        if let blockID = session.blockID, let block = DayDataService.block(id: blockID, context: context) {
            block.workedSeconds += focused
            block.distractionSeconds += session.distractionSeconds
            block.pausedSeconds += session.pausedSeconds
            block.breakSeconds += session.breakSeconds
            block.actualEnd = finalEnd
            switch reason {
            case .completed:
                block.status = .completed
            case .switched, .abandoned:
                block.status = block.workedSeconds >= block.plannedSeconds * 0.8 ? .completed
                    : (block.end > finalEnd ? .pending : .missed)
            case .interrupted:
                block.status = block.workedSeconds >= block.plannedSeconds * 0.5 ? .completed : .missed
            }
            summary.delay = block.delaySeconds
            summary.blockStatus = block.status
            if finalEnd < block.end && block.status == .completed {
                summary.finishedEarlyBy = block.end.timeIntervalSince(finalEnd)
            }
            if block.status == .completed {
                screenTime.releaseBlock(blockID: block.id)
            }
        }

        if session.appBlockingEnabled && screenTime.isAuthorized {
            screenTime.endSessionShield(sessionID: session.id)
            ShieldApplier.reconcile()
        }
        if screenTime.workPassUntil != nil { screenTime.endWorkPass() }

        NotificationService.shared.cancelSessionNotifications()
        LiveActivityService.shared.end()
        activeSession = nil
        showDeepWork = false
        if reason == .completed || reason == .interrupted {
            sessionSummary = summary
            Haptics.success()
        }
        didChangeData()
        return summary
    }

    /// "Cambiar tarea": cierra la sesión actual y empieza otro bloque o una sesión libre.
    func switchTask(to block: WorkBlock?) {
        guard let current = activeSession else { return }
        let remainingMinutes = max(15, Int(current.remaining() / 60))
        let kind = current.kind
        let category = current.category
        let blocking = current.appBlockingEnabled
        finishSession(reason: .switched)
        if let block {
            startSession(block: block)
        } else {
            startFreeSession(title: "Tarea libre", objective: "", minutes: remainingMinutes, kind: kind,
                             category: category, blockApps: blocking)
        }
    }

    /// Renombra la tarea de la sesión actual sin cortarla.
    func renameActiveTask(_ title: String, objective: String) {
        guard let session = activeSession else { return }
        session.title = title
        session.objective = objective
        LiveActivityService.shared.update(for: session)
        didChangeData()
    }

    /// Resolución de una sesión que quedó abierta (app cerrada, reinicio…).
    func resolveRecovery(endAt date: Date?) {
        guard let session = pendingRecovery else { return }
        pendingRecovery = nil
        if activeSession?.id != session.id { activeSession = session }
        if let date {
            finishSession(reason: .interrupted, at: date)
        } else {
            // Descartar: no se cuenta tiempo trabajado.
            if let blockID = session.blockID, let block = DayDataService.block(id: blockID, context: context) {
                block.status = block.end < Date() ? .missed : .pending
            }
            if session.appBlockingEnabled { screenTime.endSessionShield(sessionID: session.id) }
            LiveActivityService.shared.end()
            NotificationService.shared.cancelSessionNotifications()
            context.delete(session)
            activeSession = nil
            didChangeData()
        }
    }
}
