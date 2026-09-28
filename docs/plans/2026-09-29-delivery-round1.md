# UpstreamLens delivery round 1 — 交付计划

Date: 2026-09-29. Branch: delivery-round1. Spec authority: 本对话三轮方案（调研报告、配置简化方案、App Group 诊断）。

## Global constraints

- 本机无 Xcode：所有编译/测试只能经 GitHub Actions（macos-26 / Xcode 26.6）验证。TDD 的红绿循环以 CI 为准：每批改动推送后必须确认 Actions 全绿才可进入下一批。
- 保持 bundle ID / App Group / URL scheme 不变；旧 JSON 备份必须可无损导入。
- 不堆砌功能：不新增 Provider 抽象、不做 Share Extension（占 App ID 名额）、不做多语言。
- 判断理由必须可核查（引用命中词句），数据仅存本机。

## Tasks

- T1 CI：ldid 内嵌 entitlements（app+widget），断言改为 adhoc + entitlements 含 group；保留无 mobileprovision 断言。
- T2 数据层：schemaVersion(可选 Int?)、retentionDays(可选 Int?, 默认 90)、WatchSource 元数据缓存字段(repoDescription/defaultBranch/topics)、Finding.isPrerelease；批量操作 markAllRead/markAllHandled/clearHandledRecords；保留策略清理；角标注入闭包；诊断纯函数。
- T3 判断引擎 v2：ASCII 词边界、CJK 子串、breaking/security 词表、semver 比较(VersionCompare)、预发布降级、理由引用命中词。
- T4 网络层：共享 ISO8601(含毫秒回退)、限流头解析与错误带恢复时间、瞬时错误一次重试、ParsedGitHubURL、searchRepositories/repoMetadata/latestRelease/treePaths、tag 正文按 sha 关联 commits、releases 预发布标记。
- T5 AppModel：rateLimit 状态、probe/probePaths 注入闭包、findings 保留清理时机、诊断构建器（profile 二进制搜索 group、容器读写测试、汇总文本）。
- T6 UI：AddSourceView(搜索/粘贴/手动)、RepoConfirmView(元数据预填+SKILL 候选+版本预填)、深链接 onOpenURL、剪贴板横幅(detectPatterns 不触发粘贴弹窗)、批量操作入口、历史搜索、diff 视图、markdown 渲染、设置页(诊断/数据/限额/关于)。
- T7 Widget：accessoryRectangular/accessoryCircular 家族。
- T8 测试全套：VersionCompare、Relevance v2、URL 解析、Diff、Diagnostics 纯函数、存储向后兼容、AppModel 新操作、GitHubClient(URLProtocol mock：搜索/元数据/latest404/限流头/tag 正文)。
- T9 文档：README 更新使用流程、诊断说明、签名修复记录。
- T10 交付：合并 main、dispatch 构建、产出 IPA + SHA256；生成 deliverables/UpstreamLens-config.json（基于设备调研：7 个公开仓库，chaofanhermes 私有不可监控需注明）。

## Review focus

- 旧备份导入零丢失；新增字段全部可选。
- 未认证限额预算：添加流程 ≤3 核心调用/来源；搜索独立桶。
- 剪贴板检测绝不自动读取内容。
- UI 保持清爽：设置页集中低频功能，首页不新增噪音。
