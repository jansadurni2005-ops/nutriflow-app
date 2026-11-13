import SwiftUI

/// Tipo de bloque: determina cómo puntúa y qué política de distracciones aplica por defecto.
enum BlockKind: String, Codable, CaseIterable, Identifiable {
    case deepWork
    case work
    case meeting
    case breakTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepWork: return "Trabajo profundo"
        case .work: return "Trabajo"
        case .meeting: return "Reunión / llamada"
        case .breakTime: return "Descanso"
        }
    }

    var upperLabel: String { label.uppercased() }

    var icon: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .work: return "square.stack.3d.up"
        case .meeting: return "phone.bubble"
        case .breakTime: return "cup.and.saucer"
        }
    }

    /// Los descansos no cuentan como tiempo planificado de trabajo ni penalizan.
    var countsAsWork: Bool { self != .breakTime }

    /// Reuniones, llamadas y descansos no penalizan por distracciones.
    var tracksDistractions: Bool { self == .deepWork || self == .work }

    var defaultPolicy: ScreenTimeShared.Policy {
        switch self {
        case .deepWork: return .block
        case .work: return .measure
        case .meeting, .breakTime: return .off
        }
    }

    var selectionKind: ScreenTimeShared.SelectionKind {
        self == .deepWork ? .deepWork : .work
    }
}

enum BlockCategory: String, Codable, CaseIterable, Identifiable {
    case planning, clients, content, communication, business, learning, personal, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planning: return "Planificación"
        case .clients: return "Clientes"
        case .content: return "Contenido"
        case .communication: return "Comunicación"
        case .business: return "Negocio"
        case .learning: return "Formación"
        case .personal: return "Personal"
        case .other: return "Otro"
        }
    }

    var icon: String {
        switch self {
        case .planning: return "list.bullet.clipboard"
        case .clients: return "person.2"
        case .content: return "camera.aperture"
        case .communication: return "bubble.left.and.bubble.right"
        case .business: return "chart.line.uptrend.xyaxis"
        case .learning: return "book"
        case .personal: return "figure.run"
        case .other: return "circle.grid.2x2"
        }
    }
}

enum BlockPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0, medium = 1, high = 2, critical = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: return "Baja"
        case .medium: return "Media"
        case .high: return "Alta"
        case .critical: return "Crítica"
        }
    }

    var short: String {
        switch self {
        case .low: return "P4"
        case .medium: return "P3"
        case .high: return "P2"
        case .critical: return "P1"
        }
    }
}

enum BlockStatus: String, Codable, CaseIterable, Identifiable {
    case pending, inProgress, completed, missed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: return "Pendiente"
        case .inProgress: return "En curso"
        case .completed: return "Completado"
        case .missed: return "No realizado"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        case .missed: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending: return Palette.textSecondary
        case .inProgress: return Palette.accent
        case .completed: return Palette.success
        case .missed: return Palette.danger
        }
    }
}

enum SessionEndReason: String, Codable {
    case completed      // "He terminado" / "Finalizar bloque"
    case switched       // "Cambiar tarea"
    case abandoned      // Cancelada por el usuario
    case interrupted    // Detectada al reabrir la app (reinicio, app cerrada…)
}

enum DistractionSource: String, Codable, CaseIterable {
    case manual        // Marcada por el usuario
    case screenTime    // Medida por DeviceActivity
    case shieldAttempt // Intento de abrir una app bloqueada (no suma tiempo)

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .screenTime: return "Screen Time"
        case .shieldAttempt: return "Intento bloqueado"
        }
    }
}

enum DistractionReason: String, Codable, CaseIterable, Identifiable {
    case socialMedia, phone, interruption, mental, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .socialMedia: return "Redes sociales"
        case .phone: return "Móvil / mensajes"
        case .interruption: return "Interrupción"
        case .mental: return "Divagación"
        case .other: return "Otro"
        }
    }

    var icon: String {
        switch self {
        case .socialMedia: return "play.rectangle.on.rectangle"
        case .phone: return "iphone"
        case .interruption: return "person.wave.2"
        case .mental: return "cloud"
        case .other: return "ellipsis"
        }
    }
}

/// Sonidos de alarma. Los personalizados están en Resources/Sounds (WAV PCM, < 30 s, formato admitido por iOS).
enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case system
    case pulse
    case chime
    case rise
    case silent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistema"
        case .pulse: return "Pulse"
        case .chime: return "Chime"
        case .rise: return "Rise"
        case .silent: return "Silencio (solo vibración)"
        }
    }

    var fileName: String? {
        switch self {
        case .pulse: return "pulse.wav"
        case .chime: return "chime.wav"
        case .rise: return "rise.wav"
        case .system, .silent: return nil
        }
    }
}
