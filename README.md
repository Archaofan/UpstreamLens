# UpstreamLens

个人使用的 iPhone 技术变更雷达。支持公开 GitHub 仓库的 Release、Tag，以及指定文件或目录路径的提交。首次检查只建立基线；后续变化会结合本机保存的用途、使用版本和关键词给出可核查的判断。主 App 数据保存在本机，Widget 只读取 App Group 中的精简快照。开发者：[@Archaofan](https://github.com/Archaofan) · [项目主页](https://github.com/Archaofan/UpstreamLens)

## 使用流程

1. **添加来源**：点右上角“+”，**搜索仓库名**或**粘贴 GitHub 链接**（支持仓库、`/tree/` 分支目录、`/blob/` 文件链接）；App 会自动读取仓库描述、默认分支、topics 和最新版本并预填。“常用预设”提供 AI 领域高星项目与 Agent 工具链的特化来源（OpenClaw、Hermes Agent、DeepSeek Harness、n8n、AutoGPT、Firecrawl、Dify、Open WebUI），点选即预填，图标取各自项目的 GitHub 头像。监控 Skill 文件时选择“路径”模式，App 会列出仓库内所有 SKILL.md 供点选。手动填写仍作为兜底入口。
2. **“正在使用的版本”可以直接下拉选择**：确认页和“编辑使用情况”会读取上游 Release/Tag 列表（1 次 API 请求），点选即填，不用背版本号；列表读取失败或想填提交 SHA 时仍可手动输入。
3. 保存后首次成功检查只记录当前基线。以后打开 App 或下拉刷新才会检查新变化；每个来源会显示上次成功检查时间和错误。
4. 首页“待处理变化”包括未读和已查看的项目，优先显示“值得关注”。打开详情会标为已查看，但仍留在待处理列表；请核对判断理由和 GitHub 原文，再点“标为已处理”、点列表行尾的勾选，或左滑完成。左滑另一侧可切换已读/未读。
5. 已处理的项目在“已处理记录”中（支持搜索），可从详情重新加入待处理。小组件只统计**未读且相关**的变化，因此查看后小组件数量可能减少，而 App 中仍保留待处理项。
6. 个人使用情况（用途、版本、关键词）可在来源详情页“编辑使用情况”中随时补充；判断引擎会引用命中的具体词句，便于回原文核查。
7. “设置”中集中了低频功能：**通知开关**（含系统授权状态）、JSON 导入/导出、**AI 批量添加来源**（复制提示词给本机 AI 生成来源清单，导入后合并监控，见下文）、已处理记录自动清理（90 天，默认关闭、开启前不会动你的旧数据）、GitHub API 限额显示、**诊断信息生成**（可一键复制发给开发者）。

## 用 AI 批量添加来源

设置 → 帮助 提供一段可复制的提示词：交给能访问你电脑/服务器的 AI（Agent CLI、IDE 助手等），它会检索你本机在用的开源项目（包管理器、依赖文件、Docker、CLI 工具），带上学到的版本号，输出 `upstreamlens.source-list` 格式的 JSON 清单。把清单存为 .json 后用“导入 AI 来源清单”导入：App 只**合并新增**（同仓库同模式自动去重跳过），不修改、不删除已有来源和个人信息，导入后立即检查一轮建立基线。

## 通知与后台检查

通知默认关闭，在“设置 → 通知”开启后按以下规则工作（参考 GitHub Notifications 与 iOS 通知规范设计）：

- 只通知“值得关注”与“影响不确定”的相关变化；“一般更新”永不打扰。同一来源的多次通知在通知中心**自动成组**，一次检查最多 5 条、超出折叠为摘要。
- “值得关注”用横幅+声音（interruption level active）；“影响不确定”静默进入通知中心（passive），是否打断完全交给系统的专注模式与定时推送摘要——App 不自建免打扰时段。
- 每个来源可在“编辑使用情况”里单独关闭通知。
- 点通知直达对应变化详情。

后台检查通过 `BGAppRefreshTask` 注册，进入后台后约每 30 分钟起一次（iOS 按使用习惯调度，可能合并、推迟或不执行，**不是实时提醒**）；后台轮次设有 API 限额预算，额度不足时自动跳过，把额度留给前台。

“已处理”只表示你完成了本地核查，不表示已经升级上游版本。个人用途和备注只保存在本机，不会发给 GitHub。

## 数据稳定性

- 每次写入前会把当前 `data.json` 轮换为 `data.json.bak`；主文件损坏时启动自动从备份恢复并提示。
- 记录总量上限 1000 条：超出时按“最旧已处理 → 最旧已查看 → 最旧未读”的顺序淘汰，防止 JSON 无限膨胀拖慢读写。

## 小组件与签名

小组件依赖 App Group 共享容器。**免费 Apple ID 侧载时，签发 profile 里的 App Group 会带上 10 位团队 ID 前缀**（如 `ABCDEF1234.group.com.upstreamlens.ios`），与 entitlements 请求的无前缀 ID 不同——这是“诊断显示权限都在、容器却拿不到”的根因。App 与 Widget 现在会在运行时从 `embedded.mobileprovision` 里解析实际授权的组名并自动适配（解析规则见 `Sources/Shared/AppGroupResolver.swift`）。本项目的 IPA 由 CI 在打包前用 adhoc codesign 把 entitlements 内嵌进 App 与 Widget 的二进制（macOS runner 上的 brew ldid 安装不可靠，已改用系统 codesign），侧载工具重签时即可读到并注册 App Group。如果小组件仍显示“共享数据暂不可用”，请在 App 内“设置 → 诊断 → 生成诊断信息”复制文本：它会显示 profile 授权的组列表、实际使用的组（是否带前缀已自动适配）、共享容器是否可获得、`embedded.mobileprovision` 与主程序二进制中是否真的包含 App Group 权限——据此可定位是哪一环把权限丢了。

## 构建

本项目用 XcodeGen 生成工程。GitHub Actions 的 `iOS unsigned IPA` 工作流固定在 `macos-26`，选择 Xcode 26.6，运行单元测试、生成不签名的归档，用 adhoc codesign 内嵌 App 与 Widget 的 entitlements（不做真实签名），核查标识、架构、entitlements 后上传 IPA 和 SHA-256。工作流运行成功后，从该次 Actions 的 `UpstreamLens-unsigned` artifact 下载两个文件。下载后用 SHA-256 核对 IPA。

固定标识：

- App：`com.upstreamlens.ios`
- Widget：`com.upstreamlens.ios.widget`
- App Group：`group.com.upstreamlens.ios`
- URL scheme：`upstreamlens://`（`findings` 打开待处理队列；`add` 打开添加页）

更新时保持这些标识不变。**Actions 构建成功不代表设备安装或 App Group 共享成功。**

## 安装与关口 A 验证

使用已经验证的侧载路线：首次在 Windows 用 iloader 安装下载的未签名 IPA；后续在 iPhone 的 SideStore 中选择本地 IPA 导入和续签。SideStore 操作时连接 LocalDevVPN。插线、信任、导入和续签由设备持有人操作。不要把 IPA 提前签名。Widget 扩展会占用额外的 App ID；免费 Apple ID 的七天有效期和侧载名额需要留意。

安装后先检查：

1. 主 App 可打开，首次启动显示新手引导（四页，看完一次后不再出现）；首页显示空状态。
2. Widget 出现在添加小组件列表（含锁屏矩形/圆形款式）。
3. 添加公开 GitHub 来源，首次检查不产生历史变化；Widget 显示快照和检查时间。
4. 若 Widget 显示“共享数据暂不可用”，在“设置 → 诊断”生成信息并记录；这表示 App Group 共享在实际重签链路下仍待解决。
5. 关闭网络后打开 App，旧变化仍在，时间不会伪装为实时数据。

## 当前限制

- 公开 GitHub API 无登录模式，核心接口每 IP 每小时 60 次、搜索接口 10 次/分钟；限流时 App 会显示预计恢复时间。私有仓库无法监控（需要开发者令牌，尚未实现）。
- 刷新依赖打开 App 或手动触发；Widget 时间线由 iOS 调度，不能当成实时提醒。
- 最多读取三页、每页 100 条上游记录；长时间未检查而超过该范围时应重新核对基线。
- JSON 导入会替换本机现有列表与变化记录，导入前先导出备份。
- 版本比较针对语义化版本（含日历版本如 2026.9.24）；无规则的 tag 名不会参与版本比较。
