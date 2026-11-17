import Foundation
import Observation
import FamilyControls
import DeviceActivity
import ManagedSettings

/// Integración con las APIs oficiales de Screen Time.
///
/// Qué hace (y qué NO puede hacer iOS):
/// - ✅ Pide autorización individual (`.individual`) al propio usuario con Face ID / código.
/// - ✅ Deja elegir apps/categorías/webs con `FamilyActivityPicker`. Los tokens son opacos:
///   la app nunca conoce el nombre de las apps elegidas (privacidad de Apple).
/// - ✅ Bloquea esas apps durante bloques o sesiones con `ManagedSettingsStore` (Shield).
/// - ✅ Mide minutos de uso acumulado de la selección durante cada bloque con eventos de umbral
///   de `DeviceActivityCenter` (1, 2, 3… min). La extensión monitor anota cada minuto alcanzado.
/// - ❌ No puede saber QUÉ haces dentro de una app (Reels vs. publicar en Instagram).
/// - ❌ No puede leer el historial de uso detallado: `DeviceActivityReport` solo dibuja datos
///   dentro de una extensión aislada que no puede devolverlos a la app.
/// - ⚠️ DeviceActivity exige intervalos ≥ 15 min y limita el número de actividades simultáneas,
///   por eso se monitorizan solo los próximos bloques y se reprograma periódicamente.
@MainActor
@Observable
final class ScreenTimeService {
    static let shared = ScreenTimeService()

    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    var deepWorkSelection = FamilyActivitySelection()
    var workSelection = FamilyActivitySelection()
    var lastError: String?

    private let center = DeviceActivityCenter()
    private let maxMonitoredBlocks = 12
    private let maxMinuteEvents = 60

    private init() {
        refreshStatus()
        deepWorkSelection = ShieldApplier.loadSelection(.deepWork)
        workSelection = ShieldApplier.loadSelection(.work)
    }

    var isAuthorized: Bool { authorizationStatus == .approved }
    var isEntitlementLikelyMissing: Bool { lastError?.contains("entitlement") == true }

    var workPassUntil: Date? {
        guard let date = ScreenTimeShared.workPassUntil, date > Date() else { return nil }
        return date
    }

