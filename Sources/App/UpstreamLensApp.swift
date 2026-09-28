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

    init() {
        NotificationScheduler.registerCategory()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.refreshAll() }
            case .background:
                scheduleBackgroundRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appTask(Self.backgroundRefreshID)) { task in
            await model.refreshAllRespectingBudget(minRemaining: 5)
            scheduleBackgroundRefresh()
            task.setTaskCompleted(success: true)
        }
    }

    /// 后台检查：iOS 调度，间隔约 30 分钟起（系统可能合并或推迟，不作实时承诺）。
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
