import Foundation

/// 特化场景预设：一条点选即可进入确认页并预填全部字段。
/// 所有仓库均已用未认证 API 核实为公开可达（2026-09-29，星数为当日快照）。
struct SourcePreset: Identifiable, Equatable {
    let id: String
    let repository: String
    let kind: SourceKind
    let path: String
    let branch: String
    let displayName: String
    let purpose: String
    let keywords: String
    /// 项目图标加载失败时的 SF Symbol 兜底。
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

    /// 项目图标：仓库所有者的 GitHub 头像（org 的工作室标志），直连 CDN，
    /// 不走 API、不占限流额度；离线或加载失败时回退 symbol。
    var iconURL: URL? { Self.iconURL(for: repository) }

    /// 单一事实来源在 `RepoAvatar`，这里转发以保持既有调用点不变。
    static func iconURL(for repository: String) -> URL? {
        RepoAvatar.url(for: repository)
    }
}

enum PresetLibrary {
    /// 用户指定的三个 AI Agent 项目。
    static let openclaw = SourcePreset(
        id: "openclaw",
        repository: "openclaw/openclaw",
        kind: .release,
        path: "",
        branch: "",
        displayName: "OpenClaw",
        purpose: "开源 AI 助理平台：跟进新版本发布，评估升级对本机部署的影响",
        keywords: "breaking, deprecated, security, release",
        symbol: "cpu",
        note: "星数最高的开源 AI Agent 项目（39 万+）。")

    static let hermes = SourcePreset(
        id: "hermes",
        repository: "NousResearch/hermes-agent",
        kind: .release,
        path: "",
        branch: "",
        displayName: "Hermes Agent",
        purpose: "跟随 Hermes Agent 发版，关注能力变化与破坏性更新",
        keywords: "breaking, deprecated, security, release",
        symbol: "brain.head.profile",
        note: "Nous Research 的成长型 Agent（25 万+ 星）。")

    static let dsh = SourcePreset(
        id: "dsh",
        repository: "deepseek-ai/deepseek-harness",
        kind: .release,
        path: "",
        branch: "",
        displayName: "DeepSeek Harness（DSH）",
        purpose: "DeepSeek 插件生态核心仓库：关注版本发布与插件兼容性变化",
        keywords: "plugin, breaking, deprecated, security",
        symbol: "puzzlepiece.extension",
        note: "「万物皆插件」的 DeepSeek Harness（24 万+ 星）。")

    /// AI 领域星数最高的其余项目（按 2026-09-29 星数取前五，排除上面三个）。
    static let n8n = SourcePreset(
        id: "n8n",
        repository: "n8n-io/n8n",
        kind: .release,
        path: "",
        branch: "",
        displayName: "n8n 工作流自动化",
        purpose: "自托管工作流平台发版很密，升级前核对 breaking change",
        keywords: "breaking, migration, security, release",
        symbol: "flowchart",
        note: "带原生 AI 能力的工作流平台（20 万+ 星）。")

    static let autoGPT = SourcePreset(
        id: "autogpt",
        repository: "Significant-Gravitas/AutoGPT",
        kind: .release,
        path: "",
        branch: "",
        displayName: "AutoGPT",
        purpose: "跟进 AutoGPT 版本发布，评估平台化改动对自建流程的影响",
        keywords: "breaking, migration, security, release",
        symbol: "gauge",
        note: "经典自主 Agent 框架（18 万+ 星）。")

    static let firecrawl = SourcePreset(
        id: "firecrawl",
        repository: "firecrawl/firecrawl",
        kind: .release,
        path: "",
        branch: "",
        displayName: "Firecrawl",
        purpose: "Agent 常用的网页抓取 API：关注接口变更与版本发布",
        keywords: "api, breaking, security, release",
        symbol: "flame",
        note: "面向 Agent 的网页数据接口（18 万+ 星）。")

    static let dify = SourcePreset(
        id: "dify",
        repository: "langgenius/dify",
        kind: .release,
        path: "",
        branch: "",
        displayName: "Dify",
        purpose: "Agentic 工作流与 RAG 平台发版跟踪，升级前核对迁移说明",
        keywords: "breaking, migration, security, release",
        symbol: "square.stack.3d.up",
        note: "可视化 LLM 应用平台（15 万+ 星）。")

    static let openWebUI = SourcePreset(
        id: "open-webui",
        repository: "open-webui/open-webui",
        kind: .release,
        path: "",
        branch: "",
        displayName: "Open WebUI",
        purpose: "本地 LLM 界面发版频繁，关注安全修复与兼容性变化",
        keywords: "breaking, security, release",
        symbol: "globe",
        note: "支持 Ollama 等本地模型界面（15 万+ 星）。")

    static let all: [SourcePreset] = [openclaw, hermes, dsh, n8n, autoGPT, firecrawl, dify, openWebUI]

    /// 保证预设数据始终合法：仓库格式正确、路径来源必须带路径。
    static func validated() -> [SourcePreset] {
        all.filter { preset in
            guard (try? GitHubClient.normalizedRepository(preset.repository)) != nil else { return false }
            if preset.kind == .path { return !preset.path.isEmpty }
            return true
        }
    }
}
