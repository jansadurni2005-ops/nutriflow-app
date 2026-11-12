import Foundation

/// Rachas, logros y XP calculados de forma determinista a partir del historial real.
/// No se almacena nada "inventado": si borras datos, los logros se recalculan.
enum GamificationEngine {

    struct Achievement: Identifiable, Equatable {
        var id: String
        var title: String
        var detail: String
        var icon: String
        var progress: Double   // 0...1
        var progressLabel: String
        var unlocked: Bool { progress >= 1 }
    }

    struct Summary: Equatable {
        var totalXP: Int
        var level: Int
        var levelTitle: String
        var xpIntoLevel: Int
        var xpForNextLevel: Int
        var currentStreak: Int
        var bestStreak: Int
        var achievements: [Achievement]
        var todayXP: Int

        var levelProgress: Double {
            xpForNextLevel > 0 ? Double(xpIntoLevel) / Double(xpForNextLevel) : 0
        }
    }

    // MARK: XP

    static func xp(for stats: DayStats, goals: Goals) -> Int {
        let r = stats.result
        guard stats.hasData else { return 0 }
        let deepMinutes = r.deepWorkSeconds / 60
        let otherMinutes = max(0, r.effectiveSeconds - r.deepWorkSeconds) / 60
        var xp = deepMinutes * 1.0 + otherMinutes * 0.5
        xp += Double(r.blocksCompleted * 20)
        xp += Double(r.cleanBlocks * 10)
        if let score = r.score, score >= goals.targetEffectiveness, r.confidence != .insufficient { xp += 50 }
        if r.deepWorkBlocksCompleted >= goals.dailyDeepWorkBlocks { xp += 30 }
        if r.effectiveSeconds > 0 && r.distractionSeconds <= Double(goals.maxDailyDistractionMinutes * 60) { xp += 20 }
        return Int(xp.rounded())
    }

    /// XP acumulado necesario para alcanzar el nivel `n` (n ≥ 1). Curva suave y creciente.
    static func xpRequired(forLevel n: Int) -> Int {
        guard n > 1 else { return 0 }
        return (1..<n).reduce(0) { $0 + 400 + ($1 - 1) * 150 }
    }

    static func levelTitle(_ level: Int) -> String {
        switch level {
        case ..<3: return "Iniciado"
        case ..<6: return "Constante"
        case ..<10: return "Enfocado"
        case ..<15: return "Disciplinado"
        case ..<21: return "Operador"
        case ..<28: return "Estratega"
        case ..<36: return "Élite"
        default: return "Maestro del foco"
        }
    }

    // MARK: Rachas

    /// Día productivo = efectividad ≥ objetivo con datos. Días sin planificación ni sesiones son neutros.
    static func isProductive(_ stats: DayStats, goals: Goals) -> Bool? {
        guard stats.hasData else { return nil }
        guard let score = stats.result.score else { return false }
        return score >= goals.targetEffectiveness
    }

    /// `history` en orden cronológico; el último elemento es hoy.
    static func streaks(_ history: [DayStats], goals: Goals) -> (current: Int, best: Int) {
        var best = 0
        var running = 0
        for day in history {
            switch isProductive(day, goals: goals) {
            case .some(true): running += 1; best = max(best, running)
            case .some(false): running = 0
            case .none: continue
            }
        }
        // Racha actual: hacia atrás desde ayer; hoy suma si ya es productivo, pero no rompe si aún no.
        var current = 0
        for (index, day) in history.enumerated().reversed() {
            let isToday = index == history.count - 1
            switch isProductive(day, goals: goals) {
            case .some(true): current += 1
            case .some(false): if isToday { continue } else { return (current, max(best, current)) }
            case .none: continue
            }
        }
        return (current, max(best, current))
    }

    // MARK: Resumen

    static func summary(history: [DayStats], goals: Goals) -> Summary {
        let totalXP = history.reduce(0) { $0 + xp(for: $1, goals: goals) }
        var level = 1
        while xpRequired(forLevel: level + 1) <= totalXP { level += 1 }
        let base = xpRequired(forLevel: level)
        let next = xpRequired(forLevel: level + 1)
        let (current, best) = streaks(history, goals: goals)
        let todayXP = history.last.map { xp(for: $0, goals: goals) } ?? 0

        return Summary(totalXP: totalXP, level: level, levelTitle: levelTitle(level),
                       xpIntoLevel: totalXP - base, xpForNextLevel: next - base,
                       currentStreak: current, bestStreak: best,
                       achievements: achievements(history: history, goals: goals, bestStreak: best),
                       todayXP: todayXP)
    }

