import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var page = 0
    @State private var notificationsGranted: Bool?
    @State private var screenTimeRequested = false
    @Query private var routines: [RoutineItem]

    private let pages = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Capsule().fill(i <= page ? Palette.accent : Palette.cardElevated).frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            TabView(selection: $page) {
                welcome.tag(0)
                scoring.tag(1)
                notifications.tag(2)
                screenTime.tag(3)
                firstDay.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)
        }
        .background(Palette.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func pageLayout<Content: View>(icon: String, overline: String, title: String, text: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.accentSoft))
            Text(overline.uppercased()).overlineStyle(Palette.accent)
            Text(title).font(.system(size: 34, weight: .heavy).width(.expanded)).foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(text).font(.body).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            content()
        }
        .padding(24)
    }

    private var next: some View {
        Button("Continuar") { withAnimation { page += 1 } }.buttonStyle(PrimaryButtonStyle())
    }

    private var welcome: some View {
        pageLayout(icon: "scope", overline: "FOCUS OS", title: "Tu sistema operativo de trabajo",
                   text: "Planifica tu jornada en bloques, mide el tiempo que trabajas de verdad, detecta distracciones y mira cómo evoluciona tu rendimiento.") {
            next
        }
    }

    private var scoring: some View {
        pageLayout(icon: "gauge.with.dots.needle.67percent", overline: "Puntuación honesta", title: "Nada de números inventados",
                   text: "Tu efectividad combina concentración (40 %), cumplimiento del horario (25 %), tareas completadas (25 %) y puntualidad (10 %). Los descansos y reuniones no penalizan. Si faltan datos, verás «Estimada» o «Sin datos».") {
            next
        }
    }

    private var notifications: some View {
        pageLayout(icon: "bell.badge.fill", overline: "Alarmas", title: "Avisos aunque la app esté cerrada",
                   text: "5 minutos antes de cada bloque, al empezar, al terminar, si no has empezado, antes del descanso y al cerrar la jornada.") {
            VStack(spacing: 10) {
                if let granted = notificationsGranted {
                    Label(granted ? "Notificaciones activadas" : "Puedes activarlas más tarde en Ajustes",
                          systemImage: granted ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(granted ? Palette.success : Palette.warning)
                        .font(.subheadline.weight(.semibold))
                    next
                } else {
                    Button("Activar notificaciones") {
                        Task { notificationsGranted = await NotificationService.shared.requestAuthorization() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Ahora no") { withAnimation { page += 1 } }.foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private var screenTime: some View {
        let st = coordinator.screenTime
        return pageLayout(icon: "hourglass.badge.lock", overline: "Distracciones", title: "Bloquea y mide lo que te distrae",
                          text: "Con la API oficial de Tiempo de uso, FOCUS OS puede bloquear TikTok, Instagram, YouTube o X durante tus bloques y medir cuántos minutos las usas. Apple no permite saber qué haces dentro de cada app: para eso tendrás pases de trabajo y registro manual.") {
            VStack(spacing: 10) {
                if st.isAuthorized {
                    Label("Screen Time autorizado. Elige tus apps en Ajustes › Distracciones.", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(Palette.success).font(.subheadline.weight(.semibold))
                    next
                } else {
                    if let error = st.lastError, screenTimeRequested {
                        Text(error).font(.caption).foregroundStyle(Palette.warning)
                    }
                    Button("Autorizar Screen Time") {
                        screenTimeRequested = true
                        Task { await st.requestAuthorization() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button(screenTimeRequested ? "Continuar sin Screen Time" : "Ahora no") { withAnimation { page += 1 } }
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private var firstDay: some View {
        pageLayout(icon: "calendar.day.timeline.left", overline: "Tu primera jornada", title: "Empieza con una base",
                   text: "Puedes cargar una jornada tipo de lunes a viernes (planificación 06:30, trabajo profundo 07:00–09:00, mensajes, clientes, descanso, contenido y gestión) y ajustarla después, o empezar en blanco.") {
            VStack(spacing: 10) {
                Button("Cargar jornada tipo") {
                    if routines.isEmpty { ScheduleService.seedExampleRoutine(context: context) }
                    finish()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Empezar en blanco") { finish() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func finish() {
        coordinator.settings.onboardingCompleted = true
        coordinator.didChangeData()
        Task { await coordinator.refresh() }
    }
}
