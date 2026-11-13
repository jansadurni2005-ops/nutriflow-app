import Foundation
import SwiftData

/// Estadísticas de un día (para analytics, widget y revisión).
struct DayStats: Identifiable, Equatable {
    var day: Date
    var result: ScoreResult
    var categorySeconds: [BlockCategory: Double]
    var distractionCount: Int
    var blockedAttempts: Int

    var id: Date { day }
    var hasData: Bool { result.blocksTotal > 0 || result.effectiveSeconds > 0 }
}

/// Lecturas de SwiftData agregadas por día. Todas las cifras proceden de registros reales.
enum DayDataService {

    static func dayRange(_ day: Date) -> (Date, Date) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    static func blocks(on day: Date, context: ModelContext) -> [WorkBlock] {
        let (start, end) = dayRange(day)
        let descriptor = FetchDescriptor<WorkBlock>(
            predicate: #Predicate { $0.start >= start && $0.start < end },
            sortBy: [SortDescriptor(\.start)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func blocks(from start: Date, to end: Date, context: ModelContext) -> [WorkBlock] {
        let descriptor = FetchDescriptor<WorkBlock>(
            predicate: #Predicate { $0.start >= start && $0.start < end },
            sortBy: [SortDescriptor(\.start)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func sessions(from start: Date, to end: Date, context: ModelContext) -> [FocusSession] {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func distractions(from start: Date, to end: Date, context: ModelContext) -> [DistractionEvent] {
        let descriptor = FetchDescriptor<DistractionEvent>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func block(id: UUID, context: ModelContext) -> WorkBlock? {
        var descriptor = FetchDescriptor<WorkBlock>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func activeSession(context: ModelContext) -> FocusSession? {
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Convierte bloques + sesión activa en hechos para el motor de puntuación.
    static func facts(blocks: [WorkBlock], activeSession: FocusSession?, now: Date) -> [BlockFacts] {
        blocks.map { block in
            var worked = block.workedSeconds
            var distraction = block.distractionSeconds
            var paused = block.pausedSeconds
            var hadSession = block.actualStart != nil
            if let session = activeSession, session.isActive, session.blockID == block.id {
                worked += session.focused(at: now)
                distraction += session.distractionSeconds
                paused += session.totalPaused(at: now)
                hadSession = true
            }
            return BlockFacts(id: block.id, kind: block.kind, category: block.category, start: block.start,
                              end: block.end, status: block.status, actualStart: block.actualStart,
                              workedSeconds: worked, distractionSeconds: distraction, pausedSeconds: paused,
                              hadSession: hadSession)
        }
    }

    static func freeSessionFacts(_ sessions: [FocusSession], now: Date) -> [FreeSessionFacts] {
        sessions.filter { $0.blockID == nil }.map {
            FreeSessionFacts(focusedSeconds: $0.focused(at: now), distractionSeconds: $0.distractionSeconds,
                             pausedSeconds: $0.totalPaused(at: now), category: $0.category)
        }
    }

    /// Puntuación de un día. Para días pasados se evalúa al final del día.
    static func stats(for day: Date, context: ModelContext, settings: AppSettings, now: Date = Date(),
                      automaticTracking: Bool) -> DayStats {
        let (start, end) = Self.dayRange(day)
        let blocks = Self.blocks(on: day, context: context)
        let sessions = Self.sessions(from: start, to: end, context: context)
        let distractions = Self.distractions(from: start, to: end, context: context)
        let active = sessions.first { $0.isActive }
        return buildStats(day: start, blocks: blocks, sessions: sessions, distractions: distractions,
                          active: active, settings: settings, now: min(now, end), automaticTracking: automaticTracking)
    }

    /// Estadísticas de un rango de días con una sola lectura de la base de datos.
    static func stats(from startDay: Date, days: Int, context: ModelContext, settings: AppSettings,
                      now: Date = Date(), automaticTracking: Bool) -> [DayStats] {
        let cal = Calendar.current
        let rangeStart = cal.startOfDay(for: startDay)
        guard let rangeEnd = cal.date(byAdding: .day, value: days, to: rangeStart) else { return [] }
        let allBlocks = Self.blocks(from: rangeStart, to: rangeEnd, context: context)
        let allSessions = Self.sessions(from: rangeStart, to: rangeEnd, context: context)
        let allDistractions = Self.distractions(from: rangeStart, to: rangeEnd, context: context)

        let blocksByDay = Dictionary(grouping: allBlocks) { cal.startOfDay(for: $0.start) }
        let sessionsByDay = Dictionary(grouping: allSessions) { cal.startOfDay(for: $0.startedAt) }
        let distractionsByDay = Dictionary(grouping: allDistractions) { cal.startOfDay(for: $0.date) }

        return (0..<days).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: rangeStart) else { return nil }
            let (_, dayEnd) = Self.dayRange(day)
            let sessions = sessionsByDay[day] ?? []
            return buildStats(day: day, blocks: blocksByDay[day] ?? [], sessions: sessions,
                              distractions: distractionsByDay[day] ?? [], active: sessions.first { $0.isActive },
                              settings: settings, now: min(now, dayEnd), automaticTracking: automaticTracking)
        }
    }

    private static func buildStats(day: Date, blocks: [WorkBlock], sessions: [FocusSession],
                                   distractions: [DistractionEvent], active: FocusSession?,
                                   settings: AppSettings, now: Date, automaticTracking: Bool) -> DayStats {
        let facts = Self.facts(blocks: blocks, activeSession: active, now: now)
        let free = Self.freeSessionFacts(sessions, now: now)
        let input = ScoreInput(blocks: facts, freeSessions: free, now: now, weights: settings.weights,
                               punctualityGrace: TimeInterval(settings.punctualityGraceMinutes * 60),
                               punctualityZero: TimeInterval(settings.punctualityZeroMinutes * 60),
                               automaticDistractionTracking: automaticTracking)
        let result = ScoringEngine.evaluate(input)

        var categories: [BlockCategory: Double] = [:]
        for fact in facts where fact.kind.countsAsWork {
            categories[fact.category, default: 0] += ScoringEngine.effectiveWorked(for: fact)
        }
        for session in free {
            categories[session.category, default: 0] += session.focusedSeconds
        }

        return DayStats(day: day, result: result, categorySeconds: categories,
                        distractionCount: distractions.filter { $0.source != .shieldAttempt && !$0.isAuthorized }.count,
                        blockedAttempts: distractions.filter { $0.source == .shieldAttempt }.count)
    }
}
