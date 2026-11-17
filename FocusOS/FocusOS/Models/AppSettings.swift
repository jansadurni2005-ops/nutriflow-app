import Foundation
import Observation

/// Pesos de la puntuación de efectividad. Se normalizan siempre a suma 1.
struct ScoreWeights: Codable, Equatable {
    var concentration: Double = 0.40
    var adherence: Double = 0.25
    var completion: Double = 0.25
    var punctuality: Double = 0.10

    var total: Double { concentration + adherence + completion + punctuality }

    static let `default` = ScoreWeights()
}

/// Objetivos del usuario.
struct Goals: Codable, Equatable {
    var weeklyEffectiveHours: Double = 35
    var targetEffectiveness: Double = 0.90
    var dailyDeepWorkBlocks: Int = 4
    var maxDailyDistractionMinutes: Int = 30
    var weeklyPlanAdherence: Double = 0.85
}

/// Preferencias de notificaciones.
struct NotificationPrefs: Codable, Equatable {
    var preAlertMinutes: Int = 5
    var notifyBefore: Bool = true
    var notifyStart: Bool = true
    var notifyEnd: Bool = true
    var notStartedReminder: Bool = true
    var notStartedDelayMinutes: Int = 5
    var breakApproaching: Bool = true
    var dayEnd: Bool = true
    var dailySummary: Bool = true
    var dailySummaryHour: Int = 21
    var dailySummaryMinute: Int = 0
    var motivational: Bool = true
    var motivationalMinutes: Int = 90
    var refocusNudge: Bool = true
    var refocusNudgeSeconds: Int = 60
    var timeSensitive: Bool = true
    var defaultSound: AlarmSound = .pulse
    var hapticsEnabled: Bool = true
}

struct AppSettings: Codable, Equatable {
    var weights: ScoreWeights = .default
    var goals: Goals = Goals()
    var notifications: NotificationPrefs = NotificationPrefs()
    /// Política de Screen Time por tipo de bloque.
    var policyDeepWork: ScreenTimeShared.Policy = .block
    var policyWork: ScreenTimeShared.Policy = .measure
    /// Duración del pase de trabajo (mínimo 15 min por la API de DeviceActivity).
    var workPassMinutes: Int = 15
    var iCloudSync: Bool = false
    var onboardingCompleted: Bool = false
    var askPlanTomorrow: Bool = true
    /// Margen de puntualidad: retrasos ≤ este valor puntúan 100 %.
    var punctualityGraceMinutes: Int = 2
    /// Retraso a partir del cual la puntualidad del bloque es 0 %.
    var punctualityZeroMinutes: Int = 30
    /// Momentos en que el usuario ya fue preguntado por planificar mañana (yyyy-MM-dd).
    var lastPlanPromptDay: String = ""
}

/// Almacén observable de ajustes, persistido en el App Group.
@Observable
final class SettingsStore {
    static let shared = SettingsStore()
    private static let key = "app.settings.v1"

    var settings: AppSettings {
        didSet { persist() }
    }

    private init() {
        if let data = AppGroup.defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
        // El ajuste de iCloud se lee al arrancar desde UserDefaults estándar.
        UserDefaults.standard.set(settings.iCloudSync, forKey: "focusos.iCloudSync")
    }

    func policy(for kind: BlockKind) -> ScreenTimeShared.Policy {
        switch kind {
        case .deepWork: return settings.policyDeepWork
        case .work: return settings.policyWork
        case .meeting, .breakTime: return .off
        }
    }
}
