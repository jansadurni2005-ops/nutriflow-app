import Foundation
import WidgetKit

/// Publica una instantánea del día en el App Group y pide a WidgetKit que recargue.
@MainActor
enum WidgetBridge {
    private static var lastSnapshot: WidgetSnapshot?

    static func publish(blocks: [WorkBlock], score: ScoreResult, session: FocusSession?) {
        let now = Date()
        let infos = blocks
            .filter { $0.end > now.addingTimeInterval(-60) }
            .sorted { $0.start < $1.start }
            .prefix(24)
            .map { WidgetSnapshot.BlockInfo(id: $0.id, title: $0.title, kindLabel: $0.kind.upperLabel,
                                            start: $0.start, end: $0.end, colorHex: $0.colorHex) }
        let rounded = score.score.map { ($0 * 100).rounded() / 100 }
        let snapshot = WidgetSnapshot(generatedAt: now, blocks: Array(infos), effectiveness: rounded,
                                      effectivenessIsEstimated: score.confidence != .complete,
                                      activeSessionTitle: session?.title, activeSessionEnd: session?.plannedEnd,
                                      activeSessionPaused: (session?.isPaused ?? false) || (session?.isOnBreak ?? false),
                                      activeSessionPausedRemaining: session.map { max(0, ($0.remaining(at: now) / 60).rounded() * 60) } ?? 0)
        // Evitar recargas innecesarias (WidgetKit limita el presupuesto de recargas diarias).
        if let last = lastSnapshot {
            var comparable = snapshot
            comparable.generatedAt = last.generatedAt
            if comparable == last { return }
        }
        snapshot.save()
        lastSnapshot = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }
}
