import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Atributos de la Live Activity (pantalla de bloqueo + Dynamic Island).
/// Se comparte entre la app (que la inicia/actualiza) y la extensión de widgets (que la dibuja).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Título de la tarea actual.
        var title: String
        /// Tipo de bloque legible ("TRABAJO PROFUNDO").
        var kindLabel: String
        /// Fin previsto del bloque (para la cuenta atrás nativa del sistema).
        var plannedEnd: Date
        /// Inicio "virtual" para mostrar tiempo concentrado (inicio + pausas acumuladas).
        var focusStartReference: Date
        /// Si está en pausa o descanso, no se anima la cuenta atrás.
        var isPaused: Bool
        /// Segundos restantes congelados mientras está en pausa.
        var pausedRemaining: TimeInterval
        /// Estado legible ("En pausa", "Descanso").
        var statusLabel: String
    }

    /// Objetivo de la sesión (no cambia durante la actividad).
    var objective: String
    /// Color del bloque en hex.
    var colorHex: String
}
#endif
