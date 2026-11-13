import Foundation

/// Instantánea mínima del estado que la app publica para el widget.
/// La app la reescribe cada vez que cambia algo relevante y pide a WidgetKit recargar.
struct WidgetSnapshot: Codable, Equatable {
    struct BlockInfo: Codable, Equatable {
        var id: UUID
        var title: String
        var kindLabel: String
        var start: Date
        var end: Date
        var colorHex: String
    }

    var generatedAt: Date
    /// Bloques de hoy y mañana ordenados (el widget calcula cuál es el actual en cada entrada de la timeline).
    var blocks: [BlockInfo]
    /// Efectividad del día (0...1) o `nil` si no hay datos suficientes.
    var effectiveness: Double?
    var effectivenessIsEstimated: Bool
    /// Sesión activa (si la hay): fin previsto y si está en pausa.
    var activeSessionTitle: String?
    var activeSessionEnd: Date?
    var activeSessionPaused: Bool
    var activeSessionPausedRemaining: TimeInterval

    static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }

    func currentBlock(at date: Date) -> BlockInfo? {
        blocks.first { $0.start <= date && date < $0.end }
    }

    func nextBlock(after date: Date) -> BlockInfo? {
        blocks.first { $0.start > date }
    }
}
