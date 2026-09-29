# Design: GitHub 登录（PAT，双模式）+ 小组件原生精致化

日期：2026-09-29 · 分支：`feature/github-auth-widget-polish`
状态：已与用户确认方案（分层注入 + Medium 保持两栏 (i)）。

## 目标与非目标

**目标**
- 支持登录 GitHub（Personal Access Token），把限额从公开 60 次/小时 提到约 5000 次/小时。
- **不登录也能用**：未登录路径行为与现状完全一致（无 Authorization 头）。
- 登录附带解锁**私有仓库**监控（README 中“尚未实现”的限制）。
- 小组件按 Apple 原生风格精致化（更清晰层次、等宽数字、相关性着色）。

**非目标（YAGNI）**
- 不做 OAuth / Device Flow（用户选 PAT）。
- 不做令牌自动刷新（PAT 由用户自管，无过期概念，除非用户撤销）。
- 小组件不引入需要 App 端新增重数据的图表（保持 glanceable）。

## 安全模型（核心）

- 令牌只进 **Keychain**（`kSecClassGenericPassword`，`kSecAttrAccessible = afterFirstUnlockThisDeviceOnly`）：
  后台刷新在锁屏下也能读到；`ThisDeviceOnly` 保证不随备份/iCloud 迁移。
- 令牌**不写入** `data.json`、**不进** JSON 导出备份、**不上传**任何第三方；只作为
  `Authorization: Bearer <token>` 经 HTTPS 发往 `api.github.com`。
- 诊断文本只显示“已登录/未登录”，**永不回显令牌内容**。
- 登出即从 Keychain 删除。

## GitHub 登录架构（分层注入）

- 新增 `Sources/App/TokenStore.swift`：
  - `protocol TokenStore { func read() -> String?; func set(_ token: String?) throws }`
  - `enum KeychainTokenStore: TokenStore { static let shared }`（delete-then-add，幂等）。
  - `TokenStoreError.saveFailed(OSStatus)`。
- `GitHubClient`：
  - 新增 `var token: String?`（默认 nil）。
  - 私有 `applyHeaders(_:token:)` 统一设置 Accept/User-Agent/Api-Version，并在 token 非空时加
    `Authorization: Bearer`；为 nil 时与现状逐字节一致。
  - 新增 `rateLimitStatus(token:) async throws -> RateLimitInfo`：`GET /rate_limit`（**不消耗额度**），
    200 返回核心配额；401 抛 `GitHubError.notAuthorized`（新增错误用例）。
- `AppModel`：
  - 新增注入 `tokenStore: TokenStore = KeychainTokenStore.shared`（带默认值，不破坏现有测试调用点）。
  - 四个网络闭包（fetchChanges/probeRepo/probePaths/fetchVersionOptions）默认值改为在**调用时**
    读取 `tokenStore.read()` 并注入 `client.token`——登录/登出即时生效，无需重建。
  - 新增 `@Published private(set) var isAuthenticated`、`@Published var authError`、
    `func setAuthToken(_ token: String?)`（写 Keychain + 切状态 + 清错误）。
  - `diagnosticsReport()` 增一行“[GitHub] 登录：是/否”。
- `AddSourceView.search()`：直连 `GitHubClient()` 处注入 `KeychainTokenStore.shared.read()`。
- `SettingsView`：新增“GitHub 登录”区——
  - 未登录：`SecureField` 粘贴令牌 → “登录并验证”（调 `rateLimitStatus(token:)`，成功才落库）→
    成功后 `model.setAuthToken` + `refreshAll()` 刷新限额显示；附“如何创建令牌”帮助（Link 到
    `github.com/settings/personal-access-tokens/new`，建议 fine-grained：Metadata + Contents 只读）。
  - 已登录：显示状态 + 已验证额度 + “登出”。

## 令牌校验流程

1. 用户粘贴令牌 → `rateLimitStatus(token:)`。
2. 401 → `notAuthorized` → 提示“无效或已撤销”，**不落库**。
3. 200 → 读取 core limit（5000）→ `setAuthToken` → `refreshAll()` → 限额区显示 authenticated 配额。

## 小组件精致化（原生风，Medium = 两栏 (i)）

- `WidgetSnapshot`（Shared）新增可选 `headlineRelevance: Relevance?`；`WidgetSnapshotWriter` 写入
  top 项的相关性。快照为每次重写的瞬时文件，新增可选字段无迁移风险。
- 精化点：
  - 数字统一 `.monospacedDigit()`（消除 contentTransition 跳动）。
  - “最新待查看”标题旁加**相关性着色点**（值得关注=橙，其余=accent），一眼可辨是否要管。
  - `systemMedium` 两栏间加极淡竖向分隔；统一间距/层级。
  - 容器背景保持 `.fill.tertiary` + 低透明度品牌渐变（贴 App 图标青绿色系）。
- 覆盖全部家族：systemSmall / systemMedium / accessoryCircular / accessoryRectangular / accessoryInline。

## 数据流变化

未登录：与现状一致。已登录：`AppModel` 默认网络闭包在每次请求读 Keychain → `GitHubClient` 带头 →
限流响应头反映 5000 配额 → `rateLimit` 状态更新 → 设置页显示。Widget 快照新增相关性字段。

## 错误处理

- 令牌无效（401）→ `notAuthorized`，UI 明确提示，不污染本地数据。
- Keychain 写失败 → `TokenStoreError` → `authError` 展示，`isAuthenticated` 不变。
- 校验时的网络错误 → 提示重试，不影响未登录兜底。

## 测试（红绿门由 CI 承担；本机无 Xcode）

- `GitHubClientTests`：auth 头在带令牌时发送/不带时不发送；`rateLimitStatus` 200 回核心配额；
  401 抛 `notAuthorized`。复用 `MockAPIProtocol` 捕获请求。
- `AppModelTests`：`setAuthToken` 切换 `isAuthenticated` 并经注入的内存 `TokenStore` 生效；
  登出清空。
- `StabilityTests`：`WidgetSnapshot` 含 `headlineRelevance` 的编解码往返。
- 全部用依赖注入，不触碰真实 Keychain/网络（除既有默认闭包用例，行为不变）。

## 构建与交付

沿用 CI：`iOS unsigned IPA` 工作流（macos-26 / Xcode 26.6）跑单测 + 截图 + adhoc 内嵌
entitlements + 打包 IPA/SHA-256。特性分支推送后用 `gh workflow run --ref` 触发，`gh run download`
取 IPA 并 `shasum -a 256` 核对。全绿后再合并 main。
