# UpstreamLens 0.4.0 设计：应用内本地化 · 设置子页面 · 2×2 小组件 · 可配置刷新 · 双语 README

- 日期：2026-09-29
- 状态：已定稿，待实现
- 目标版本：0.4.0（CURRENT_PROJECT_VERSION 3）
- 分支：`feature/i18n-settings-widget-refresh`

## 1. 背景与目标

在已有「GitHub 登录 + 小组件美化」基础上，下一版本要做五件事：

- **A. 应用内语言**：安装后默认英文；引导页第一页即可选语言；设置里可随时切换。提供 英文 / 简体中文 / 跟随系统 三选，默认英文（即使设备是中文）。
- **B. 设置子页面**：把现在挤在一个 Form 里的设置拆成多个子页面。
- **C. 小组件 2×2**：小尺寸（systemSmall）标题被截成省略号，显示效果差；按业界做法优化。
- **D. 检查/后台刷新策略**：在设置里可配置「是否打开 App 时检查」「后台刷新开关与间隔」。
- **E. README 中英双语**：仓库主页默认展示英文版，可点击进入中文版。

## 2. 已锁定的用户决策

| 议题 | 决策 |
|---|---|
| 语言集合 | 英文（默认）+ 简体中文 + 跟随系统 |
| 小组件语言 | 跟随 App 选择（经共享快照带语言码），不跟随设备系统 |
| 2×2 方案 | 计数为主 + ≤2 行短标题 + 检查时间；不新增快照数据 |
| 刷新策略 | 开关 + 间隔档位；默认=打开App检查 + 约30分钟后台 |
| README | `README.md`=英文（默认），`README.zh-CN.md`=中文，顶部互链 |

## 3. 范围与非目标

**范围**：App 与 Widget 全部用户可见字符串本地化；设置结构重组；刷新策略偏好与接线；小尺寸小组件重排；双语 README；相应测试；版本号升级。

**非目标**：不做中英以外的语言；不改动 ChangeDetector / RelevanceEngine / GitHubClient 核心逻辑（既有登录除外）；不做 OAuth/Device Flow；不把新偏好写入导出备份。

## 4. 设计

### A. 应用内本地化

**机制**：String Catalog + 运行时 locale 覆盖 + 小组件独立字符串表。

1. **String Catalog**：新增 `Sources/App/Localizable.xcstrings`，`sourceLanguage = "en"`。键=英文字面量，`zh-Hans` 提供中文翻译。缺失翻译回退英文（不崩溃）。在 `project.yml` 的 App target `sources` 中加入该文件；`CFBundleDevelopmentRegion` 设为 `en`。
2. **语言模型**：
   ```swift
   enum AppLanguage: String, CaseIterable, Identifiable {
       case english = "en", chinese = "zh-Hans", system = "system"
   }
   ```
   纯函数解析（可单测）：
   ```swift
   enum LanguagePreferences {
       /// 返回 (注入 SwiftUI 的 Locale?, 供快照/字符串表使用的语言码)
       static func resolve(_ selection: AppLanguage,
                           systemPreferred: [String] = Locale.preferredLanguages)
           -> (locale: Locale?, code: String)
   }
   ```
   - `.english` → `(Locale(identifier:"en"), "en")`
   - `.chinese` → `(Locale(identifier:"zh-Hans"), "zh-Hans")`
   - `.system` → `(nil, 取 systemPreferred 里首个受支持码，回退 "en")`
3. **选择存储**：`@AppStorage("appLanguage") var appLanguage: AppLanguage = .english`（默认英文）。放在根视图。
4. **应用与注入**：根视图（`UpstreamLensApp` 的 WindowGroup 内容）：
   - `.environment(\.locale, resolved.locale ?? .current)` —— SwiftUI `Text` 即时切换、无需重启。
   - `.onAppear` / `.onChange(of: appLanguage)` 里设置 `UserDefaults.standard.set([code], forKey: "AppleLanguages")`，使 `Bundle`/`String(localized:)` 等非 Text 路径一致。
