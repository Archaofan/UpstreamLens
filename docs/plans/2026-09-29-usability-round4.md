# 计划：usability-round4（小组件修复 + 版本下拉 + 预设更换 + 推广 + 引导 + AI 来源清单）

来源：用户 2026-09-29 反馈（含设备诊断文本）。

## 背景与根因

诊断显示：embedded.mobileprovision 存在且包含组字符串、主程序 entitlements 含组字符串，但
`containerURL(forSecurityApplicationGroupIdentifier:)` 返回 nil。诊断的"包含 App Group"是子串
搜索，会被**带团队前缀的组名误判为通过**：免费 Apple ID 侧载签发的 profile 中，App Group 实际是
`<10位团队ID>.group.com.upstreamlens.ios`，而 App 请求无前缀原名 → 不匹配 → 无容器。

## 任务

1. **T1 小组件修复**：新增 `Sources/Shared/AppGroupResolver.swift`（App/Widget 两个 target 共用）。
   运行时：先试原始 ID；失败则从 embedded.mobileprovision 原始字节提取实际授权的组（以 `group.`
   为锚向左扩展合法字符，兼容 XML/二进制 plist，无需解析 CMS），挑选 `<团队ID>.group.…` 变体，
   逐个验证 containerURL。`WidgetSnapshotWriter.groupID` 改为解析值；Widget 读路径同步。诊断
   报告输出：请求 ID / profile 授权组列表 / 实际使用组。
2. **T2 版本下拉**：`GitHubClient.versionOptions(repository:kind:)`（1 次核心请求，release 过滤
   draft、tag 直读）；`AppModel.versionOptions` 注入闭包透传；新组件 `VersionPickerField`
   （Menu 下拉 + 手动输入兜底 + 失败提示），接入 RepoConfirmView、PersonalContextEditorView、
   SourceEditorView（经可选 loader 闭包）。path 模式仍为手填 SHA。
3. **T3 预设更换**：现 4 个预设（swift/evolution/xcodes/superpowers）换成用户指定 3 个 + AI 高星
   5 个：openclaw/openclaw、NousResearch/hermes-agent、deepseek-ai/deepseek-harness、n8n-io/n8n、
   Significant-Gravitas/AutoGPT、firecrawl/firecrawl、langgenius/dify、open-webui/open-webui
   （均 release 模式，2026-09-29 已用未认证 API 核实公开可达与星数）。
   图标：`https://github.com/<owner>.png?size=120`（不走 API 不限额），磁盘缓存 + SF Symbol 兜底。
4. **T4 推广**：设置 → 关于 增加开发者 @Archaofan、项目主页链接与 ShareLink。
5. **T5 新手引导**：首次启动 fullScreenCover 四页（用途/添加来源/通知预期/隐私），
   `hasCompletedOnboarding` AppStorage 记忆。
6. **T6 AI 来源清单**：设置 → 帮助 提供可复制提示词（让 AI 检索本机在用开源项目并按
   `upstreamlens.source-list` schema 输出 JSON）；新增"导入 AI 来源清单（合并）"，解析容忍 BOM/
   代码围栏/数组或对象两种形态，逐条校验 repository，按 仓库+模式+路径 判重合并（不覆盖不删除），
   导入后立即 refreshAll。
7. **T7 收尾**：project.yml 版本 0.3.0；README 同步（预设、版本下拉、引导、AI 清单、App Group
   团队前缀说明）。

## 测试（红绿门由 Actions 承担）

- AppGroupResolverTests：组提取（XML/二进制形态、多组、排除无关组）、preferredGroupID 纯决策、
  resolve 兜底不崩。
- SourceListImportTests：围栏剥离、对象/数组、kind 映射、无效条目警告跳过、notJSON。
- GitHubClientTests：versionOptions release 过滤 draft / tag 直读 / path 空数组且不发请求。
- AppModelTests：mergeSourceList 判重与计数。
- StabilityTests：预设 id 唯一、图标 URL 形态、缓存文件名稳定。

## 约束

- 本机无 Xcode：同批提交代码+测试，Actions 单测为门（沿用 round1 ruling）。
- 新字段全部可选，旧备份解码不受影响；不动现有数据 schema。
- API 预算：版本下拉每次打开编辑页 +1 次核心请求，确认页说明文案同步。
