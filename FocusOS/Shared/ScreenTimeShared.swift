import Foundation

/// Contrato de datos entre la app y las extensiones de Screen Time
/// (DeviceActivityMonitor, ShieldConfiguration y ShieldAction).
///
/// Todo se guarda en los UserDefaults del App Group, codificado en JSON.
/// Las extensiones tienen un límite de memoria muy bajo (~6 MB), por eso
/// las estructuras son pequeñas y se recortan periódicamente.
enum ScreenTimeShared {

    // MARK: Claves

    enum Key {
        /// `Data` de `FamilyActivitySelection` para bloques de trabajo profundo.
        static let selectionDeepWork = "st.selection.deepWork"
        /// `Data` de `FamilyActivitySelection` para bloques de trabajo normal.
        static let selectionWork = "st.selection.work"
        /// Registro de minutos de uso detectados por el monitor (`[UsageLogEntry]`).
        static let usageLog = "st.usageLog"
        /// Intentos de abrir apps bloqueadas registrados por el Shield (`[ShieldAttempt]`).
        static let shieldAttempts = "st.shieldAttempts"
        /// Planes de bloqueo/medición por actividad (`[String: MonitorPlan]`).
        static let plans = "st.plans"
        /// Pase de trabajo activo: fecha hasta la que el bloqueo está suspendido.
        static let workPassUntil = "st.workPassUntil"
        /// Contexto que muestra el Shield (título del bloque actual).
        static let shieldContext = "st.shieldContext"
    }

    // MARK: Nombres de actividades

    /// Prefijo de las actividades de DeviceActivity asociadas a un bloque.
    static let blockActivityPrefix = "block."
    /// Prefijo de las actividades de una sesión libre de concentración.
    static let sessionActivityPrefix = "session."
    /// Actividad del pase de trabajo temporal.
    static let workPassActivity = "workpass"
    /// Prefijo de los eventos de umbral (minuto N de uso).
    static let minuteEventPrefix = "min."
    /// Nombre del ManagedSettingsStore usado para los bloqueos.
    static let storeName = "focusos.shield"

    // MARK: Modelos

    /// Política de distracciones de un bloque.
    enum Policy: String, Codable, CaseIterable {
        case off       // No medir ni bloquear (p.ej. descanso o bloque de contenido en Instagram)
        case measure   // Medir el uso de apps distractoras, sin bloquear
        case block     // Bloquear apps distractoras con el Shield
    }

    /// Qué selección de apps usar para un plan.
    enum SelectionKind: String, Codable {
        case deepWork
        case work

        var key: String {
            switch self {
            case .deepWork: return Key.selectionDeepWork
            case .work: return Key.selectionWork
            }
        }
    }

    /// Plan que la app deja preparado para que el monitor sepa qué hacer
    /// cuando empiece o termine el intervalo de una actividad.
    struct MonitorPlan: Codable, Equatable {
        var activityName: String
        var blockID: UUID?
        var title: String
        var start: Date
        var end: Date
        var policy: Policy
        var selection: SelectionKind
    }

    /// Un minuto de uso de apps distractoras detectado por DeviceActivity.
    struct UsageLogEntry: Codable, Equatable, Hashable {
        var activityName: String
        var minute: Int
        var detectedAt: Date
    }

    /// Un intento de abrir una app bloqueada (pulsación en el Shield).
    struct ShieldAttempt: Codable, Equatable, Hashable {
        var date: Date
        var action: String
    }

    // MARK: Helpers de lectura/escritura (seguros para extensiones)

    static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults = AppGroup.defaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String, defaults: UserDefaults = AppGroup.defaults) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    static func plans() -> [String: MonitorPlan] {
        load([String: MonitorPlan].self, key: Key.plans) ?? [:]
    }

    static func appendUsage(_ entry: UsageLogEntry) {
        var log = load([UsageLogEntry].self, key: Key.usageLog) ?? []
        guard !log.contains(where: { $0.activityName == entry.activityName && $0.minute == entry.minute }) else { return }
        log.append(entry)
        // Mantener el registro acotado (la app lo consume y lo limpia).
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
        save(log, key: Key.usageLog)
    }

    static func appendAttempt(_ attempt: ShieldAttempt) {
        var list = load([ShieldAttempt].self, key: Key.shieldAttempts) ?? []
        list.append(attempt)
        if list.count > 1000 { list.removeFirst(list.count - 1000) }
        save(list, key: Key.shieldAttempts)
    }

    static var workPassUntil: Date? {
        get { AppGroup.defaults.object(forKey: Key.workPassUntil) as? Date }
        set { AppGroup.defaults.set(newValue, forKey: Key.workPassUntil) }
    }

    /// Devuelve el plan cuyo intervalo contiene `date` y que requiere bloqueo.
    static func activeBlockingPlan(at date: Date = Date()) -> MonitorPlan? {
        plans().values
            .filter { $0.policy == .block && $0.start <= date && date < $0.end }
            .sorted { $0.start < $1.start }
            .last
    }
}