5. **引导页第一页**：在 `OnboardingView` 第 0 页顶部加语言选择器（分段或菜单，绑定 `appLanguage`），选中即刻生效。
6. **设置**：通用子页加「语言 / Language」行 → 选择器（英文/中文/跟随系统）。
7. **改字符串**：把 App 各视图里的中文字面量替换为英文键。插值串用带占位符的本地化键（如 `Text("\(n) to review")` ↔ 中文 `"\(n) 条待查看"`）。涉及文件：ContentView、AddSourceView、RepoConfirmView、VersionPickerField、DiffView、FindingQueue、SettingsView(+子页)、OnboardingView、SourceListImport(提示词文案)、Diagnostics、UpstreamLensApp 等。

### B. 设置子页面

`SettingsView` 变成根列表，内部已是 `NavigationStack`，用 `NavigationLink` 推到子页。新建 `Sources/App/Settings/`：

- `GeneralSettingsView.swift`：语言、GitHub 登录（含限额显示）、令牌帮助。
- `MonitoringSettingsView.swift`：打开App检查开关、后台刷新开关+间隔、通知（原 notificationSection 迁入）。
- `DataSettingsView.swift`：导入/导出、AI 来源清单导入、清理已处理记录。
- `AboutSettingsView.swift`：帮助、诊断、关于。

`model`（`@ObservedObject`）向下传递；各子页自持 `@AppStorage` 与本地 `@State`；导入/导出/诊断的 sheet 放在各自子页内。`TokenHelpSheet` 随通用页。

### C. 小组件 2×2（systemSmall）

`smallLayout` 重排为「一览式」：

```
[紧凑 header: UpstreamLens]
[大号计数 + 待查看]
[相关性圆点 + ≤2 行标题（字号略小、尾部干净截断）]
[检查于 …（caption2 次级色）]
```

- 标题 `lineLimit(2)`，字体 `.callout`/`.subheadline`，去掉原先 3 行拥挤块；收紧间距，确保 2×2 放得下。
- Medium（两栏）与锁屏 accessory 保持不变。
- 不新增快照数据。

### D. 检查/后台刷新策略

**偏好（`@AppStorage`，均设备本地、不入备份）**：
- `checkOnOpen: Bool = true`
- `backgroundRefreshEnabled: Bool = true`
- `backgroundRefreshMinutes: Int = 30`（档位 15/30/60/180）

**纯逻辑（可单测，隔离 BGTaskScheduler）**：
```swift
struct RefreshPolicy {
    var checkOnOpen: Bool
    var backgroundEnabled: Bool
    var intervalMinutes: Int
    static let intervalPresets = [15, 30, 60, 180]
    var backgroundInterval: TimeInterval { TimeInterval(intervalMinutes) * 60 }
}
```

**接线（`UpstreamLensApp`）**：
- `.active`：`if policy.checkOnOpen { await model.refreshAll() }`
- `.background`：`if policy.backgroundEnabled { schedule(interval:) } else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundRefreshID) }`
- `scheduleBackgroundRefresh(minutes:)`：`request.earliestBeginDate = .now + minutes*60`
- 后台任务回调仍用 `refreshAllRespectingBudget(minRemaining: 5)`，完成后按当前间隔重新排程。

**设置 UI**（监控子页）：两个开关 + 间隔选择器（后台关闭时间隔禁用）；文案注明 iOS 对后台实际时机不完全可控，只设最早开始时间。

### E. 双语 README

- `README.md` = 英文版（仓库主页默认展示）。顶部语言条：`**English** | [简体中文](README.zh-CN.md)`。
- `README.zh-CN.md` = 中文版。顶部：`[English](README.md) | **简体中文**`。
- 两份结构对齐，都更新到 0.4.0 新特性（可选登录、设置子页面、可配置刷新、应用内语言、2×2 优化）。安装方式（TrollStore/Sideloadly）与隐私边界两版都写清。

