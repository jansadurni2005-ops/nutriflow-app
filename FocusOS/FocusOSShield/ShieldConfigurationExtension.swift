import UIKit
import ManagedSettings
import ManagedSettingsUI

/// Personaliza la pantalla que iOS muestra al intentar abrir una app bloqueada.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private var contextTitle: String {
        AppGroup.defaults.string(forKey: ScreenTimeShared.Key.shieldContext) ?? "Bloque de concentración"
    }

    private func makeConfiguration(appName: String?) -> ShieldConfiguration {
        let orange = UIColor(red: 1.0, green: 0.396, blue: 0.0, alpha: 1)
        let subtitle: String
        if let appName {
            subtitle = "\(appName) está en pausa durante «\(contextTitle)». Lo importante ahora es tu objetivo."
        } else {
            subtitle = "Esta app está en pausa durante «\(contextTitle)». Lo importante ahora es tu objetivo."
        }
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.035, green: 0.035, blue: 0.035, alpha: 0.96),
            icon: UIImage(systemName: "scope"),
            title: ShieldConfiguration.Label(text: "FOCUS OS", color: orange),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: UIColor(white: 0.85, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Volver al foco", color: .black),
            primaryButtonBackgroundColor: orange,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Lo necesito para trabajar", color: UIColor(white: 0.7, alpha: 1))
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(appName: webDomain.domain)
    }
}
