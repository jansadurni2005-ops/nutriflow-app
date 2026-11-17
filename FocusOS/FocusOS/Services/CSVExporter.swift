import Foundation
import SwiftData

/// Exportación de datos a CSV (separador `;` y coma decimal para abrir directamente en Excel/Numbers en español).
enum CSVExporter {

    private static func escape(_ value: String) -> String {
        let needsQuotes = value.contains(";") || value.contains("\"") || value.contains("\n")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    private static func number(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Resumen diario.
    static func dailyCSV(stats: [DayStats]) -> String {
        var rows = ["fecha;efectividad_%;confianza;horas_planificadas;horas_efectivas;min_distraccion;bloques_completados;bloques_totales;concentracion_%;cumplimiento_%;tareas_%;puntualidad_%;intentos_bloqueados"]
        for s in stats {
            let r = s.result
            func comp(_ kind: ScoreComponent.Kind) -> String {
                guard let v = r.components.first(where: { $0.kind == kind })?.value else { return "" }
                return number(v * 100)
            }
            rows.append([
                dateFormatter.string(from: s.day),
                r.score.map { number($0 * 100) } ?? "",
                r.confidence.label,
                number(r.plannedSeconds / 3600, digits: 2),
                number(r.effectiveSeconds / 3600, digits: 2),
                number(r.distractionSeconds / 60, digits: 0),
                String(r.blocksCompleted),
                String(r.blocksTotal),
                comp(.concentration), comp(.adherence), comp(.completion), comp(.punctuality),
                String(s.blockedAttempts)
            ].joined(separator: ";"))
        }
        return rows.joined(separator: "\n")
    }

    /// Detalle de bloques.
    static func blocksCSV(blocks: [WorkBlock]) -> String {
        var rows = ["fecha;inicio;fin;tarea;tipo;categoria;prioridad;estado;inicio_real;fin_real;retraso_min;min_trabajados;min_distraccion;min_pausa;objetivo;notas"]
        for b in blocks {
            rows.append([
                dateFormatter.string(from: b.start),
                timeFormatter.string(from: b.start),
                timeFormatter.string(from: b.end),
                escape(b.title),
                b.kind.label,
                b.category.label,
                b.priority.label,
                b.status.label,
                b.actualStart.map { timeFormatter.string(from: $0) } ?? "",
                b.actualEnd.map { timeFormatter.string(from: $0) } ?? "",
                b.delaySeconds.map { number($0 / 60, digits: 0) } ?? "",
                number(b.workedSeconds / 60, digits: 0),
                number(b.distractionSeconds / 60, digits: 0),
                number(b.pausedSeconds / 60, digits: 0),
                escape(b.objective),
                escape(b.notes)
            ].joined(separator: ";"))
        }
        return rows.joined(separator: "\n")
    }

    /// Escribe ambos CSV en un directorio temporal y devuelve sus URLs.
    @MainActor
    static func export(days: Int, context: ModelContext, settings: AppSettings, automaticTracking: Bool) throws -> [URL] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let stats = DayDataService.stats(from: start, days: days, context: context, settings: settings,
                                         automaticTracking: automaticTracking)
        let end = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let blocks = DayDataService.blocks(from: start, to: end, context: context)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FocusOS-export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = dateFormatter.string(from: Date())
        let daily = dir.appendingPathComponent("focusos_resumen_diario_\(stamp).csv")
        let detail = dir.appendingPathComponent("focusos_bloques_\(stamp).csv")
        // BOM UTF-8 para que Excel reconozca los acentos.
        let bom = "\u{FEFF}"
        try (bom + dailyCSV(stats: stats)).write(to: daily, atomically: true, encoding: .utf8)
        try (bom + blocksCSV(blocks: blocks)).write(to: detail, atomically: true, encoding: .utf8)
        return [daily, detail]
    }
}
