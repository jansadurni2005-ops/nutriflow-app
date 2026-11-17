import Foundation
import SwiftData

// Todos los modelos son compatibles con CloudKit: atributos con valor por defecto,
// sin restricciones `.unique` y sin relaciones obligatorias. Las referencias entre
// entidades se hacen por UUID, lo que simplifica la sincronización opcional con iCloud.

// MARK: - Bloque de trabajo

@Model
final class WorkBlock {
    var id: UUID = UUID()
    var title: String = ""
    /// Inicio del día al que pertenece (para consultas rápidas).
    var day: Date = Date()
    var start: Date = Date()
    var end: Date = Date()

    var kindRaw: String = BlockKind.work.rawValue
    var categoryRaw: String = BlockCategory.other.rawValue
    var priorityRaw: Int = BlockPriority.medium.rawValue
    var statusRaw: String = BlockStatus.pending.rawValue

    var objective: String = ""
    var notes: String = ""
    var colorHex: String = "FF6500"

    // Alarmas
    var alarmBefore: Bool = true
    var alarmStart: Bool = true
    var alarmEnd: Bool = true
    var soundRaw: String = AlarmSound.system.rawValue

    /// Política de Screen Time (`nil` = la del tipo de bloque).
    var policyRaw: String? = nil

    // Origen
    var routineID: UUID? = nil
    var externalEventID: String? = nil

    // Registro real
    var actualStart: Date? = nil
    var actualEnd: Date? = nil
    var workedSeconds: Double = 0
    var distractionSeconds: Double = 0
    var pausedSeconds: Double = 0
    var breakSeconds: Double = 0
    /// `true` si el tiempo trabajado se introdujo a mano (se marca como dato manual).
    var workedIsManual: Bool = false
    var createdAt: Date = Date()

    init(title: String, start: Date, end: Date, kind: BlockKind = .work, category: BlockCategory = .other,
         priority: BlockPriority = .medium, colorHex: String = "FF6500") {
        self.id = UUID()
        self.title = title
        self.start = start
        self.end = end
        self.day = Calendar.current.startOfDay(for: start)
        self.kindRaw = kind.rawValue
        self.categoryRaw = category.rawValue
        self.priorityRaw = priority.rawValue
        self.colorHex = colorHex
        self.createdAt = Date()
    }

