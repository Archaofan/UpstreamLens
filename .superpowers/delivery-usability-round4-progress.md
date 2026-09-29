# SDD ledger — plan: docs/plans/2026-09-29-usability-round4.md

Pre-flight: 新增 init 参数全部带默认值，现有测试调用点不受影响；新文件按目录 glob 被 XcodeGen 收进对应 target（AppGroupResolver→Shared 双端，其余→App；测试文件自动进 Tests）。

仓库核实（2026-09-29，未认证 API）：openclaw/openclaw 390,739★、NousResearch/hermes-agent 249,806★、deepseek-ai/deepseek-harness 238,770★、n8n-io/n8n 206,225★、Significant-Gravitas/AutoGPT 187,595★、firecrawl/firecrawl 186,014★、langgenius/dify 157,435★、open-webui/open-webui 153,459★。

T1 小组件根因：诊断的“包含 App Group”是子串搜索，被 `<团队ID>.group.…` 前缀形态误判通过；
App 请求无前缀 ID → containerURL nil。修复 = AppGroupResolver 运行时解析（先原始 ID，再从
profile 原始字节提取授权组，优先 `.group.com.upstreamlens.ios` 后缀变体），App/Widget 双端一致。
T2 版本下拉：versionOptions 1 次核心请求；VersionPickerField（Menu + 手动兜底 + 失败重试），
接入确认页 / 编辑监控目标 / 编辑使用情况三处；path 模式保持手填 SHA。
T3 预设：8 个（用户 3 + AI 高星 5），图标 = owner 头像直链（不走 API）+ 磁盘缓存 + SF Symbol 兜底。
T4 推广：关于区加 @Archaofan / 项目主页 / ShareLink（Promotion 常量集中一处）。
T5 引导：OnboardingView 四页，hasCompletedOnboarding AppStorage，fullScreenCover。
T6 AI 清单：SourceListImport.parse（BOM/围栏/对象或数组容忍，逐条校验跳过无效）+ prompt 常量；
AppModel.mergeSourceList 按 仓库+模式+路径 判重只增不改；设置→帮助 提示词 sheet + 导入确认，
导入后 refreshAll。
T7 收尾：MARKETING_VERSION 0.3.0；README 同步（预设/版本下拉/AI 清单/引导/App Group 说明）。

测试：AppGroupResolverTests（提取/纯决策/兜底）8 例；SourceListImportTests（围栏/数组/跳过/去重/BOM）8 例；
GitHubClientTests +4（draft 过滤、tag、path 不发请求、非法仓库）；AppModelTests +2（判重合并、不覆盖个人数据）；
StabilityTests 预设断言扩展 + 图标缓存名稳定。
红绿门：Actions（本机无 Xcode，沿用 round1 ruling）。

CI loop record (usability-round4, run 36508741689 → 36509896790 → 36510840505 → 36512080961 SUCCESS):
- R1: VersionPickerField 括号失衡（Edit 序列遗留）→ 整文件重写；新增 build/check_braces.py 静态括号平衡检查
- R2: Result<_, String> 不合法（Failure: Error）→ any Error + localizedDescription
- R3: if let loadError 遮蔽 @State 属性 → 显式命名 message
- 期间 GitHub 直连多次中断（connection reset），push 用重试循环恢复
- 设备端待验证：App Group 解析是否在真实重签链路下拿到 <团队ID> 前缀容器（诊断文本会显示授权组与实际使用组）
Merge: main 49ba76f (--no-ff), final main run 36513245313 SUCCESS（IPA artifact UpstreamLens-unsigned）。
