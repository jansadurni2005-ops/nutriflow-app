import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

@main
struct FocusOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = AppCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .modelContainer(coordinator.container)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            coordinator.handleScenePhase(phase)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppCoordinator.refreshTaskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in AppCoordinator.shared.handleBackgroundRefresh(refresh) }
        }
        return true
    }

    // Mostrar notificaciones también con la app abierta.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        let userInfo = content.userInfo
        let title = content.title
        let body = content.body
        Task { @MainActor in
            AppCoordinator.shared.handleNotificationResponse(actionIdentifier: action, userInfo: userInfo,
                                                             title: title, body: body)
            completionHandler()
        }
    }
}
