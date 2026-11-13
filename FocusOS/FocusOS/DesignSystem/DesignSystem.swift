import SwiftUI

// MARK: - Tipografía
// Estética deportiva: números condensados y pesados, etiquetas en mayúsculas expandidas.

extension Font {
    /// Números grandes (temporizador, puntuación).
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default).width(.condensed).monospacedDigit()
    }
    /// Etiquetas en mayúsculas tipo "EFECTIVIDAD".
    static let overline = Font.system(size: 11, weight: .semibold).width(.expanded)
    static let cardTitle = Font.system(size: 17, weight: .semibold)
    static let screenTitle = Font.system(size: 30, weight: .heavy).width(.expanded)
}

extension Text {
    func overlineStyle(_ color: Color = Palette.textSecondary) -> some View {
        self.font(.overline).tracking(1.4).foregroundStyle(color)
    }
}

// MARK: - Tarjeta

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    var highlight: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(highlight?.opacity(0.45) ?? Palette.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 18, highlight: Color? = nil) -> some View {
        modifier(CardModifier(padding: padding, highlight: highlight))
    }

    /// Fondo de pantalla estándar.
    func screenBackground() -> some View {
        self.background(Palette.background.ignoresSafeArea())
    }
}

// MARK: - Anillo de progreso

struct RingGauge<Center: View>: View {
    var value: Double?
    var lineWidth: CGFloat = 16
    var tint: Color = Palette.accent
    var trackColor: Color = Color.white.opacity(0.06)
    var dashed: Bool = false
    @ViewBuilder var center: () -> Center

    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: animated)
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(animated, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dashed ? [2, 6] : [])
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.35), radius: 10)
            center()
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { animated = min(1, value ?? 0) } }
        .onChange(of: value) { _, newValue in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { animated = min(1, newValue ?? 0) }
        }
    }
}

// MARK: - Barra de progreso

struct ProgressBar: View {
    var value: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.6), value: value)
    }
}

// MARK: - Métrica

struct MetricTile: View {
    var title: String
    var value: String
    var icon: String
    var tint: Color = Palette.textPrimary
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint.opacity(0.9))
                Text(title).overlineStyle()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(value)
                .font(.metric(24))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.cardElevated))
    }
}

// MARK: - Botones

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.cardElevated))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.stroke))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Botón circular de control (pausar, distracción…).
struct ControlButton: View {
    var icon: String
    var label: String
    var tint: Color = Palette.textPrimary
    var filled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(filled ? .black : tint)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(filled ? tint : Palette.cardElevated))
                    .overlay(Circle().strokeBorder(filled ? .clear : Palette.stroke))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Chips

struct Chip: View {
    var text: String
    var icon: String? = nil
    var tint: Color = Palette.textSecondary
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(selected ? .black : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(selected ? Palette.accent : tint.opacity(0.12)))
    }
}

// MARK: - Cabecera de sección

struct SectionHeader: View {
    var title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased()).overlineStyle()
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Estado vacío

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Palette.accentSoft))
            Text(title).font(.cardTitle).foregroundStyle(Palette.textPrimary)
            Text(message).font(.subheadline).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - Toast

struct ToastView: View {
    var toast: Toast

    private var tint: Color {
        switch toast.style {
        case .info: return Palette.info
        case .success: return Palette.success
        case .warning: return Palette.warning
        }
    }

    private var icon: String {
        switch toast.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(toast.message).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.4)))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}

// MARK: - Cabecera de pantalla

struct ScreenHeader<Trailing: View>: View {
    var overline: String
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(overline.uppercased()).overlineStyle(Palette.accent)
                Text(title).font(.screenTitle).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(overline: String, title: String) {
        self.init(overline: overline, title: title, trailing: { EmptyView() })
    }
}

// MARK: - Indicador de confianza

struct ConfidenceBadge: View {
    var confidence: ScoreConfidence

    var body: some View {
        switch confidence {
        case .complete:
            Chip(text: "Datos completos", icon: "checkmark.seal.fill", tint: Palette.success)
        case .estimated:
            Chip(text: "Estimada", icon: "exclamationmark.circle", tint: Palette.warning)
        case .insufficient:
            Chip(text: "Sin datos suficientes", icon: "questionmark.circle", tint: Palette.textSecondary)
        }
    }
}
