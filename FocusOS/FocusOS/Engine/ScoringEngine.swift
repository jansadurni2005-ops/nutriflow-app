import Foundation

/// Hechos de un bloque necesarios para puntuar (desacoplados de SwiftData para poder testearlos).
struct BlockFacts: Equatable {
    var id: UUID = UUID()
    var kind: BlockKind
    var category: BlockCategory = .other
    var start: Date
    var end: Date
    var status: BlockStatus
    var actualStart: Date? = nil
    /// Tiempo trabajado (incluye la sesión activa en vivo si la hay).
    var workedSeconds: Double = 0
    var distractionSeconds: Double = 0
    var pausedSeconds: Double = 0
    var hadSession: Bool = false

    var plannedSeconds: Double { max(0, end.timeIntervalSince(start)) }
}

/// Sesiones libres (no asociadas a un bloque planificado).
struct FreeSessionFacts: Equatable {
    var focusedSeconds: Double
    var distractionSeconds: Double
    var pausedSeconds: Double
    var category: BlockCategory = .other
}

struct ScoreInput {
    var blocks: [BlockFacts]
    var freeSessions: [FreeSessionFacts] = []
    var now: Date
    var weights: ScoreWeights = .default
    var punctualityGrace: TimeInterval = 2 * 60
    var punctualityZero: TimeInterval = 30 * 60
    /// `true` si hay medición automática de distracciones (Screen Time) activa ese día.
    var automaticDistractionTracking: Bool = false
}

enum ScoreConfidence: String {
    case complete     // Todos los componentes con datos suficientes
    case estimated    // Faltan componentes o hay pocos datos
    case insufficient // No hay datos para puntuar

    var label: String {
        switch self {
        case .complete: return "Datos completos"
        case .estimated: return "Estimada"
        case .insufficient: return "Sin datos suficientes"
        }
    }
}

struct ScoreComponent: Identifiable, Equatable {
    enum Kind: String { case concentration, adherence, completion, punctuality }
    var kind: Kind
    var value: Double?
    var weight: Double
    var detail: String

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .concentration: return "Concentración"
        case .adherence: return "Cumplimiento del horario"
        case .completion: return "Tareas completadas"
        case .punctuality: return "Puntualidad"
        }
    }
}

struct ScoreResult: Equatable {
    var score: Double?
    var confidence: ScoreConfidence
    var components: [ScoreComponent]

    /// Tiempo de trabajo efectivo (concentrado) del día.
    var effectiveSeconds: Double
    /// Tiempo de trabajo planificado del día completo (sin descansos).
    var plannedSeconds: Double
    /// Parte del tiempo planificado que ya debería haber ocurrido.
    var plannedElapsedSeconds: Double
    var distractionSeconds: Double
    var pausedSeconds: Double
    /// Tiempo hasta el final del último bloque del día.
    var remainingDaySeconds: Double
    var blocksCompleted: Int
    var blocksTotal: Int
    var deepWorkBlocksCompleted: Int
    /// Tiempo efectivo en bloques de trabajo profundo.
    var deepWorkSeconds: Double
    /// Bloques completados con sesión y sin distracciones.
    var cleanBlocks: Int
    /// Bloques iniciados dentro del margen de puntualidad.
    var onTimeBlocks: Int
    /// 0...1 progreso temporal de la jornada.
    var dayProgress: Double
    var automaticDistractionTracking: Bool

    static let empty = ScoreResult(score: nil, confidence: .insufficient, components: [], effectiveSeconds: 0,
                                   plannedSeconds: 0, plannedElapsedSeconds: 0, distractionSeconds: 0,
                                   pausedSeconds: 0, remainingDaySeconds: 0, blocksCompleted: 0, blocksTotal: 0,
                                   deepWorkBlocksCompleted: 0, deepWorkSeconds: 0, cleanBlocks: 0, onTimeBlocks: 0,
                                   dayProgress: 0, automaticDistractionTracking: false)
}

