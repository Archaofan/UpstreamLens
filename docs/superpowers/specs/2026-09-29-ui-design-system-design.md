# UpstreamLens 界面设计系统与来源管理 — 设计文档

日期：2026-09-29
状态：待评审

## 1. 目标与成功标准

用户提出七项诉求，归纳为一个目标：**把 UpstreamLens 从"能用的工具"提升到"有设计感、愿意日常打开的应用"**，同时修复一个明确的导航缺陷。

成功标准：

1. 新增/已有来源显示**真实仓库头像**（GitHub owner 头像），取不到才回退 SF Symbol。
2. 添加来源的搜索结果与确认页也能看到仓库头像。
3. 来源可**搜索 + 自动分组 + 手动标签**，数量增长后仍可快速定位。
4. 设置里可**清除图标缓存**；清除时不碰任何配置与数据；弹窗让用户选择"仅清缓存 / 同时清已有来源头像 / 保留已有来源头像"。
5. 修复"点击搜索到的来源后没有退出按键"的缺陷。
6. 底部有**多个入口的标签栏**（雷达 / 来源 / 设置），贴近常规 App 形态。
7. 设置里可切换**配色主题**与 **App 图标**（预设方案 + 备用图标）。
8. 用户可**上传图片作为页面背景**，透明度和亮度可调，可一键关闭。
9. 卡片、控件等采用 **iOS 26 液态玻璃半透明**样式，旧系统优雅降级。

### 已确认的决策（用户已选）

| 议题 | 决策 |
|---|---|
| 交付方式 | 分 4 个阶段，每阶段独立 CI 通过并产出可用 IPA |
| 标签栏 | 3 个：雷达 / 来源 / 设置 |
| 来源组织 | 搜索 + 按 owner 自动分组 + 手动标签 |
| 主题与图标 | 预设配色方案 + 备用 App 图标 |
| 玻璃材质 | iOS 26 液态玻璃，`#available` 降级到半透明材质 |
| 背景范围 | 全局统一背景 |

### 非目标（YAGNI）

- 不做用户自选任意强调色的取色器（仅预设方案）。
- 不做每页独立背景。
- 不做云同步、账号体系。
- 不引入任何第三方依赖（保持零依赖）。

## 2. 现状关键事实

- `Sources/App/ContentView.swift`：单一 `NavigationStack` + `List`，无 TabBar；设置以 `.sheet` 呈现；右上角 `+` 与 `ellipsis.circle` 菜单。
- **已存在可复用地基**：
  - `SourcePreset.iconURL(for:)` → `https://github.com/<owner>.png?size=120`，**不走 API、不占限流额度**。
  - `PresetIconCache`（`Sources/App/PresetIcon.swift`）：磁盘缓存在 `Caches/preset-icons`，文件名由 URL 派生，失败回退 nil。
  - `PresetIconView`：30×30 圆角头像视图，`.task(id:)` 异步加载。
- `WatchSource`（`Sources/Shared/Models.swift`）为 `Codable` 且所有字段有默认值 → **新增字段向后兼容**，旧 `data.json` 缺键时解出默认值。
- 部署目标 iOS 17.0；CI 为 Xcode 26.6 / iOS 26 SDK → 液态玻璃 API 可用但需 `#available`。
- 安全不变量（本次不得破坏）：GitHub 令牌仅存 Keychain，不进导出备份、不进诊断。

## 3. 架构：共享设计系统

四个可独立理解、可独立测试的单元，后续所有页面复用。

### 3.1 `AppTheme`（`Sources/App/Theme/AppTheme.swift`）

- `enum AppTheme: String, CaseIterable, Identifiable`，raw value 即持久化值（**一旦发布不可更改**）：
  - `teal`（默认，现有品牌青）、`indigo`、`violet`、`emerald`、`amber`、`rose`
- 每个 case 提供 `accent: Color`（浅色/深色各一，用 `Color(light:dark:)` 辅助）与 `displayName: LocalizedStringKey`。
- `LanguagePreferences` 同款模式：`enum ThemePreferences` 提供 `resolve(_ selection:systemColorScheme:) -> Color`，把"未设置/非法值 → 默认 teal"集中一处。
- 持久化：`@AppStorage("appTheme")`（仅本机，**不进导出备份**）。
- 注入：`ViewModifier`（`ThemeInjector`）在 App 根视图 `.tint(resolved)`，并写入 `AppleLanguages` 无关、仅主题。

### 3.2 `AppBackground`（`Sources/App/Theme/AppBackground.swift`）

- 数据：`@AppStorage("bgEnabled")`（默认 false）、`bgOpacity`（Double，0.1–1.0，默认 0.35）、`bgBrightness`（Double，-0.2–0.2，默认 0.0）。
- 图片：用户从相册选取 → 缩放为最长边 ≤ 2048 的 JPEG → 写入 **App Group 容器** `background/current.jpg`（与 Widget 快照同容器，天然不进 `data.json` 导出）。
  - 选 App Group 容器而非 `Caches`：避免被系统清理导致背景莫名丢失；用户主动"移除背景"才删除。
