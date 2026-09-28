import Foundation

/// 特化场景预设：一条点选即可进入确认页并预填全部字段。
/// 所有仓库均已用未认证 API 核实为公开可达（2026-09-29）。
struct SourcePreset: Identifiable, Equatable {
    let id: String
    let repository: String
    let kind: SourceKind
    let path: String
    let branch: String
    let displayName: String
    let purpose: String
    let keywords: String
    let symbol: String
    let note: String

    var watchSource: WatchSource {
        var source = WatchSource(kind: kind, repository: repository)
        source.path = path
        source.branch = branch
        source.displayName = displayName
        source.purpose = purpose
        source.keywords = keywords
        return source
    }
}

enum PresetLibrary {
    /// iOS 应用开发场景。
    static let swiftLanguage = SourcePreset(
        id: "swift",
        repository: "swiftlang/swift",
        kind: .release,
        path: "",
        branch: "",
        displayName: "Swift 语言",
        purpose: "跟随 Swift 编译器版本发布，评估工具链升级对项目的影响",
        keywords: "breaking, migration, release",
        symbol: "swift",
        note: "原 apple/swift，已迁移到 swiftlang 组织。")

    static let swiftEvolution = SourcePreset(
        id: "swift-evolution",
        repository: "swiftlang/swift-evolution",
        kind: .path,
        path: "proposals",
        branch: "",
        displayName: "Swift Evolution 提案",
        purpose: "跟踪新提案与提案状态变化，提前了解语言特性走向",
        keywords: "proposal, accepted, rejected",
        symbol: "doc.text.magnifyingglass",
        note: "监控 proposals 目录的提交。")

    static let xcodes = SourcePreset(
        id: "xcodes",
        repository: "XcodesOrg/xcodes",
        kind: .release,
        path: "",
        branch: "",
        displayName: "xcodes 命令行工具",
        purpose: "iOS 开发工具链：Xcode 版本安装管理器的新版本发布",
        keywords: "release, bug, breaking",
        symbol: "hammer",
        note: "iOS 开发常用工具链。")

    /// Skill 开发场景。
    static let superpowers = SourcePreset(
        id: "superpowers",
        repository: "obra/superpowers",
        kind: .path,
        path: "skills",
        branch: "",
        displayName: "Superpowers 技能集",
        purpose: "本机安装的 Agent 技能集，关注技能文件更新与新技能",
        keywords: "skill, workflow",
        symbol: "sparkles",
        note: "技能集合的 skills 目录提交。")

    static let all: [SourcePreset] = [swiftLanguage, swiftEvolution, xcodes, superpowers]

    /// 保证预设数据始终合法：仓库格式正确、路径来源必须带路径。
    static func validated() -> [SourcePreset] {
        all.filter { preset in
            guard (try? GitHubClient.normalizedRepository(preset.repository)) != nil else { return false }
            if preset.kind == .path { return !preset.path.isEmpty }
            return true
        }
    }
}
