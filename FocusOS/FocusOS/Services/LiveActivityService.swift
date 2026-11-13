import Foundation
import ActivityKit

/// Live Activity del temporizador (pantalla de bloqueo + Dynamic Island).
/// La cuenta atrás la anima el propio sistema con `Text(timerInterval:)`, así que no hacen
/// falta actualizaciones periódicas ni notificaciones push: solo se actualiza al pausar/reanudar.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var current: Activity<FocusActivityAttributes>?

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func state(for session: FocusSession) -> FocusActivityAttributes.ContentState {
        let now = Date()
        let label: String
        if session.isOnBreak { label = "Descanso" } else if session.isPaused { label = "En pausa" } else { label = "Concentrado" }
        return .init(title: session.title,
                     kindLabel: session.kind.upperLabel,
                     plannedEnd: session.plannedEnd,
                     focusStartReference: now.addingTimeInterval(-session.focused(at: now)),
                     isPaused: session.isPaused || session.isOnBreak,
                     pausedRemaining: max(0, session.remaining(at: now)),
                     statusLabel: label)
    }

    func start(for session: FocusSession) {
        guard areActivitiesEnabled else { return }
        endAll()
        let attributes = FocusActivityAttributes(objective: session.objective, colorHex: session.colorHex)
        let content = ActivityContent(state: state(for: session), staleDate: session.plannedEnd.addingTimeInterval(3600))
        current = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func update(for session: FocusSession) {
        let content = ActivityContent(state: state(for: session), staleDate: session.plannedEnd.addingTimeInterval(3600))
        if let current {
            Task { await current.update(content) }
        } else if let existing = Activity<FocusActivityAttributes>.activities.first {
            current = existing
            Task { await existing.update(content) }
        } else {
            start(for: session)
        }
    }

    func end(finalTitle: String? = nil) {
        endAll()
    }

    private func endAll() {
        let activities = Activity<FocusActivityAttributes>.activities
        current = nil
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