- 读取：`BackgroundImageStore.load()` 返回 `UIImage?`；带内存缓存避免滚动时反复解码。
- 应用：`ViewModifier`（`appBackground()`）叠在各 Tab 根视图最底层：自定义图（可调 opacity/brightness）或 `Color(uiColor: .systemGroupedBackground)`。
- 亮度用 `.brightness()` 修饰，透明度用 `.opacity()`；两者都通过 `Color` 之外的图层叠加，**不影响内容可读性对比度下限**（opacity 下限 0.1）。

### 3.3 `GlassSurface`（`Sources/App/Theme/GlassSurface.swift`）

- `struct GlassCard<Content: View>`：圆角容器，`#available(iOS 26, *)` 用 `GlassEffectContainer` + `.glassEffect(.regular.interpolant(...)`；否则 `.background(.ultraThinMaterial, in: RoundedRectangle(...))`。
- `enum GlassStyle { case regular, prominent, thin }` 映射到两种实现的最近似参数。
- 提供 `View.glassCard(_ style:)` 便捷修饰符，用于替代现有 `Color.accentColor.opacity(0.1)` 方块、分段背景、底部标签栏底色等。
- **可读性保障**：玻璃仅作容器背景，文字仍用语义色（`.primary`/`.secondary`），不因材质变化失真。

### 3.4 `RepoAvatarImage`（`Sources/App/Avatar/RepoAvatarImage.swift`）

- 泛化现有预设图标能力：
  - `enum RepoAvatar { static func url(for repository: String) -> URL? }` —— 逻辑即现有 `SourcePreset.iconURL(for:)`，改为对任意 `owner/repo` 生效；`SourcePreset.iconURL` 改为转发到它（保持单一事实来源）。
  - `enum AvatarCache` —— 由 `PresetIconCache` 泛化：目录参数化（默认 `Caches/avatars`，兼容读取旧 `preset-icons`），新增 `totalBytes()`、`clear(scope:)`。
- `struct RepoAvatarImage: View`：`let repository: String; var symbol: String; var size: CGFloat = 30`；`.task(id: repository)` 异步加载，失败/无 URL 回退 SF Symbol（按 `SourceKind` 选 symbol）。带 `@State` 内存缓存 + `AvatarCache` 磁盘缓存。
- `AvatarCache.clear(keepExistingSources: Bool, currentOwners: Set<String>)`：弹窗两个选项的真实语义——
  - `keepExistingSources == false` → 删除**全部**头像缓存文件。
  - `keepExistingSources == true` → 只删除**当前没有对应来源**的头像文件（按 owner 派生文件名反查），已有来源的头像保留、不重新下载。
  - 两个选项都**绝不**触碰 `data.json`、导出备份、主题/背景/图标偏好。

## 4. 分阶段实施计划

每阶段结束：`python build/check_braces.py` + JSON 校验 → 提交 → 推送（`push_via_api.py`，BASE=`main`）→ 触发 CI → 确认全绿 → 才进入下一阶段。

### Phase 1 — 缺陷修复 + 设计系统地基

**修复导航 bug**：`AddSourceView` 第 42 行 `.sheet` 中的 `RepoConfirmView` 包上 `NavigationStack`，使其 `.toolbar` 的 Cancel 真正渲染。（`ContentView.pendingClipboardAdd` 已是正确写法，可对照。）

新增：`AppTheme` + `ThemePreferences` + `ThemeInjector`；`AppBackground` + `BackgroundImageStore` + `appBackground()`；`GlassCard` + `glassCard()`。
Catalog 增补主题/背景/玻璃相关键（英文键 + 中文）。
测试：`ThemePreferencesTests`（resolve/normalize/默认值/非法 raw value）、`BackgroundPreferencesTests`（opacity/brightness 范围钳制 round-trip）。
此阶段不改变现有视觉默认值（主题默认 teal = 现品牌色，背景默认关闭），保证"修好 bug + 地基就位"而不引入视觉回归风险。

### Phase 2 — 仓库头像 + 缓存管理

`RepoAvatar` / `AvatarCache` / `RepoAvatarImage`；`SourcePreset.iconURL` 转发。
应用到：`SourceRowView`（替换现有按 kind 的 SF Symbol 方块）、`RepoConfirmView`（Repository 区头部）、`AddSourceView.resultRow`（搜索结果行）。
设置 → 数据与备份 增「图标缓存」分区：显示缓存大小 + 「清除图标缓存」按钮 + 确认弹窗（含"同时清除已有来源头像"开关）。
测试：`RepoAvatarTests`（URL 派生、非法 repository 返回 nil、旧 preset 目录兼容）、`AvatarCacheTests`（写入/读取/统计/清除范围，用临时目录）。

### Phase 3 — 底部标签栏 + 来源管理