    // MARK: Accesores tipados

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .work }
        set { kindRaw = newValue.rawValue }
    }
    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var priority: BlockPriority {
        get { BlockPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    var status: BlockStatus {
        get { BlockStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
    var sound: AlarmSound {
        get { AlarmSound(rawValue: soundRaw) ?? .system }
        set { soundRaw = newValue.rawValue }
    }
    /// Política específica de este bloque (`nil` = usar la del tipo de bloque en Ajustes).
    var policyOverride: ScreenTimeShared.Policy? {
        get { policyRaw.flatMap(ScreenTimeShared.Policy.init(rawValue:)) }
        set { policyRaw = newValue?.rawValue }
    }

    /// Política efectiva teniendo en cuenta los ajustes del usuario.
    func effectivePolicy(_ settings: AppSettings) -> ScreenTimeShared.Policy {
        if let policyOverride { return policyOverride }
        switch kind {
        case .deepWork: return settings.policyDeepWork
        case .work: return settings.policyWork
        case .meeting, .breakTime: return .off
        }
    }

    var plannedSeconds: Double { max(0, end.timeIntervalSince(start)) }

    /// Retraso al empezar (segundos, ≥ 0). `nil` si no se ha empezado.
    var delaySeconds: Double? {
        guard let actualStart else { return nil }
        return max(0, actualStart.timeIntervalSince(start))
    }

    var isRepeating: Bool { routineID != nil }

    /// Ajusta inicio/fin manteniendo `day` coherente.
    func reschedule(start newStart: Date, end newEnd: Date) {
        start = newStart
        end = max(newEnd, newStart.addingTimeInterval(5 * 60))
        day = Calendar.current.startOfDay(for: newStart)
    }
}

// MARK: - Rutina semanal

/// Plantilla que genera bloques automáticamente los días de la semana indicados.
/// Cada elemento puede tener horarios distintos; para diferentes horarios según el
/// día se crean elementos distintos con diferentes `weekdays`.
@Model
final class RoutineItem {
    var id: UUID = UUID()
    var title: String = ""
    /// Días de la semana (1 = domingo … 7 = sábado, como `Calendar`) separados por comas.
    var weekdaysRaw: String = "2,3,4,5,6"
    var startMinutes: Int = 9 * 60
    var endMinutes: Int = 10 * 60
    var kindRaw: String = BlockKind.work.rawValue
    var categoryRaw: String = BlockCategory.other.rawValue
    var priorityRaw: Int = BlockPriority.medium.rawValue
    var objective: String = ""
    var notes: String = ""
    var colorHex: String = "FF6500"
    var alarmBefore: Bool = true
    var alarmStart: Bool = true
    var alarmEnd: Bool = true
    var soundRaw: String = AlarmSound.system.rawValue
    var policyRaw: String? = nil
    var isActive: Bool = true
    var createdAt: Date = Date()

    init(title: String, weekdays: Set<Int>, startMinutes: Int, endMinutes: Int, kind: BlockKind,
         category: BlockCategory, colorHex: String) {
        self.id = UUID()
        self.title = title
        self.weekdaysRaw = weekdays.sorted().map(String.init).joined(separator: ",")
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.kindRaw = kind.rawValue
        self.categoryRaw = category.rawValue
        self.colorHex = colorHex
        self.createdAt = Date()
    }

    var weekdays: Set<Int> {
        get { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { weekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }
    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .work }
        set { kindRaw = newValue.rawValue }
    }
    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var priority: BlockPriority {
        get { BlockPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}

// MARK: - Sesión de concentración

@Model
final class FocusSession {
    var id: UUID = UUID()
    var blockID: UUID? = nil
    var title: String = ""
    var objective: String = ""
    var kindRaw: String = BlockKind.deepWork.rawValue
    var categoryRaw: String = BlockCategory.other.rawValue
    var colorHex: String = "FF6500"

    var startedAt: Date = Date()
    var plannedEnd: Date = Date()
    var endedAt: Date? = nil

    /// Pausa en curso (interrupción): cuenta como "no concentrado".
    var pauseStartedAt: Date? = nil
    var pausedSeconds: Double = 0
    /// Descanso autorizado en curso ("Necesito descansar"): neutral para la concentración.
    var breakStartedAt: Date? = nil
    var breakSeconds: Double = 0

    var distractionSeconds: Double = 0
    var distractionCount: Int = 0
    var blockedAttempts: Int = 0

    var isActive: Bool = true
    var endReasonRaw: String? = nil
    var appBlockingEnabled: Bool = false
    var lastHeartbeat: Date = Date()
    var day: Date = Date()

    init(title: String, kind: BlockKind, plannedEnd: Date, blockID: UUID?, objective: String,
         category: BlockCategory, colorHex: String, startedAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.plannedEnd = plannedEnd
        self.blockID = blockID
        self.objective = objective
        self.categoryRaw = category.rawValue
        self.colorHex = colorHex
        self.startedAt = startedAt
        self.lastHeartbeat = startedAt
        self.day = Calendar.current.startOfDay(for: startedAt)
    }

    var kind: BlockKind { BlockKind(rawValue: kindRaw) ?? .deepWork }
    var category: BlockCategory { BlockCategory(rawValue: categoryRaw) ?? .other }
    var endReason: SessionEndReason? { endReasonRaw.flatMap(SessionEndReason.init(rawValue:)) }

    var isPaused: Bool { pauseStartedAt != nil }
    var isOnBreak: Bool { breakStartedAt != nil }

    // Todos los cálculos se basan en marcas temporales reales, de modo que el tiempo
    // es correcto aunque la app pase a segundo plano o se cierre.

    func elapsed(at now: Date = Date()) -> Double {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    func totalPaused(at now: Date = Date()) -> Double {
        pausedSeconds + (pauseStartedAt.map { max(0, (endedAt ?? now).timeIntervalSince($0)) } ?? 0)
    }

    func totalBreak(at now: Date = Date()) -> Double {
        breakSeconds + (breakStartedAt.map { max(0, (endedAt ?? now).timeIntervalSince($0)) } ?? 0)
    }

    /// Tiempo efectivo de concentración: transcurrido − pausas − descansos − distracciones.
    func focused(at now: Date = Date()) -> Double {
        max(0, elapsed(at: now) - totalPaused(at: now) - totalBreak(at: now) - distractionSeconds)
    }

    /// Tiempo restante hasta el fin previsto (negativo = tiempo extra).
    func remaining(at now: Date = Date()) -> Double {
        plannedEnd.timeIntervalSince(endedAt ?? now)
    }

    /// Progreso 0...1 del bloque por tiempo.
    func progress(at now: Date = Date()) -> Double {
        let total = plannedEnd.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, elapsed(at: now) / total))
    }

    /// Concentración de la sesión 0...1 (descansos autorizados excluidos).
    func concentration(at now: Date = Date()) -> Double? {
        let focusedTime = focused(at: now)
        let denominator = focusedTime + distractionSeconds + totalPaused(at: now)
        guard denominator >= 60 else { return nil }
        return focusedTime / denominator
    }
}

// MARK: - Distracción

@Model
final class DistractionEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var day: Date = Date()
    var durationSeconds: Double = 0
    var sourceRaw: String = DistractionSource.manual.rawValue
    var reasonRaw: String = DistractionReason.other.rawValue
    var sessionID: UUID? = nil
    var blockID: UUID? = nil
    var note: String = ""
    /// Uso dentro de un pase de trabajo autorizado: se guarda pero no penaliza.
    var isAuthorized: Bool = false

    init(date: Date, durationSeconds: Double, source: DistractionSource, reason: DistractionReason,
         sessionID: UUID?, blockID: UUID?, note: String = "", isAuthorized: Bool = false) {
        self.id = UUID()
        self.date = date
        self.day = Calendar.current.startOfDay(for: date)
        self.durationSeconds = durationSeconds
        self.sourceRaw = source.rawValue
        self.reasonRaw = reason.rawValue
        self.sessionID = sessionID
        self.blockID = blockID
        self.note = note
        self.isAuthorized = isAuthorized
    }

    var source: DistractionSource { DistractionSource(rawValue: sourceRaw) ?? .manual }
    var reason: DistractionReason { DistractionReason(rawValue: reasonRaw) ?? .other }
    /// Duración que penaliza (0 si autorizada o si es un intento bloqueado).
    var penalizedSeconds: Double { (isAuthorized || source == .shieldAttempt) ? 0 : durationSeconds }
}

// MARK: - Diario / revisión diaria

@Model
final class DayJournal {
    var id: UUID = UUID()
    var day: Date = Date()
    var improvementNote: String = ""
    var winsNote: String = ""
    var reviewedAt: Date? = nil
    var plannedTomorrow: Bool = false

    init(day: Date) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
    }
}

/// Esquema completo para el `ModelContainer`.
enum FocusSchema {
    static let models: [any PersistentModel.Type] = [
        WorkBlock.self, RoutineItem.self, FocusSession.self, DistractionEvent.self, DayJournal.self
    ]
}
