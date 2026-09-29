import Foundation
import SwiftUI

extension SourceCategory {
    /// 显示名：用户改过名就用用户的，否则用内置 slug 的本地化名。
    var displayName: String {
        if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customName
        }
        return AppLocalization.string(CategoryCatalog.nameKey(id))
    }
}

/// "来源"页的分组依据。默认按类别（真机反馈：按 owner 分组时几乎一组一个仓库，
/// 用户真正想按"AI"这类主题归类），也保留按 owner 的选项。
enum SourceGroupKind: String, CaseIterable, Identifiable {
    case category
    case owner

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .category: return "Category"
        case .owner: return "Owner"
        }
    }
}

enum SourceGroupPreferences {
    static let storageKey = "sourceGroupKind"
    static let fallback = SourceGroupKind.category

    static func resolve(_ raw: String?) -> SourceGroupKind {
        guard let raw, let kind = SourceGroupKind(rawValue: raw) else { return fallback }
        return kind
    }
}
