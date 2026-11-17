import SwiftUI

/// Transparencia: qué hace FOCUS OS con cada permiso y qué límites impone iOS.
struct CapabilitiesView: View {
    @Environment(AppCoordinator.self) private var coordinator

    private struct Item: Identifiable {
        var id: String { title }
        var title: String
        var icon: String
        var status: Status
        var detail: String
        enum Status { case ok, partial, unavailable }
    }

    private var items: [Item] {
        let st = coordinator.screenTime
        return [
            Item(title: "Temporizador exacto", icon: "timer", status: .ok,
                 detail: "Basado en marcas temporales guardadas. Sigue siendo exacto en segundo plano, con la app cerrada o tras reiniciar."),
            Item(title: "Alarmas con la app cerrada", icon: "bell.badge", status: NotificationService.shared.isAuthorized ? .ok : .partial,
                 detail: "Notificaciones locales programadas en iOS. Límite de 64 pendientes: se programa una ventana rodante."),
            Item(title: "Live Activity y Dynamic Island", icon: "platter.filled.top.and.arrow.up.iphone", status: LiveActivityService.shared.areActivitiesEnabled ? .ok : .partial,
                 detail: "Cuenta atrás en pantalla de bloqueo animada por el sistema. Requiere iPhone con iOS 16.1+ (Dynamic Island: iPhone 14 Pro o posterior)."),
            Item(title: "Widget de inicio", icon: "square.grid.2x2", status: AppGroup.isAvailable ? .ok : .partial,
                 detail: AppGroup.isAvailable ? "Bloque actual, tiempo restante, efectividad y próxima tarea." : "El App Group no está firmado: el widget no puede leer datos. Revisa la firma (README)."),
            Item(title: "Bloqueo de apps (Shield)", icon: "lock.app.dashed", status: st.isAuthorized ? .ok : .unavailable,
                 detail: "FamilyControls + ManagedSettings. Requiere el entitlement Family Controls (cuenta de pago)."),
            Item(title: "Medición de uso de apps", icon: "chart.bar.doc.horizontal", status: st.automaticTrackingActive ? .ok : (st.isAuthorized ? .partial : .unavailable),
                 detail: "DeviceActivity: minutos acumulados de las apps elegidas por bloque (≥ 15 min). No sabe qué haces dentro de cada app."),
            Item(title: "Saber si un uso de Instagram es trabajo u ocio", icon: "questionmark.app", status: .unavailable,
                 detail: "iOS no lo permite. Solución: política por bloque (medir/bloquear/nada), pase de trabajo temporal y registro manual."),
            Item(title: "Detectar que sales de FOCUS OS", icon: "arrow.up.forward.app", status: .partial,
                 detail: "La app sabe que pasa a segundo plano, no a qué app vas. Si no bloqueas el iPhone, te envía un aviso «vuelve al foco». No cuenta como distracción automáticamente."),
            Item(title: "Google Calendar", icon: "calendar", status: coordinator.calendarService.hasReadAccess ? .ok : .partial,
                 detail: "Vía EventKit tras añadir la cuenta de Google en Ajustes de iOS. Solo lectura."),
            Item(title: "iCloud", icon: "icloud", status: coordinator.settings.iCloudSync ? .ok : .partial,
                 detail: "Opcional. SwiftData + CloudKit privado. Requiere cuenta de pago y capacidad iCloud.")
        ]
    }

    var body: some View {
        List {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                            Spacer()
                            switch item.status {
                            case .ok: Chip(text: "Activo", tint: Palette.success)
                            case .partial: Chip(text: "Parcial", tint: Palette.warning)
                            case .unavailable: Chip(text: "No disponible", tint: Palette.textSecondary)
                            }
                        }
                        Text(item.detail).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Palette.card)
            }
        }
        .navigationTitle("Permisos y límites")
    }
}
