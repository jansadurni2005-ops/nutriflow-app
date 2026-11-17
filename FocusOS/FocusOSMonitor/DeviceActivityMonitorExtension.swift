import Foundation
import DeviceActivity
import ManagedSettings
import FamilyControls

/// Extensión que iOS ejecuta en segundo plano (aunque FOCUS OS esté cerrada) cuando:
/// - empieza o termina el intervalo de una actividad programada (bloque, sesión o pase de trabajo),
/// - el uso acumulado de las apps seleccionadas alcanza un umbral (1, 2, 3… minutos).
///
/// Límite de memoria muy estricto (~6 MB): solo se leen/escriben pequeños JSON en el App Group.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let name = activity.rawValue
        if name == ScreenTimeShared.workPassActivity { return }
        guard let plan = ScreenTimeShared.plans()[name] else { return }
        if plan.policy == .block {
            ShieldApplier.apply(plan.selection, title: plan.title)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let name = activity.rawValue
        if name == ScreenTimeShared.workPassActivity {
            // Fin del pase de trabajo: volver a bloquear si sigue habiendo un bloque/sesión con bloqueo.
            ScreenTimeShared.workPassUntil = nil
            ShieldApplier.reconcile()
            return
        }
        // Fin de un bloque o sesión: retirar su bloqueo (manteniendo otros vigentes).
        ShieldApplier.reconcile(excluding: name)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let raw = event.rawValue
        guard raw.hasPrefix(ScreenTimeShared.minuteEventPrefix),
              let minute = Int(raw.dropFirst(ScreenTimeShared.minuteEventPrefix.count)) else { return }
        ScreenTimeShared.appendUsage(.init(activityName: activity.rawValue, minute: minute, detectedAt: Date()))
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }
}