## 5. 数据模型与偏好变更

- `WidgetSnapshot` 增加 `var language: String?`（可选；nil 视为 "en"，兼容旧快照解码）。`WidgetSnapshotWriter.write` 写入 `LanguagePreferences.resolve(appLanguage).code`。`.empty` 的 `language = "en"`。
- 新增 `@AppStorage` 键：`appLanguage`、`checkOnOpen`、`backgroundRefreshEnabled`、`backgroundRefreshMinutes`（均设备本地，不进入导出备份）。
- 小组件字符串表：`enum WidgetStrings { static func text(_ key: String, lang: String) -> String }`，内含 en / zh-Hans 两张表，覆盖：UpstreamLens、待查看计数、最新待查看、暂无需要关注的新变化、检查于/尚未完成检查、共享数据暂不可用、请打开App检查组件状态、配置显示名与描述等约 10 条。

## 6. 安全不变量（不变）

- GitHub 令牌仍仅存 Keychain，只作 `Authorization: Bearer` 发往 api.github.com，不入 data.json/导出备份/第三方；诊断只显示登录与否。
- 新增偏好为设备本地 `@AppStorage`，不写入导出备份，不随备份迁移。
- 未登录/公开路径行为不变。

## 7. 测试计划

- `LanguagePreferences.resolve`：三档各自的 (locale, code)；system 回退。
- `WidgetStrings`：en/zh-Hans 各键返回值正确；未知语言回退 en。
- `WidgetSnapshot`：带 `language`  round-trip；旧 JSON（无 language）解出 nil→按 en 处理。
- `RefreshPolicy`：`backgroundInterval` 档位映射；开关组合。
- `AppModel`：既有 `isAuthenticated`/令牌测试不回归。
- 既有全部测试保持绿。

## 8. 实施顺序（每步一个 CI 门）

1. 本地化基础设施：AppLanguage、LanguagePreferences、String Catalog、根视图 locale 注入 + AppleLanguages；引导页第一页语言选择器；设置语言行。（先打通机制）
2. 全面中文化字符串→英文键 + zh-Hans 翻译（App 各视图）。
3. 设置拆子页面（B）。
4. 刷新策略（D）：RefreshPolicy + UpstreamLensApp 接线 + 监控子页 UI。
5. 小组件（C + 语言）：smallLayout 重排 + WidgetStrings + WidgetSnapshot.language + Writer 写入。
6. README 双语（E）；版本号 0.4.0/build 3；README 同步。
7. 全量测试 + CI 出 IPA + 核对 SHA-256 + 交付。

## 9. 风险与缓解

- **本地化量大**：缺失翻译回退英文（不崩），可迭代补齐；CI 编译门捕获语法。
- **运行时 locale 覆盖**：SwiftUI Text 走 `.environment(\.locale)` 即时生效；`String(localized:)` 等靠 AppleLanguages；两者并设保持一致。核心逻辑抽成纯函数便于单测。
- **小组件语言**：用快照带语言码 +  widget 内建表，避免依赖设备locale，保证与 App 一致。
- **后台时机**：iOS 不完全可控，仅在 UI 明示只设最早开始时间。
- **网络**：github.com git 出口受限时继续用 Git Data API 推送 + workflow_dispatch。

## 10. 验收标准

- 全新安装默认英文；引导页第一页可切中文并即时生效；设置可切回/切系统。
- 设置分为四个子页面，功能不丢失。
- 2×2 小组件标题不再出现生硬省略号；Medium/锁屏不变。
- 可在设置里关闭「打开App检查」「后台刷新」并调整间隔档位。
- README.md 为英文默认、可点入中文版。
- 单测全绿；CI 产出 IPA 且 SHA-256 可核对。
