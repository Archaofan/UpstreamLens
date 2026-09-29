import SwiftUI
import BackgroundTasks
import UserNotifications

extension Notification.Name {
    static let openFindingFromNotification = Notification.Name("openFindingFromNotification")
}

/// 通知点击路由：把 userInfo 里的 findingID 转成 App 内导航事件。
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["findingID"] as? String,
              let id = UUID(uuidString: text) else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .openFindingFromNotification, object: id)
        }
    }

    /// 前台收到通知也展示横幅（不抢焦点，仅显示）。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

@main struct UpstreamLensApp: App {
    static let backgroundRefreshID = "com.upstreamlens.ios.refresh"
    @StateObject private var model = AppModel()
    @StateObject private var notificationRouter = NotificationRouter()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        NotificationScheduler.registerCategory()
        // 直接向 BGTaskScheduler 注册后台检查；SwiftUI 的 .backgroundTask 修饰符在
        // 当前 SDK 上类型推断不稳定，系统级注册行为完全一致。
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundRefreshID, using: nil) { [weak model] task in
            let work = Task { @MainActor [weak model] in
                guard let model else {
                    task.setTaskCompleted(success: false)
                    return
                }
                if RefreshPolicy.backgroundEnabled() {
                    await model.refreshAllRespectingBudget(minRemaining: 5)
                    UpstreamLensApp.scheduleBackgroundRefresh()
                }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            // 底部三入口：雷达 / 来源 / 设置。各 Tab 自持 NavigationStack，
            // 原有 ContentView 内部导航与深链逻辑保持不变。
            TabView {
                ContentView(model: model)
                    .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
                SourcesTabView(model: model)
                    .tabItem { Label("Sources", systemImage: "square.stack.3d.up") }
                SettingsView(model: model)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .injectLocale()
            .injectTheme()
            .appBackground()
            // 冷启动兜底：万一上次切换失败，重新应用已保存的图标选择。
            .task {
                if let stored = AppIconPreferences.stored() as AppIconOption?, stored != .primary {
                    _ = try? await AppIconSwitcher.apply(stored)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { hasCompletedOnboarding = !$0 })) {
                OnboardingView { hasCompletedOnboarding = true }
                    .injectLocale()
                    .injectTheme()
                    .appBackground()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if RefreshPolicy.checkOnOpen() {
                    Task { await model.refreshAll() }
                }
            case .background:
                if RefreshPolicy.backgroundEnabled() {
                    Self.scheduleBackgroundRefresh()
                }
            default:
                break
            }
        }
    }

    /// 后台检查：iOS 调度，间隔由设置里的档位决定（系统可能合并或推迟，不作实时承诺）。
    static func scheduleBackgroundRefresh() {
        guard RefreshPolicy.backgroundEnabled() else { return }
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(RefreshPolicy.backgroundMinutes() * 60))
        try? BGTaskScheduler.shared.submit(request)
    }
}
