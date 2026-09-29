import Foundation

/// 检查 / 后台刷新策略：本机偏好（@AppStorage / UserDefaults 持久化，不进导出备份）。
/// 默认：打开时检查 = 开，后台刷新 = 开，后台间隔 = 30 分钟。
enum RefreshPolicy {
    static let checkOnOpenKey = "refreshCheckOnOpen"
    static let backgroundEnabledKey = "refreshBackgroundEnabled"
    static let backgroundMinutesKey = "refreshBackgroundMinutes"

    /// 后台刷新间隔档位（分钟）。iOS 实际调度约 30 分钟起，可能合并或推迟。
    static let intervalOptions = [15, 30, 60, 180]
    static let defaultMinutes = 30

    /// 打开/前台时是否自动检查。未设置默认开。
    static func checkOnOpen(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: checkOnOpenKey) == nil ? true : defaults.bool(forKey: checkOnOpenKey)
    }

    /// 是否允许后台刷新。未设置默认开。
    static func backgroundEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: backgroundEnabledKey) == nil ? true : defaults.bool(forKey: backgroundEnabledKey)
    }

    /// 后台刷新间隔（分钟）；非法值回退默认 30。
    static func backgroundMinutes(_ defaults: UserDefaults = .standard) -> Int {
        let v = defaults.integer(forKey: backgroundMinutesKey)
        return intervalOptions.contains(v) ? v : defaultMinutes
    }
}