- `UpstreamLensApp` 根视图改 `TabView`：雷达（现 `ContentView` 主体）/ 来源（新 `SourcesTabView`）/ 设置（现 `SettingsView`，从 sheet 改为 Tab）。
- 雷达 Tab 保留现有全部能力（待处理、概览、剪贴板横幅、下拉刷新、深链）。
- 来源 Tab：搜索框（按 displayName / repository / purpose / keywords 实时过滤）+ 按 owner 自动分组 + 手动标签分组；行用 `RepoAvatarImage`；行尾显示标签。
- `WatchSource` 增 `var tags: [String] = []`（Codable 默认值 → 旧数据兼容）。
- `SourceEditorView` 增标签编辑（输入逗号分隔或 chips）。
- 测试：`WatchSourceDecodeTests`（缺 `tags` 键解出 `[]`；含 tags round-trip）、`SourceGroupingTests`（过滤/分组纯函数）。

### Phase 4 — 主题选择 + App 图标 + 视觉打磨

- 设置 → 通用 增「外观」分区：主题选择器（6 预设，实时预览色块）+ App 图标选择器。
- 备用 App 图标：`Assets.xcassets/AppIcon.appiconset` 增加 3 套 alternate icon 资源 + `project.yml` 注入 `CFBundleIcons` 备用图标声明；用 `UIApplication.shared.setAlternateIconName` 切换，持久化 `@AppStorage("appIcon")`，启动时校正。
- 全站套用 `GlassCard` 与 `appBackground()`：来源行、概览卡片、设置各子页、底部标签栏。
- 视觉打磨：统一圆角/间距/字阶 tier，去掉现有零散的 `Color.accentColor.opacity(0.1)` 手工方块。
- 测试：`AppIconPreferencesTests`（持久化值与合法名集合校验）。

## 5. 关键流程

### 5.1 头像加载与回退

```
RepoAvatarImage(repository: "n8n-io/n8n", symbol: "flowchart")
  → RepoAvatar.url(for:) → https://github.com/n8n-io.png?size=120
  → AvatarCache.image(url:)
      磁盘命中 → 返回
      否则 URLSession 拉取（200 且可解码为 UIImage）→ 写盘 → 返回
      失败/超时 → nil
  → nil 时渲染 Image(systemName: symbol)
```

失败不阻塞 UI、不弹错误；列表始终整齐。

### 5.2 清除图标缓存（弹窗）

设置 → 数据与备份 → 图标缓存 → 「清除图标缓存」弹出 `confirmationDialog`，明确告知：只会删除本地缓存的仓库头像图片，**不会**删除任何来源、配置、变化记录或备份。两个选项：

- **「清除全部（含已有来源的头像）」** → `clear(keepExistingSources: false, …)`，删除全部头像文件；已有来源下次查看时重新下载。
- **「仅清除未使用的，保留已有来源的头像」** → `clear(keepExistingSources: true, currentOwners:)`，只删当前无对应来源的头像文件。

另有「取消」，不做任何删除。操作后刷新显示的缓存大小。

## 6. 数据与兼容性

- `WatchSource.tags` 新增字段：旧 `data.json` 无该键 → 解出 `[]`；导出备份带上该键；导入旧备份同样安全。
- 主题/背景/图标偏好均为 `@AppStorage`，**不进入** `exportData()` 备份、不进诊断文本。
- 背景图存 App Group 容器 `background/current.jpg`，不进 `data.json`；导出备份大小不受影响。
- 头像缓存在 `Caches`，系统可自行清理，属可再生产物。

## 7. 错误处理

| 场景 | 行为 |
|---|---|
| 头像 URL 派生失败（repository 非法） | 回退 SF Symbol，不请求 |
| 头像下载失败/超时/非 200 | 回退 SF Symbol，不写盘，不提示 |
| 背景图片解码失败 | 保留原背景，提示"图片无法使用" |
| 背景图写入容器失败 | 提示失败，不改变当前背景 |
| `setAlternateIconName` 失败 | 回退主图标，提示失败 |
| 清除缓存时文件被占用 | 尽力删除，报告实际释放大小 |

## 8. 测试策略

- 纯逻辑单测：主题解析、背景参数钳制、头像 URL 派生、缓存范围、tags 解码兼容、来源过滤/分组。
- 文件系统测试用临时目录 + `FileManager`，不触碰真实容器。
- CI 只保证编译 + 单测；液态玻璃视觉效果、标签栏切换、背景叠照需真机目视确认。

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| TabBar 重构影响深链/通知路由 | Phase 3 保持 `ContentView` 内部导航不变，只在外层包 TabView；深链与 `openFindingFromNotification` 逻辑原样保留 |
| 液态玻璃 API 在 iOS 17 不可用 | `#available(iOS 26, *)` + `.ultraThinMaterial` 降级；CI 用 iOS 26 SDK 编译两者都过 |
| 备用图标资源增加包体 | 控制在 3 套、每套复用同一构图仅换色，单套 < 60 KB |
| 头像并发拉取触发限流 | `github.com/<owner>.png` 不走 API；CDN 直连，且磁盘缓存命中后不再请求 |
| 背景图影响可读性 | opacity 下限 0.1 + 内容用语义色 + 玻璃卡片提供对比基底 |

## 10. 交付检查单

每阶段需满足：`check_braces.py` 全平衡、xcstrings JSON 合法且新增键都有中文翻译、CI 全绿（编译 + 单测）、无新增第三方依赖、安全不变量未被破坏（令牌仍仅 Keychain）。
