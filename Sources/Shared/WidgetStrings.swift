import Foundation

/// 小组件文案表：按 App 选择的语言（写进快照的 language 码）取词，跟随 App 而非设备语言。
/// 放在 Shared：App 与 Widget 都编译，单测经 @testable import 也可访问。
enum WidgetStrings {
    private static let en: [String: String] = [
        "pending": "to review",
        "noChanges": "No changes to review",
        "checked": "Checked %@",
        "notChecked": "Not checked yet",
        "unavailable": "Shared data unavailable",
        "unavailableHint": "Open the app to check widget status",
        "latest": "Latest to review",
        "inlineNone": "UpstreamLens: none to review",
        "inlinePending": "UpstreamLens: %@ to review",
        "circular": "to review",
        "configName": "Tech Changes",
        "configDescription": "Shows pending relevant changes and the last check time."
    ]
    private static let zhHans: [String: String] = [
        "pending": "条待查看",
        "noChanges": "暂无需要关注的新变化",
        "checked": "检查于 %@",
        "notChecked": "尚未完成检查",
        "unavailable": "共享数据暂不可用",
        "unavailableHint": "请打开 App 检查组件状态",
        "latest": "最新待查看",
        "inlineNone": "UpstreamLens：暂无待查看",
        "inlinePending": "UpstreamLens：%@ 条待查看",
        "circular": "待查看",
        "configName": "技术变化",
        "configDescription": "显示待查看的相关变化与上次检查时间。"
    ]

    static func table(_ lang: String) -> [String: String] {
        lang == "zh-Hans" ? zhHans : en
    }
}
