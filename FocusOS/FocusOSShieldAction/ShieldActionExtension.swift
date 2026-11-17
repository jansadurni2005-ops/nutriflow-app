import Foundation
import ManagedSettings

/// Gestiona los botones del Shield.
/// - "Volver al foco": registra el intento y cierra la app bloqueada.
/// - "Lo necesito para trabajar": registra el intento. iOS no permite abrir FOCUS OS desde aquí,
///   así que el Shield se cierra y el usuario puede activar un *pase de trabajo* desde la app
///   (queda registrado como uso autorizado).
final class ShieldActionExtension: ShieldActionDelegate {

    private func record(_ action: ShieldAction) {
        let label: String
        switch action {
        case .primaryButtonPressed: label = "back_to_focus"
        case .secondaryButtonPressed: label = "needs_for_work"
        @unknown default: label = "unknown"
        }
        ScreenTimeShared.appendAttempt(.init(date: Date(), action: label))
    }

    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        record(action)
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        record(action)
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        record(action)
        completionHandler(.close)
    }
}
