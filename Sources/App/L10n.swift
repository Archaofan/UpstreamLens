import Foundation

/// 带命名占位符的本地化文案。
///
/// 刻意**不用** `String(format:)`：格式符（%@/%lld）与参数类型不匹配是
/// 运行时问题，编译期查不出来，翻译时也极易错配。命名占位符是纯文本替换，
/// 不可能因为类型或顺序出错，而且译文中占位符可以自由调整语序。
///
/// 用法：
/// ```
/// L10n.format("Upstream is at {upstream}, you recorded {installed}.",
///             ["upstream": "0.21.5", "installed": "0.20.6"])
/// ```
enum L10n {
    /// 填充命名占位符。缺失的占位符保持原样，便于测试发现漏填。
    static func fill(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { result, pair in
            result.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    /// 取当前语言模板并填充。
    static func format(_ key: String, _ values: [String: String],
                       defaults: UserDefaults = .standard) -> String {
        fill(AppLocalization.string(key, defaults: defaults), values)
    }
}
