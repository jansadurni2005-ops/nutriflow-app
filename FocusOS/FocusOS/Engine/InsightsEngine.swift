import Foundation

/// Recomendaciones para "Qué puedo mejorar mañana", basadas en reglas sobre datos reales del día.
enum InsightsEngine {

    struct Insight: Identifiable, Equatable {
        enum Tone { case positive, improve, warning }
        var id = UUID()
        var icon: String
        var text: String
        var tone: Tone
    }

    static func insights(stats: DayStats, blocks: [WorkBlock], goals: Goals) -> [Insight] {
        let r = stats.result
        var list: [Insight] = []
        guard stats.hasData else {
            return [Insight(icon: "calendar.badge.plus", text: "No había nada planificado. Prepara mañana con 3–4 bloques realistas.", tone: .improve)]
        }

        let work = blocks.filter { $0.kind.countsAsWork }
        let delays = work.compactMap(\.delaySeconds)
        if !delays.isEmpty {
            let avg = delays.reduce(0, +) / Double(delays.count)
            if avg > 5 * 60 {
                list.append(Insight(icon: "clock.badge.exclamationmark",
                                    text: "Empezaste con \(TimeFormat.duration(avg)) de retraso medio. Deja preparado el primer bloque la noche anterior y activa el aviso 5 min antes.",
                                    tone: .improve))
            } else {
                list.append(Insight(icon: "clock.badge.checkmark", text: "Puntualidad sólida: retraso medio de \(TimeFormat.duration(avg)).", tone: .positive))
            }
        }

        let maxDistraction = Double(goals.maxDailyDistractionMinutes * 60)
        if r.distractionSeconds > maxDistraction {
            list.append(Insight(icon: "iphone.slash",
                                text: "\(TimeFormat.duration(r.distractionSeconds)) de distracciones (límite \(goals.maxDailyDistractionMinutes) min). Activa el bloqueo de apps en los bloques de trabajo profundo.",
                                tone: .warning))
        } else if r.effectiveSeconds > 0 {
            list.append(Insight(icon: "shield.lefthalf.filled", text: "Distracciones bajo control: \(TimeFormat.duration(r.distractionSeconds)).", tone: .positive))
        }

        if let adherence = r.components.first(where: { $0.kind == .adherence })?.value, adherence < 0.75 {
            list.append(Insight(icon: "calendar.badge.exclamationmark",
                                text: "Cumpliste el \(TimeFormat.percent(adherence)) del tiempo planificado. Planifica bloques más cortos o deja huecos de margen entre bloques.",
                                tone: .improve))
        }

        let missed = work.filter { $0.status == .missed }
        if !missed.isEmpty {
            list.append(Insight(icon: "arrow.uturn.forward",
                                text: "\(missed.count) bloque\(missed.count == 1 ? "" : "s") sin realizar. Muévelos a mañana o elimínalos para no arrastrar ruido.",
                                tone: .warning))
        }

        if r.deepWorkBlocksCompleted < goals.dailyDeepWorkBlocks {
            list.append(Insight(icon: "brain.head.profile",
                                text: "\(r.deepWorkBlocksCompleted) de \(goals.dailyDeepWorkBlocks) bloques de trabajo profundo. Protege la primera hora de la mañana para lo más importante.",
                                tone: .improve))
        } else {
            list.append(Insight(icon: "bolt.fill", text: "Objetivo de trabajo profundo cumplido (\(r.deepWorkBlocksCompleted) bloques).", tone: .positive))
        }

        if let concentration = r.components.first(where: { $0.kind == .concentration })?.value, concentration >= 0.9 {
            list.append(Insight(icon: "scope", text: "Concentración del \(TimeFormat.percent(concentration)). Repite las condiciones de hoy.", tone: .positive))
        }
        return list
    }
}