    func refreshStatus() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
        refreshStatus()
    }

    func revokeAuthorization() {
        stopAllMonitoring()
        ShieldApplier.clear()
        AuthorizationCenter.shared.revokeAuthorization { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    static func describe(_ error: Error) -> String {
        if let fc = error as? FamilyControlsError {
            switch fc {
            case .restricted: return "Screen Time está restringido en este dispositivo (control parental o MDM)."
            case .unavailable: return "Screen Time no está disponible. Actívalo en Ajustes › Tiempo de uso."
            case .invalidAccountType: return "La cuenta de iCloud no permite esta autorización."
            case .invalidArgument: return "Argumento no válido al solicitar la autorización."
            case .authorizationConflict: return "Otra app de control parental tiene la autorización."
            case .authorizationCanceled: return "Has cancelado la autorización."
            case .networkError: return "Error de red al autorizar. Inténtalo con conexión."
            case .authenticationMethodUnavailable: return "Configura un código de bloqueo para autorizar Screen Time."
            @unknown default: return "Error de Screen Time: \(error.localizedDescription)"
            }
        }
        let text = error.localizedDescription
        if text.lowercased().contains("entitlement") {
            return "Falta el entitlement com.apple.developer.family-controls en la firma (necesitas cuenta de pago). Detalle: \(text)"
        }
        return text
    }

    // MARK: Selecciones

    func selection(for kind: ScreenTimeShared.SelectionKind) -> FamilyActivitySelection {
        kind == .deepWork ? deepWorkSelection : workSelection
    }

    func save(_ selection: FamilyActivitySelection, for kind: ScreenTimeShared.SelectionKind) {
        if kind == .deepWork { deepWorkSelection = selection } else { workSelection = selection }
        ShieldApplier.saveSelection(selection, kind: kind)
    }

    func selectionSummary(_ kind: ScreenTimeShared.SelectionKind) -> String {
        let s = selection(for: kind)
        let apps = s.applicationTokens.count
        let cats = s.categoryTokens.count
        let webs = s.webDomainTokens.count
        if apps + cats + webs == 0 { return "Ninguna seleccionada" }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categoría\(cats == 1 ? "" : "s")") }
        if webs > 0 { parts.append("\(webs) web\(webs == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    func hasSelection(_ kind: ScreenTimeShared.SelectionKind) -> Bool {
        !ShieldApplier.isEmpty(selection(for: kind))
    }

    /// ¿Hay medición automática real posible ahora mismo?
    var automaticTrackingActive: Bool {
        isAuthorized && (hasSelection(.deepWork) || hasSelection(.work))
    }

    // MARK: Monitorización de bloques

    private static func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: date)
    }

    /// Programa la medición/bloqueo de los próximos bloques según su política.
    func scheduleMonitoring(blocks: [WorkBlock], settings: AppSettings) {
        guard isAuthorized else { return }
        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)
        var plans = ScreenTimeShared.plans()

        // Planes de bloques: se recalculan desde cero. Se mantienen sesión y pase.
        let candidates = blocks
            .filter { $0.end > now && $0.start < horizon && $0.status != .completed && $0.status != .missed }
            .filter { $0.kind.tracksDistractions && $0.effectivePolicy(settings) != .off }
            .sorted { $0.start < $1.start }
            .prefix(maxMonitoredBlocks)

        let desiredNames = Set(candidates.map { ScreenTimeShared.blockActivityPrefix + $0.id.uuidString })
        let existingBlockActivities = center.activities.filter { $0.rawValue.hasPrefix(ScreenTimeShared.blockActivityPrefix) }
        // Ojo: stopMonitoring([]) detiene TODAS las actividades, por eso se comprueba que no esté vacío.
        let obsolete = existingBlockActivities.filter { !desiredNames.contains($0.rawValue) }
        if !obsolete.isEmpty { center.stopMonitoring(obsolete) }
        for key in plans.keys where key.hasPrefix(ScreenTimeShared.blockActivityPrefix) && !desiredNames.contains(key) {
            plans.removeValue(forKey: key)
        }

        for block in candidates {
            let policy = block.effectivePolicy(settings)
            let kind = block.kind.selectionKind
            let selection = self.selection(for: kind)
            guard !ShieldApplier.isEmpty(selection) else { continue }

            let start = max(block.start, now.addingTimeInterval(5))
            var end = block.end
            if end.timeIntervalSince(start) < 15 * 60 {
                // DeviceActivity exige intervalos ≥ 15 min. Si el bloque es más corto o ya está casi acabado,
                // se amplía la ventana de medición hasta 15 min solo si el bloque es de ≥ 15 min.
                guard block.plannedSeconds >= 15 * 60 else { continue }
                end = start.addingTimeInterval(15 * 60)
            }
            let name = DeviceActivityName(ScreenTimeShared.blockActivityPrefix + block.id.uuidString)
            let plan = ScreenTimeShared.MonitorPlan(activityName: name.rawValue, blockID: block.id, title: block.title,
                                                    start: block.start, end: block.end, policy: policy, selection: kind)
            // Evitar reiniciar una actividad ya programada idéntica (reiniciar borraría su progreso).
            if plans[name.rawValue] == plan && center.activities.contains(name) { continue }

            let minutes = min(maxMinuteEvents, max(1, Int(end.timeIntervalSince(start) / 60)))
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for minute in 1...minutes {
                events[DeviceActivityEvent.Name(ScreenTimeShared.minuteEventPrefix + String(minute))] = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: minute)
                )
            }
            let schedule = DeviceActivitySchedule(intervalStart: Self.components(start),
                                                  intervalEnd: Self.components(end), repeats: false)
            do {
                center.stopMonitoring([name])
                try center.startMonitoring(name, during: schedule, events: events)
                plans[name.rawValue] = plan
                lastError = nil
            } catch {
                lastError = Self.describe(error)
            }
        }

        // Limpiar planes caducados.
        for (key, plan) in plans where plan.end < now.addingTimeInterval(-3600) {
            plans.removeValue(forKey: key)
        }
        ScreenTimeShared.save(plans, key: ScreenTimeShared.Key.plans)
    }

    // MARK: Bloqueo inmediato (sesiones)

    /// Bloquea ya las apps de la selección y deja una actividad que retira el bloqueo al terminar,
    /// aunque la app se cierre.
    func startSessionShield(sessionID: UUID, kind: ScreenTimeShared.SelectionKind, title: String, until end: Date) {
        guard isAuthorized, hasSelection(kind) else { return }
        let now = Date()
        let name = DeviceActivityName(ScreenTimeShared.sessionActivityPrefix + sessionID.uuidString)
        var plans = ScreenTimeShared.plans()
        let safeEnd = max(end, now.addingTimeInterval(15 * 60 + 5))
        plans[name.rawValue] = .init(activityName: name.rawValue, blockID: nil, title: title, start: now,
                                     end: safeEnd, policy: .block, selection: kind)
        ScreenTimeShared.save(plans, key: ScreenTimeShared.Key.plans)
        ShieldApplier.apply(kind, title: title, now: now)
        do {
            try center.startMonitoring(name, during: DeviceActivitySchedule(intervalStart: Self.components(now.addingTimeInterval(2)),
                                                                            intervalEnd: Self.components(safeEnd), repeats: false))
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Retira el bloqueo de la sesión. Si hay un bloque con política de bloqueo vigente, se mantiene ese.
    func endSessionShield(sessionID: UUID) {
        guard isAuthorized else { return }
        let name = ScreenTimeShared.sessionActivityPrefix + sessionID.uuidString
        center.stopMonitoring([DeviceActivityName(name)])
        var plans = ScreenTimeShared.plans()
        plans.removeValue(forKey: name)
        // Al terminar la sesión antes de tiempo, el bloque asociado también deja de bloquear.
        ScreenTimeShared.save(plans, key: ScreenTimeShared.Key.plans)
        ShieldApplier.clear()
    }

    /// Termina el bloqueo de un bloque concreto (el usuario lo ha completado antes de tiempo).
    func releaseBlock(blockID: UUID) {
        guard isAuthorized else { return }
        let name = ScreenTimeShared.blockActivityPrefix + blockID.uuidString
        var plans = ScreenTimeShared.plans()
        if var plan = plans[name] {
            plan.policy = .measure
            plans[name] = plan
            ScreenTimeShared.save(plans, key: ScreenTimeShared.Key.plans)
        }
        ShieldApplier.reconcile(excluding: name)
    }

    // MARK: Pase de trabajo (uso profesional autorizado)

    /// Suspende el bloqueo durante N minutos (mín. 15) para usar, por ejemplo, Instagram por trabajo.
    /// El uso detectado durante el pase se registra como autorizado y no penaliza.
    func startWorkPass(minutes: Int) {
        guard isAuthorized else { return }
        let now = Date()
        let until = now.addingTimeInterval(Double(max(15, minutes) * 60))
        ScreenTimeShared.workPassUntil = until
        recordPassWindow(start: now, end: until)
        ShieldApplier.clear()
        let name = DeviceActivityName(ScreenTimeShared.workPassActivity)
        center.stopMonitoring([name])
        do {
            try center.startMonitoring(name, during: DeviceActivitySchedule(intervalStart: Self.components(now.addingTimeInterval(2)),
                                                                            intervalEnd: Self.components(until), repeats: false))
        } catch {
            lastError = Self.describe(error)
        }
    }

    func endWorkPass() {
        guard isAuthorized else { ScreenTimeShared.workPassUntil = nil; return }
        // Recortar la ventana autorizada al momento actual.
        var list = ScreenTimeShared.load([[Date]].self, key: Self.passHistoryKey) ?? []
        if let last = list.indices.last, let end = list[last].last, end > Date() {
            list[last] = [list[last].first ?? Date(), Date()]
            ScreenTimeShared.save(list, key: Self.passHistoryKey)
        }
        ScreenTimeShared.workPassUntil = nil
        center.stopMonitoring([DeviceActivityName(ScreenTimeShared.workPassActivity)])
        ShieldApplier.reconcile()
    }

    func stopAllMonitoring() {
        center.stopMonitoring()
        ScreenTimeShared.save([String: ScreenTimeShared.MonitorPlan](), key: ScreenTimeShared.Key.plans)
    }

    // MARK: Ingesta

    /// Lee y vacía los registros escritos por las extensiones.
    func consumeLogs() -> (usage: [ScreenTimeShared.UsageLogEntry], attempts: [ScreenTimeShared.ShieldAttempt]) {
        let usage = ScreenTimeShared.load([ScreenTimeShared.UsageLogEntry].self, key: ScreenTimeShared.Key.usageLog) ?? []
        let attempts = ScreenTimeShared.load([ScreenTimeShared.ShieldAttempt].self, key: ScreenTimeShared.Key.shieldAttempts) ?? []
        AppGroup.defaults.removeObject(forKey: ScreenTimeShared.Key.usageLog)
        AppGroup.defaults.removeObject(forKey: ScreenTimeShared.Key.shieldAttempts)
        return (usage, attempts)
    }

    /// Fechas de pases de trabajo pasados (para excluir su uso). Se guardan en la app.
    private static let passHistoryKey = "st.passHistory"

    func recordPassWindow(start: Date, end: Date) {
        var list = ScreenTimeShared.load([[Date]].self, key: Self.passHistoryKey) ?? []
        list.append([start, end])
        list = list.filter { ($0.last ?? .distantPast) > Date().addingTimeInterval(-3 * 86_400) }
        ScreenTimeShared.save(list, key: Self.passHistoryKey)
    }

    func wasInsidePass(_ date: Date) -> Bool {
        let list = ScreenTimeShared.load([[Date]].self, key: Self.passHistoryKey) ?? []
        return list.contains { window in
            guard let s = window.first, let e = window.last else { return false }
            return s <= date && date <= e
        }
    }
}
