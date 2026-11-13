import Foundation
import SwiftData

/// Operaciones de planificación: rutinas, duplicado de días, mover tareas, bloques no realizados.
enum ScheduleService {

    private static let generatedKey = "schedule.generatedDays"

    private static func dayKey(_ day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(on day: Date, minutes: Int) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        return Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: Rutinas

    /// Genera los bloques de las rutinas activas para un día (solo una vez por día y nunca para el pasado).
    static func ensureRoutines(for day: Date, context: ModelContext, force: Bool = false) {
        let start = Calendar.current.startOfDay(for: day)
        guard start >= Calendar.current.startOfDay(for: Date()) else { return }
        var generated = Set(UserDefaults.standard.stringArray(forKey: generatedKey) ?? [])
        let key = dayKey(start)
        if generated.contains(key) && !force { return }

        let weekday = Calendar.current.component(.weekday, from: start)
        let routines = (try? context.fetch(FetchDescriptor<RoutineItem>(predicate: #Predicate { $0.isActive == true }))) ?? []
        let existing = DayDataService.blocks(on: start, context: context)
        let existingRoutineIDs = Set(existing.compactMap(\.routineID))

        for routine in routines where routine.weekdays.contains(weekday) && !existingRoutineIDs.contains(routine.id) {
            context.insert(makeBlock(from: routine, on: start))
        }

        generated.insert(key)
        // Conservar solo las últimas ~60 claves.
        let trimmed = Array(generated.sorted().suffix(60))
        UserDefaults.standard.set(trimmed, forKey: generatedKey)
        try? context.save()
    }

    static func makeBlock(from routine: RoutineItem, on day: Date) -> WorkBlock {
        let blockStart = date(on: day, minutes: routine.startMinutes)
        var endMinutes = routine.endMinutes
        if endMinutes <= routine.startMinutes { endMinutes = routine.startMinutes + 30 }
        let blockEnd = date(on: day, minutes: endMinutes)
        let block = WorkBlock(title: routine.title, start: blockStart, end: blockEnd, kind: routine.kind,
                              category: routine.category, priority: routine.priority, colorHex: routine.colorHex)
        block.objective = routine.objective
        block.notes = routine.notes
        block.alarmBefore = routine.alarmBefore
        block.alarmStart = routine.alarmStart
        block.alarmEnd = routine.alarmEnd
        block.soundRaw = routine.soundRaw
        block.policyRaw = routine.policyRaw
        block.routineID = routine.id
        return block
    }

    /// Tras editar una rutina, regenera sus bloques futuros que siguen pendientes y sin empezar.
    static func applyRoutineChange(_ routine: RoutineItem, context: ModelContext) {
        let now = Date()
        let routineID: UUID? = routine.id
        let descriptor = FetchDescriptor<WorkBlock>(predicate: #Predicate { $0.routineID == routineID && $0.start > now })
        let future = (try? context.fetch(descriptor)) ?? []
        var touchedDays = Set<Date>()
        for block in future where block.status == .pending && block.actualStart == nil {
            touchedDays.insert(block.day)
            context.delete(block)
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        // Hoy (si el nuevo horario aún no ha empezado) y mañana.
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let generatedBefore = touchedDays.contains(day)
                || (UserDefaults.standard.stringArray(forKey: generatedKey) ?? []).contains(dayKey(day))
            guard routine.isActive, routine.weekdays.contains(cal.component(.weekday, from: day)), generatedBefore else { continue }
            let block = makeBlock(from: routine, on: day)
            if block.start > now { context.insert(block) }
        }
        try? context.save()
    }

    static func deleteRoutine(_ routine: RoutineItem, context: ModelContext) {
        let now = Date()
        let routineID: UUID? = routine.id
        let descriptor = FetchDescriptor<WorkBlock>(predicate: #Predicate { $0.routineID == routineID && $0.start > now })
        for block in (try? context.fetch(descriptor)) ?? [] where block.status == .pending && block.actualStart == nil {
            context.delete(block)
        }
        context.delete(routine)
        try? context.save()
    }

    /// Crea una rutina semanal a partir de un bloque (opción "Repetición semanal").
    @discardableResult
    static func makeRoutine(from block: WorkBlock, weekdays: Set<Int>, context: ModelContext) -> RoutineItem {
        let routine = RoutineItem(title: block.title, weekdays: weekdays, startMinutes: minutes(of: block.start),
                                  endMinutes: minutes(of: block.end), kind: block.kind, category: block.category,
                                  colorHex: block.colorHex)
        routine.priority = block.priority
        routine.objective = block.objective
        routine.notes = block.notes
        routine.alarmBefore = block.alarmBefore
        routine.alarmStart = block.alarmStart
        routine.alarmEnd = block.alarmEnd
        routine.soundRaw = block.soundRaw
        routine.policyRaw = block.policyRaw
        context.insert(routine)
        block.routineID = routine.id
        try? context.save()
        return routine
    }

    // MARK: Mantenimiento

    /// Marca como "no realizado" los bloques vencidos que nunca se empezaron.
    static func markMissedBlocks(context: ModelContext, now: Date = Date()) {
        let pending = BlockStatus.pending.rawValue
        let descriptor = FetchDescriptor<WorkBlock>(predicate: #Predicate { $0.statusRaw == pending && $0.end < now })
        let overdue = (try? context.fetch(descriptor)) ?? []
        var changed = false
        for block in overdue where block.kind != .breakTime {
            if block.actualStart == nil && block.workedSeconds == 0 {
                block.status = .missed
            } else {
                // Se empezó pero no se cerró explícitamente: se considera completado si se trabajó ≥ 50 %.
                block.status = block.workedSeconds >= block.plannedSeconds * 0.5 ? .completed : .missed
            }
            changed = true
        }
        // Los descansos vencidos simplemente se dan por completados (no puntúan).
        for block in overdue where block.kind == .breakTime {
            block.status = .completed
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: Copiar / mover

    /// Duplica la planificación de un día en otro (sin registros reales). Evita duplicados exactos.
    @discardableResult
    static func duplicate(day source: Date, to target: Date, context: ModelContext) -> Int {
        let sourceBlocks = DayDataService.blocks(on: source, context: context)
        let targetBlocks = DayDataService.blocks(on: target, context: context)
        var created = 0
        for block in sourceBlocks {
            let startMin = minutes(of: block.start)
            let endMin = startMin + Int(block.plannedSeconds / 60)
            let newStart = date(on: target, minutes: startMin)
            let alreadyExists = targetBlocks.contains {
                $0.title == block.title && abs($0.start.timeIntervalSince(newStart)) < 60
            }
            if alreadyExists { continue }
            let copy = WorkBlock(title: block.title, start: newStart, end: date(on: target, minutes: endMin),
                                 kind: block.kind, category: block.category, priority: block.priority,
                                 colorHex: block.colorHex)
            copy.objective = block.objective
            copy.notes = block.notes
            copy.alarmBefore = block.alarmBefore
            copy.alarmStart = block.alarmStart
            copy.alarmEnd = block.alarmEnd
            copy.soundRaw = block.soundRaw
            copy.policyRaw = block.policyRaw
            context.insert(copy)
            created += 1
        }
        try? context.save()
        return created
    }

    /// Mueve una tarea no completada al día siguiente, a la misma hora (copia limpia; el original queda como no realizado).
    @discardableResult
    static func moveToNextDay(_ block: WorkBlock, context: ModelContext) -> WorkBlock {
        let cal = Calendar.current
        let newStart = cal.date(byAdding: .day, value: 1, to: block.start) ?? block.start
        let newEnd = cal.date(byAdding: .day, value: 1, to: block.end) ?? block.end
        let copy = WorkBlock(title: block.title, start: newStart, end: newEnd, kind: block.kind,
                             category: block.category, priority: block.priority, colorHex: block.colorHex)
        copy.objective = block.objective
        copy.notes = block.notes.isEmpty ? "Movida desde \(block.start.formatted(date: .abbreviated, time: .omitted))" : block.notes
        copy.alarmBefore = block.alarmBefore
        copy.alarmStart = block.alarmStart
        copy.alarmEnd = block.alarmEnd
        copy.soundRaw = block.soundRaw
        copy.policyRaw = block.policyRaw
        context.insert(copy)
        if block.status != .completed { block.status = .missed }
        try? context.save()
        return copy
    }

    // MARK: Plantilla inicial

    /// Rutina de ejemplo (lunes a viernes) basada en la jornada tipo del usuario.
    static func seedExampleRoutine(context: ModelContext) {
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let items: [(String, Int, Int, BlockKind, BlockCategory, String, String)] = [
            ("Planificación diaria", 6 * 60 + 30, 7 * 60, .work, .planning, "8E8E93", "Definir las 3 prioridades del día"),
            ("Trabajo profundo", 7 * 60, 9 * 60, .deepWork, .business, "FF6500", "Avanzar en el proyecto principal"),
            ("Responder mensajes", 9 * 60, 9 * 60 + 30, .work, .communication, "4C8DFF", "Bandeja de entrada a cero"),
            ("Revisiones de clientes", 9 * 60 + 30, 11 * 60, .work, .clients, "35D07F", "Revisar progresos y ajustar planes"),
            ("Descanso", 11 * 60, 11 * 60 + 15, .breakTime, .personal, "30D5C8", ""),
            ("Creación de contenido", 11 * 60 + 15, 12 * 60 + 30, .work, .content, "BF5AF2", "Publicar y responder comentarios"),
            ("Gestión del negocio", 12 * 60 + 30, 13 * 60, .work, .business, "FFD60A", "Finanzas y operaciones")
        ]
        for item in items {
            let routine = RoutineItem(title: item.0, weekdays: weekdays, startMinutes: item.1, endMinutes: item.2,
                                      kind: item.3, category: item.4, colorHex: item.5)
            routine.objective = item.6
            // En contenido se usa Instagram profesionalmente: no medir ni bloquear.
            if item.4 == .content { routine.policyRaw = ScreenTimeShared.Policy.off.rawValue }
            context.insert(routine)
        }
        try? context.save()
        ensureRoutines(for: Date(), context: context, force: true)
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
            ensureRoutines(for: tomorrow, context: context, force: true)
        }
    }

    /// Detecta solapamientos entre bloques de un mismo día.
    static func overlaps(in blocks: [WorkBlock]) -> Set<UUID> {
        var result = Set<UUID>()
        let sorted = blocks.sorted { $0.start < $1.start }
        for (i, a) in sorted.enumerated() {
            for b in sorted.dropFirst(i + 1) {
                if b.start >= a.end { break }
                result.insert(a.id)
                result.insert(b.id)
            }
        }
        return result
    }
}
