import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Namespace private var tabNamespace
    @Environment(\.scenePhase) private var scenePhase
    @State private var todayKey = Calendar.current.startOfDay(for: Date())

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack(alignment: .bottom) {
            TabView(selection: $coordinator.selectedTab) {
                HomeView().tag(AppTab.home).toolbar(.hidden, for: .tabBar)
                ScheduleView().tag(AppTab.schedule).toolbar(.hidden, for: .tabBar)
                FocusHubView().id(todayKey).tag(AppTab.focus).toolbar(.hidden, for: .tabBar)
                AnalyticsView().tag(AppTab.analytics).toolbar(.hidden, for: .tabBar)
                SettingsView().tag(AppTab.settings).toolbar(.hidden, for: .tabBar)
            }

            VStack(spacing: 10) {
                if coordinator.activeSession != nil && !coordinator.showDeepWork {
                    ActiveSessionBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                tabBar
            }
        }
        .screenBackground()
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: coordinator.activeSession?.id)
        .overlay(alignment: .top) { toastOverlay }
        .fullScreenCover(isPresented: $coordinator.showDeepWork) {
            DeepWorkView().environment(coordinator)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !coordinator.settings.onboardingCompleted },
            set: { if !$0 { coordinator.settings.onboardingCompleted = true } }
        )) {
            OnboardingView().environment(coordinator)
        }
        .sheet(item: $coordinator.sessionSummary) { summary in
            SessionSummarySheet(summary: summary)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
        }
        .sheet(item: $coordinator.pendingRecovery) { session in
            RecoverySheet(session: session)
                .presentationDetents([.medium])
                .presentationBackground(Palette.background)
                .interactiveDismissDisabled()
        }
        .sheet(item: Binding(
            get: { coordinator.reviewDay.map(IdentifiableDate.init) },
            set: { coordinator.reviewDay = $0?.date }
        )) { item in
            DailyReviewView(day: item.date)
                .presentationBackground(Palette.background)
        }
        .onAppear { coordinator.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { todayKey = Calendar.current.startOfDay(for: Date()) }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if coordinator.selectedTab != tab { Haptics.selection() }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { coordinator.selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if coordinator.selectedTab == tab {
                                Capsule()
                                    .fill(Palette.accentSoft)
                                    .frame(width: 52, height: 32)
                                    .matchedGeometryEffect(id: "tab", in: tabNamespace)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(coordinator.selectedTab == tab ? Palette.accent : Palette.textTertiary)
                        }
                        .frame(height: 32)
                        Text(tab.title.uppercased())
                            .font(.system(size: 9, weight: .bold).width(.expanded))
                            .foregroundStyle(coordinator.selectedTab == tab ? Palette.textPrimary : Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            Palette.background.opacity(0.92)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(Palette.stroke).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = coordinator.toast {
            ToastView(toast: toast)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(3.2))
                    withAnimation { if coordinator.toast?.id == toast.id { coordinator.toast = nil } }
                }
                .onTapGesture { withAnimation { coordinator.toast = nil } }
        }
    }
}

struct IdentifiableDate: Identifiable {
    var date: Date
    var id: Date { date }
}

/// Barra flotante con la sesión en curso (fuera de la pantalla DEEP WORK).
struct ActiveSessionBar: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        if let session = coordinator.activeSession {
            Button {
                coordinator.showDeepWork = true
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 12) {
                        Circle().fill(session.isPaused || session.isOnBreak ? Palette.warning : Palette.accent)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                            Text(session.isOnBreak ? "Descanso" : session.isPaused ? "En pausa" : session.kind.label)
                                .font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        let remaining = session.remaining(at: context.date)
                        Text(remaining >= 0 ? TimeFormat.compactClock(remaining) : "+" + TimeFormat.compactClock(-remaining))
                            .font(.metric(20))
                            .foregroundStyle(remaining >= 0 ? Palette.textPrimary : Palette.accent)
                        Image(systemName: "chevron.up").font(.caption.weight(.bold)).foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.cardElevated))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.accent.opacity(0.35)))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }
}
