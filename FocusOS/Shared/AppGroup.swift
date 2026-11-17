import Foundation

/// Acceso al contenedor compartido (App Group) entre la app y sus extensiones.
/// El identificador se lee del Info.plist (clave `AppGroupIdentifier`), que a su vez
/// se rellena desde el ajuste de compilación `APP_GROUP_ID` de project.yml.
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String) ?? "group.com.tunombre.focusos"
    }

    /// `true` si el App Group está correctamente firmado y accesible.
    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    /// UserDefaults compartidos. Si el App Group no está disponible (por ejemplo,
    /// cuenta gratuita sin la capacidad), se usa `.standard` para que la app siga funcionando.
    static var defaults: UserDefaults {
        if isAvailable, let shared = UserDefaults(suiteName: identifier) {
            return shared
        }
        return .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