    static func achievements(history: [DayStats], goals: Goals, bestStreak: Int) -> [Achievement] {
        let deepHours = history.reduce(0) { $0 + $1.result.deepWorkSeconds } / 3600
        let totalHours = history.reduce(0) { $0 + $1.result.effectiveSeconds } / 3600
        let cleanBlocks = history.reduce(0) { $0 + $1.result.cleanBlocks }
        let onTime = history.reduce(0) { $0 + $1.result.onTimeBlocks }
        let firstDeep = history.contains { $0.result.deepWorkBlocksCompleted > 0 }

        // Semanas (lunes a domingo) con media ≥ 90 % y ≥ 3 días con datos; y semanas con horas objetivo.
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "es_ES")
        let byWeek = Dictionary(grouping: history) { calendar.dateInterval(of: .weekOfYear, for: $0.day)?.start ?? $0.day }
        var bestWeekAvg: Double = 0
        var bestWeekHours: Double = 0
        for (_, days) in byWeek {
            let scored = days.compactMap(\.result.score)
            if scored.count >= 3 { bestWeekAvg = max(bestWeekAvg, scored.reduce(0, +) / Double(scored.count)) }
            bestWeekHours = max(bestWeekHours, days.reduce(0) { $0 + $1.result.effectiveSeconds } / 3600)
        }
        let zeroDistractionDay = history.contains {
            $0.result.blocksCompleted >= 3 && $0.result.distractionSeconds == 0 && $0.distractionCount == 0
        }

        func ratio(_ value: Double, _ target: Double) -> Double { target > 0 ? min(1, value / target) : 0 }

        return [
            Achievement(id: "first-deep", title: "Primer bloque profundo", detail: "Completa un bloque de trabajo profundo.",
                        icon: "bolt.fill", progress: firstDeep ? 1 : 0, progressLabel: firstDeep ? "Conseguido" : "0/1"),
            Achievement(id: "streak-7", title: "Siete de siete", detail: "7 días seguidos cumpliendo tu objetivo de efectividad.",
                        icon: "flame.fill", progress: ratio(Double(bestStreak), 7), progressLabel: "\(min(bestStreak, 7))/7 días"),
            Achievement(id: "deep-20", title: "20 h de profundidad", detail: "Acumula 20 horas de trabajo profundo efectivo.",
                        icon: "brain.head.profile", progress: ratio(deepHours, 20),
                        progressLabel: "\(deepHours.formatted(.number.precision(.fractionLength(1))))/20 h"),
            Achievement(id: "clean-10", title: "Diez bloques limpios", detail: "10 bloques completados sin ninguna distracción.",
                        icon: "checkmark.seal.fill", progress: ratio(Double(cleanBlocks), 10), progressLabel: "\(min(cleanBlocks, 10))/10"),
            Achievement(id: "week-90", title: "Semana de élite", detail: "Una semana con efectividad media superior al 90 %.",
                        icon: "crown.fill", progress: ratio(bestWeekAvg, 0.9), progressLabel: TimeFormat.percent(bestWeekAvg) + " mejor semana"),
            Achievement(id: "week-hours", title: "Objetivo semanal", detail: "Alcanza \(Int(goals.weeklyEffectiveHours)) h efectivas en una semana.",
                        icon: "target", progress: ratio(bestWeekHours, goals.weeklyEffectiveHours),
                        progressLabel: "\(bestWeekHours.formatted(.number.precision(.fractionLength(1))))/\(Int(goals.weeklyEffectiveHours)) h"),
            Achievement(id: "punctual-25", title: "Reloj suizo", detail: "Empieza 25 bloques a su hora.",
                        icon: "clock.badge.checkmark", progress: ratio(Double(onTime), 25), progressLabel: "\(min(onTime, 25))/25"),
            Achievement(id: "zero-day", title: "Día sin ruido", detail: "Un día con 3+ bloques completados y cero distracciones.",
                        icon: "speaker.slash.fill", progress: zeroDistractionDay ? 1 : 0, progressLabel: zeroDistractionDay ? "Conseguido" : "Pendiente"),
            Achievement(id: "hours-100", title: "Centenario", detail: "100 horas de trabajo efectivo registradas.",
                        icon: "hourglass", progress: ratio(totalHours, 100),
                        progressLabel: "\(Int(totalHours))/100 h")
        ]
    }
}
