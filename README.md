# UpstreamLens

个人使用的 iPhone 技术变更雷达。支持公开 GitHub 仓库的 Release、Tag，以及指定文件或目录路径的提交。首次检查只建立基线；后续变化会结合本机保存的用途、使用版本和关键词给出可核查的判断。主 App 数据保存在本机，Widget 只读取 App Group 中的精简快照。

## 使用流程

1. 在首页点“添加来源”，选择 Release、Tag 或路径，填写 `owner/repo`。监控 Skill 时选择“路径”，填写 `skills/example/SKILL.md` 或该 Skill 的目录。显示名称和用途可以直接填写；版本、关键词和采用理由在“更多个人信息”中。
2. 保存后首次成功检查只记录当前基线。以后打开 App 或点“手动刷新”才会检查新变化；每个来源会显示上次成功检查时间和错误。
3. 首页“待处理变化”包括未读和已查看的项目，优先显示“值得关注”。打开详情会标为已查看，但仍留在待处理列表；请核对判断理由和 GitHub 原文，再点“标为已处理”、点列表行尾的勾选，或左滑完成。
4. 已处理的项目在“已处理记录”中，可从详情重新加入待处理。小组件只统计**未读且相关**的变化，因此查看后小组件数量可能减少，而 App 中仍保留待处理项。

“已处理”只表示你完成了本地核查，不表示已经升级上游版本。个人用途和备注只保存在本机。

## 构建

本项目用 XcodeGen 生成工程。GitHub Actions 的 `iOS unsigned IPA` 工作流固定在 `macos-26`，选择 Xcode 26.6，运行单元测试、生成不签名的归档，核查 App 与 Widget 扩展后上传 IPA 和 SHA-256。工作流运行成功后，从该次 Actions 的 `UpstreamLens-unsigned` artifact 下载两个文件。下载后用 SHA-256 核对 IPA。

固定标识：

- App：`com.upstreamlens.ios`
- Widget：`com.upstreamlens.ios.widget`
- App Group：`group.com.upstreamlens.ios`

更新时保持这些标识不变。**Actions 构建成功不代表设备安装或 App Group 共享成功。**

## 安装与关口 A 验证

使用已经验证的侧载路线：首次在 Windows 用 iloader 安装下载的未签名 IPA；后续在 iPhone 的 SideStore 中选择本地 IPA 导入和续签。SideStore 操作时连接 LocalDevVPN。插线、信任、导入和续签由设备持有人操作。不要把 IPA 提前签名。Widget 扩展会占用额外的 App ID；免费 Apple ID 的七天有效期和侧载名额需要留意。

安装后先检查：

1. 主 App 可打开，首页显示空状态。
2. Widget 出现在添加小组件列表。
3. 添加公开 GitHub 来源，首次检查不产生历史变化；Widget 显示快照和检查时间。
4. 关闭网络后打开 App，旧变化仍在，时间不会伪装为实时数据。

若 Widget 显示“共享数据暂不可用”，记录设备现象；这表示 App Group 共享在实际重签链路下仍待解决。交接说明允许的公开单来源网络回退须在此关口真实失败后实现和验证。

## 当前限制

- 公开 GitHub API 无登录模式，可能触及未认证限额；个人备注不会发给 GitHub。
- 刷新依赖打开 App 或手动触发；Widget 时间线由 iOS 调度，不能当成实时提醒。
- 最多读取三页、每页 100 条上游记录；长时间未检查而超过该范围时应重新核对基线。
- JSON 导入会替换本机现有列表与变化记录，导入前先导出备份。
- 设备安装、Widget 共享行为及七天后真实自动续签均需设备持有人反馈后单独记录。