/// Motor de efectividad.
///
/// Definiciones (todas visibles en la app, sección "Cómo se calcula"):
/// - **Concentración**: tiempo concentrado ÷ (concentrado + distracciones + pausas) en bloques
///   de trabajo y trabajo profundo. Los descansos autorizados y las reuniones/llamadas no cuentan.
/// - **Cumplimiento del horario**: Σ min(trabajado, planificado) ÷ Σ planificado de los bloques
///   que ya deberían haber ocurrido (el bloque en curso cuenta solo la parte transcurrida).
/// - **Tareas completadas**: bloques completados ÷ bloques ya vencidos o completados.
/// - **Puntualidad**: media por bloque iniciado; 100 % si el retraso ≤ margen, 0 % si ≥ límite, lineal entre medias.
///
/// Si un componente no tiene datos se excluye y los pesos se renormalizan; la puntuación se
/// marca entonces como "estimada". Nunca se inventan valores.
enum ScoringEngine {

    static let minimumDataSeconds: Double = 5 * 60

    static func evaluate(_ input: ScoreInput) -> ScoreResult {
        let now = input.now
        let workBlocks = input.blocks.filter { $0.kind.countsAsWork }

        // ── Tiempos base ──────────────────────────────────────────
        let plannedTotal = workBlocks.reduce(0) { $0 + $1.plannedSeconds }

        var plannedElapsed: Double = 0
        var adherenceNumerator: Double = 0
        var effective: Double = 0
        var concentrationFocused: Double = 0
        var concentrationDistraction: Double = 0
        var concentrationPaused: Double = 0
        var punctualityScores: [Double] = []
        var dueCount = 0
        var completedCount = 0
        var deepCompleted = 0
        var deepSeconds: Double = 0
        var cleanBlocks = 0
        var onTimeBlocks = 0

        for block in workBlocks {
            let worked = effectiveWorked(for: block)
            effective += worked
            if block.kind == .deepWork { deepSeconds += worked }
            if block.status == .completed && block.kind.tracksDistractions && block.hadSession && block.distractionSeconds == 0 {
                cleanBlocks += 1
            }

            // Parte del bloque que ya "debería" haber ocurrido.
            let evaluated: Double
            if block.status == .completed || block.status == .missed || block.end <= now {
                evaluated = block.plannedSeconds
            } else if block.start < now {
                evaluated = now.timeIntervalSince(block.start)
            } else {
                evaluated = 0
            }
            if evaluated > 0 {
                plannedElapsed += evaluated
                adherenceNumerator += min(worked, evaluated)
            }

            // Concentración: solo bloques que miden distracciones y que tienen datos.
            if block.kind.tracksDistractions && (block.hadSession || block.workedSeconds > 0 || block.distractionSeconds > 0) {
                concentrationFocused += block.workedSeconds
                concentrationDistraction += block.distractionSeconds
                concentrationPaused += block.pausedSeconds
            }

            // Tareas completadas.
            if block.status == .completed || block.status == .missed || block.end <= now {
                dueCount += 1
                if block.status == .completed {
                    completedCount += 1
                    if block.kind == .deepWork { deepCompleted += 1 }
                }
            }

            // Puntualidad.
            if let actualStart = block.actualStart {
                if actualStart.timeIntervalSince(block.start) <= input.punctualityGrace { onTimeBlocks += 1 }
                punctualityScores.append(punctuality(delay: actualStart.timeIntervalSince(block.start),
                                                     grace: input.punctualityGrace, zero: input.punctualityZero))
            }
        }

        for session in input.freeSessions {
            effective += session.focusedSeconds
            concentrationFocused += session.focusedSeconds
            concentrationDistraction += session.distractionSeconds
            concentrationPaused += session.pausedSeconds
        }

        let totalDistraction = workBlocks.reduce(0) { $0 + $1.distractionSeconds }
            + input.freeSessions.reduce(0) { $0 + $1.distractionSeconds }
        let totalPaused = concentrationPaused

        // ── Componentes ───────────────────────────────────────────
        let w = input.weights
        let concentrationDenominator = concentrationFocused + concentrationDistraction + concentrationPaused
        let concentrationValue: Double? = concentrationDenominator >= minimumDataSeconds
            ? concentrationFocused / concentrationDenominator : nil
        let adherenceValue: Double? = plannedElapsed >= minimumDataSeconds
            ? min(1, adherenceNumerator / plannedElapsed) : nil
        let completionValue: Double? = dueCount > 0 ? Double(completedCount) / Double(dueCount) : nil
        let punctualityValue: Double? = punctualityScores.isEmpty
            ? nil : punctualityScores.reduce(0, +) / Double(punctualityScores.count)

        let components = [
            ScoreComponent(kind: .concentration, value: concentrationValue, weight: w.concentration,
                           detail: concentrationValue == nil ? "Sin sesiones registradas"
                           : "\(TimeFormat.duration(concentrationFocused)) concentrado · \(TimeFormat.duration(concentrationDistraction)) distracciones · \(TimeFormat.duration(concentrationPaused)) pausas"),
            ScoreComponent(kind: .adherence, value: adherenceValue, weight: w.adherence,
                           detail: adherenceValue == nil ? "Aún no ha pasado tiempo planificado"
                           : "\(TimeFormat.duration(adherenceNumerator)) de \(TimeFormat.duration(plannedElapsed)) planificado hasta ahora"),
            ScoreComponent(kind: .completion, value: completionValue, weight: w.completion,
                           detail: completionValue == nil ? "Ningún bloque ha vencido todavía"
                           : "\(completedCount) de \(dueCount) bloques vencidos completados"),
            ScoreComponent(kind: .punctuality, value: punctualityValue, weight: w.punctuality,
                           detail: punctualityValue == nil ? "Ningún bloque iniciado"
                           : "\(punctualityScores.count) bloques iniciados")
        ]

        let available = components.filter { $0.value != nil && $0.weight > 0 }
        let weightSum = available.reduce(0) { $0 + $1.weight }
        let score: Double? = weightSum > 0
            ? available.reduce(0) { $0 + ($1.value ?? 0) * $1.weight } / weightSum
            : nil

        let confidence: ScoreConfidence
        if score == nil {
            confidence = .insufficient
        } else if available.count < components.filter({ $0.weight > 0 }).count
                    || plannedElapsed + concentrationDenominator < 30 * 60 {
            confidence = .estimated
        } else {
            confidence = .complete
        }

        // ── Jornada ───────────────────────────────────────────────
        let allSorted = input.blocks.sorted { $0.start < $1.start }
        var dayProgress: Double = 0
        var remaining: Double = 0
        if let first = allSorted.first?.start, let last = allSorted.map(\.end).max(), last > first {
            dayProgress = min(1, max(0, now.timeIntervalSince(first) / last.timeIntervalSince(first)))
            remaining = max(0, last.timeIntervalSince(now))
        }

        return ScoreResult(
            score: score,
            confidence: confidence,
            components: components,
            effectiveSeconds: effective,
            plannedSeconds: plannedTotal,
            plannedElapsedSeconds: plannedElapsed,
            distractionSeconds: totalDistraction,
            pausedSeconds: totalPaused,
            remainingDaySeconds: remaining,
            blocksCompleted: workBlocks.filter { $0.status == .completed }.count,
            blocksTotal: workBlocks.count,
            deepWorkBlocksCompleted: deepCompleted,
            deepWorkSeconds: deepSeconds,
            cleanBlocks: cleanBlocks,
            onTimeBlocks: onTimeBlocks,
            dayProgress: dayProgress,
            automaticDistractionTracking: input.automaticDistractionTracking
        )
    }

    /// Tiempo efectivo de un bloque. Las reuniones/llamadas completadas sin sesión registrada
    /// cuentan su duración planificada (no se penalizan llamadas profesionales).
    static func effectiveWorked(for block: BlockFacts) -> Double {
        if block.kind == .meeting && block.status == .completed && block.workedSeconds == 0 {
            return block.plannedSeconds
        }
        return block.workedSeconds
    }

    static func punctuality(delay: TimeInterval, grace: TimeInterval, zero: TimeInterval) -> Double {
        if delay <= grace { return 1 }
        if delay >= zero { return 0 }
        return 1 - (delay - grace) / (zero - grace)
    }
}
