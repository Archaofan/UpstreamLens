import Foundation
import UserNotifications

/// 一条待投递的本地通知。判断逻辑是纯函数（NotificationPlanner），投递走可注入闭包。
struct PendingNotification: Equatable {
    let identifier: String
    let title: String
    let body: String
    let threadIdentifier: String
    let isImportant: Bool
    let findingID: UUID
}

enum NotificationPlanner {
    static let categoryIdentifier = "SOURCE_UPDATE"

    /// 从本次刷新新增的记录里挑出值得通知的。原则：
    /// - 总开关关闭或来源关闭 → 不通知
    /// - 只通知“未读且相关”的记录；routine 永不打扰
    /// - 每个来源一次最多 5 条，超出折叠为一条摘要（防轰炸，参考 GitHub Notifications 分组）
    static func plan(additions: [Finding], source: WatchSource, masterEnabled: Bool) -> [PendingNotification] {
        guard masterEnabled, source.notifyEnabled != false else { return [] }
        let worthy = additions
            .filter { $0.isUnreadRelevant }
            .sorted { ($0.relevance == .important ? 0 : 1) < ($1.relevance == .important ? 0 : 1) }
        guard !worthy.isEmpty else { return [] }
        let capped = worthy.prefix(5)
        var result = capped.map { finding in
            PendingNotification(
                identifier: "finding-\(finding.id.uuidString)",
                title: source.title,
                body: finding.title,
                threadIdentifier: source.title,
                isImportant: finding.relevance == .important,
                findingID: finding.id)
        }
        if worthy.count > capped.count {
            let rest = worthy.dropFirst(capped.count)
            result.append(PendingNotification(
                identifier: "source-\(source.id.uuidString)-overflow",
                title: source.title,
                body: "还有 \(rest.count) 条相关变化，打开 App 查看。",
                threadIdentifier: source.title,
                isImportant: false,
                findingID: source.id))
        }
        return result
    }
}

/// 投递与授权都收敛在可注入的闭包里，单测不触碰真实系统。
struct NotificationScheduler {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    static func registerCategory() {
        let category = UNNotificationCategory(
            identifier: NotificationPlanner.categoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction])
        center().setNotificationCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 先申请授权；拒绝时返回 false（调用方在设置页解释好处后允许重试）。
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .badge, .sound, .provisional])) ?? false
    }

    func deliver(_ notifications: [PendingNotification]) async {
        guard await authorizationStatus() != .denied else { return }
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.threadIdentifier = notification.threadIdentifier
            content.categoryIdentifier = NotificationPlanner.categoryIdentifier
            content.interruptionLevel = notification.isImportant ? .active : .passive
            content.sound = notification.isImportant ? .default : nil
            content.userInfo = ["findingID": notification.findingID.uuidString]
            let request = UNNotificationRequest(identifier: notification.identifier,
                                                content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
