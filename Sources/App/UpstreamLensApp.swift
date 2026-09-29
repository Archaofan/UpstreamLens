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
                await model.refreshAllRespectingBudget(minRemaining: 5)
                UpstreamLensApp.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { hasCompletedOnboarding = !$0 })) {
                    OnboardingView { hasCompletedOnboarding = true }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.refreshAll() }
            case .background:
                Self.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }

    /// 后台检查：iOS 调度，间隔约 30 分钟起（系统可能合并或推迟，不作实时承诺）。
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
