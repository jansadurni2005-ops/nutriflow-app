import Foundation
import FamilyControls
import ManagedSettings

/// Aplica y retira el bloqueo (Shield) de las apps seleccionadas.
/// Se usa desde la app y desde la extensión DeviceActivityMonitor (que puede ejecutarse con la app cerrada).
enum ShieldApplier {

    static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeShared.storeName))
    }

    static func loadSelection(_ kind: ScreenTimeShared.SelectionKind) -> FamilyActivitySelection {
        guard let data = AppGroup.defaults.data(forKey: kind.key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    static func saveSelection(_ selection: FamilyActivitySelection, kind: ScreenTimeShared.SelectionKind) {
        if let data = try? JSONEncoder().encode(selection) {
            AppGroup.defaults.set(data, forKey: kind.key)
        }
    }

    static func isEmpty(_ selection: FamilyActivitySelection) -> Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    /// Activa el Shield para la selección indicada. Respeta un pase de trabajo vigente.
    static func apply(_ kind: ScreenTimeShared.SelectionKind, title: String, now: Date = Date()) {
        if let pass = ScreenTimeShared.workPassUntil, pass > now { return }
        let selection = loadSelection(kind)
        guard !isEmpty(selection) else { return }
        let store = Self.store
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        if selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        } else {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
            store.shield.webDomainCategories = .specific(selection.categoryTokens)
        }
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        AppGroup.defaults.set(title, forKey: ScreenTimeShared.Key.shieldContext)
    }

    static func clear() {
        store.clearAllSettings()
        AppGroup.defaults.removeObject(forKey: ScreenTimeShared.Key.shieldContext)
    }

    /// Reaplica el bloqueo si hay algún plan de bloqueo vigente; si no, lo retira.
    static func reconcile(now: Date = Date(), excluding activityName: String? = nil) {
        let active = ScreenTimeShared.plans().values
            .filter { $0.policy == .block && $0.start <= now && now < $0.end && $0.activityName != activityName }
            .sorted { $0.start < $1.start }
            .last
        if let active {
            apply(active.selection, title: active.title, now: now)
        } else {
            clear()
        }
    }
}
